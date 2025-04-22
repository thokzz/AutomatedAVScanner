// AppCoordinator.swift (Fixed with aggressive finalization and fallback printing)
import Foundation
import Combine
import UserNotifications
import AVFoundation
import AppKit

extension Notification.Name {
    static let physicalDriveFullyScanned = Notification.Name("physicalDriveFullyScanned")
}

@MainActor
class AppCoordinator: ObservableObject {
    let volumeMonitor = VolumeMonitor()
    let transactionManager = TransactionManager()

    @Published var connectedVolumes: [ExternalVolume] = []
    @Published var volumeStates: [String: VolumeScanState] = [:]
    @Published var activeTab: Int = 0
    @Published var autoScanEnabled: Bool = true
    @Published var autoPrintEnabled: Bool = true

    private var processingVolumes = Set<String>()
    private var scanTasks: [String: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var completedPhysicalDrives = Set<String>()
    private var notificationObserver: NSObjectProtocol?

    init() {
        observeVolumes()
        setupNotifications()

        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task {
                await PrintManager().cleanupOldPrintRecords()
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForceRescan),
            name: Notification.Name("ForceRescanRequested"),
            object: nil
        )
        notificationObserver = NotificationCenter.default.addObserver(
                forName: .physicalDriveFullyScanned,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handlePhysicalDriveFullyScanned(notification)
            }

            Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task {
                    await self?.retryLatePrintsIfNeeded()
                }
            }
        }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func retryLatePrintsIfNeeded() async {
        let lateStates = volumeStates.values.filter {
            $0.scanProgress >= 1.0 &&
            !$0.hasPrinted &&
            FileManager.default.fileExists(atPath: $0.volume.path.path) &&
            !(PhysicalDriveTracker.shared.getDriveKey(for: $0.volume)
                .map { completedPhysicalDrives.contains($0) } ?? false)
        }



        guard !lateStates.isEmpty else { return }

        print("🔁 Found \(lateStates.count) late partitions needing print...")

        for state in lateStates {
            do {
                let bookmark = state.volume.path.startAccessingSecurityScopedResource()
                defer { if bookmark { state.volume.path.stopAccessingSecurityScopedResource() } }

                try await PrintManager().printScanResults(for: state)
                state.hasPrinted = true
                transactionManager.updateTransactionPrintTimeByVolumeUUID(volumeUUID: state.volume.volumeUUID)

                print("✅ Late print succeeded for \(state.volume.name)")
            } catch {
                print("❌ Late print failed for \(state.volume.name): \(error.localizedDescription)")
            }
        }
    }

    private func observeVolumes() {
        volumeMonitor.$connectedVolumes
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectedVolumes)

        volumeMonitor.$volumeStates
            .receive(on: DispatchQueue.main)
            .assign(to: &$volumeStates)

        NotificationCenter.default.publisher(for: .newVolumeConnected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let volume = notification.object as? ExternalVolume else { return }

                print("🧩 Volume added: \(volume.name) [\(volume.volumeUUID)]")

                if WhitelistManager.shared.isWhitelisted(volume: volume) {
                    print("🛑 Volume \(volume.name) is whitelisted. Skipping scan.")
                    return
                }

                if self.autoScanEnabled {
                    if let driveKey = PhysicalDriveTracker.shared.getDriveKey(for: volume) {
                        self.completedPhysicalDrives.remove(driveKey) // 🛠 ALLOW RESCAN on reinsertion
                    }
                    self.startScanningVolume(volume)
                } else {
                    print("🛑 Auto scan disabled. Skipping scan for \(volume.name)")
                }
            }
            .store(in: &cancellables)
    }

    private func setupNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }
    
    func isPhysicalDriveCompleted(driveKey: String) -> Bool {
        return completedPhysicalDrives.contains(driveKey)
    }
    
    func debugDriveStatus() {
        print("🔍 DEBUG: Currently tracking \(completedPhysicalDrives.count) completed drives:")
        for driveKey in completedPhysicalDrives {
            print("   - \(driveKey)")
        }
        print("🔍 DEBUG: Processing volumes: \(processingVolumes.count)")
        for volumeKey in processingVolumes {
            print("   - \(volumeKey)")
        }
    }
    
    func startScanningVolume(_ volume: ExternalVolume) {
        let volumeKey = "\(volume.volumeUUID)-\(volume.name)"
        
        // Important: Always reset state when explicitly starting a scan
        if let state = volumeStates[volumeKey] {
            // Reset scan state to ensure it starts fresh
            state.scanStatus = .queued
            state.scanProgress = 0.0
            state.scannedFiles = 0
            state.lastScannedFile = ""
            state.infectedFiles = []
            state.error = nil
            
            // No need to check if we're already processing - this is a manual trigger
            processingVolumes.remove(volumeKey)
        }
        
        // Make sure to clear from completed drives list no matter what
        if let driveKey = PhysicalDriveTracker.shared.getDriveKey(for: volume) {
            print("🔄 Explicitly clearing drive \(driveKey) from completed list for rescan")
            completedPhysicalDrives.remove(driveKey)
            
            // Also explicitly clear the drive from PhysicalDriveTracker's tracking
            PhysicalDriveTracker.shared.resetDriveState(key: driveKey)
        }
        
        // Get fresh state after possible modifications
        guard let state = volumeStates[volumeKey], !processingVolumes.contains(volumeKey) else {
            print("⚠️ Cannot start scan: state not found or volume already processing")
            return
        }

        print("🚀 Starting fresh scan for \(volume.name)")
        let task = ScanHandler.shared.startScanning(
            volume: volume,
            state: state,
            autoPrintEnabled: autoPrintEnabled,
            volumeMonitor: volumeMonitor,
            notify: showNotification,
            playEjectCue: playEjectCueIfNeeded
        )

        scanTasks[volumeKey] = task
        processingVolumes.insert(volumeKey)
    }


    func cancelScanForVolume(_ volume: ExternalVolume) {
        let volumeKey = "\(volume.volumeUUID)-\(volume.name)"
        scanTasks[volumeKey]?.cancel()
        scanTasks.removeValue(forKey: volumeKey)
        processingVolumes.remove(volumeKey)
        FileCounter().cancelCounting()
        ScanEngine().cancelScan()
        volumeMonitor.markVolumeAsDoneScanning(volume)
    }
    
    @objc private func handleForceRescan(_ notification: Notification) {
        if let driveKey = notification.userInfo?["driveKey"] as? String {
            print("📣 Received force rescan request for drive \(driveKey)")
            completedPhysicalDrives.remove(driveKey)
        }
    }
    // Modify the handlePhysicalDriveFullyScanned function in AppCoordinator:
    @objc private func handlePhysicalDriveFullyScanned(_ notification: Notification) {
        guard let partitions = notification.userInfo?["partitions"] as? [ExternalVolume],
              let driveKey = notification.userInfo?["driveKey"] as? String else {
            print("❌ Notification missing required info.")
            return
        }

        guard !completedPhysicalDrives.contains(driveKey) else {
            print("🔄 Drive \(driveKey) already processed.")
            return
        }

        // Add this mutex set to prevent duplicate processing
        completedPhysicalDrives.insert(driveKey)

        Task {
            // FIXED: Longer delay to ensure all states are updated
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // Get the latest states since they might have changed
            let allDriveStates: [VolumeScanState] = partitions.compactMap {
                let key = "\($0.volumeUUID)-\($0.name)"
                return volumeStates[key]
            }

            print("🔍 Found \(allDriveStates.count)/\(partitions.count) volume states for drive \(driveKey)")
            
            var finalPrintQueue: [VolumeScanState] = []
            // Track already processed partitions in this session to prevent duplicates
            var alreadyProcessedInSession = Set<String>()

            for state in allDriveStates {
                if state.scanProgress >= 1.0 && state.scanStatus == .waiting {
                    print("⚠️ Finalizing stuck .waiting status for \(state.volume.name)")
                    state.scanStatus = state.infectedFiles.isEmpty ? .clean : .infected
                }

                // Prevent duplicate processing in this session
                let volumeKey = "\(state.volume.volumeUUID)-\(state.volume.name)"
                if alreadyProcessedInSession.contains(volumeKey) {
                    print("⚠️ Already processed \(state.volume.name) in this session - skipping")
                    continue
                }
                alreadyProcessedInSession.insert(volumeKey)

                // FIXED: Make sure the volume actually exists before adding to print queue
                if !state.hasPrinted && FileManager.default.fileExists(atPath: state.volume.path.path) {
                    print("📋 Adding \(state.volume.name) to final print queue")
                    finalPrintQueue.append(state)
                } else if !FileManager.default.fileExists(atPath: state.volume.path.path) {
                    print("⚠️ Volume \(state.volume.name) no longer exists - skipping print")
                } else if state.hasPrinted {
                    print("✓ Volume \(state.volume.name) already printed - skipping")
                }
            }

            if finalPrintQueue.isEmpty {
                print("📦 All partitions already printed for drive \(driveKey), proceeding to eject")

                // Pick any partition that still exists for ejection
                let availablePartitions = partitions.filter {
                    FileManager.default.fileExists(atPath: $0.path.path)
                }

                if let firstAvailable = availablePartitions.first {
                    DriveEjectHandler.shared.attemptEject(
                        driveKey: driveKey,
                        partition: firstAvailable,
                        allPartitionsPrinted: true,
                        volumeMonitor: volumeMonitor,
                        notify: showNotification
                    )
                } else {
                    print("🛑 No valid partition available to eject for drive \(driveKey)")
                }

                PhysicalDriveTracker.shared.clearDrive(key: driveKey)
                
                // Extra safety delay before removing from completed list
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                    await MainActor.run {
                        completedPhysicalDrives.remove(driveKey)
                    }
                }
                return
            }

            // FIXED: Updated approach to printing
            let hasInfected = finalPrintQueue.contains { !$0.infectedFiles.isEmpty }
            let waitTime: UInt64 = hasInfected ? 3_000_000_000 : 2_000_000_000 // Longer waits
            
            print("🖨️ Starting sequential print for \(finalPrintQueue.count) partitions (infected: \(hasInfected))")
            let success = await PrintHandler.shared.printPartitionsSequentially(
                partitions: finalPrintQueue,
                printManager: PrintManager(),
                transactionManager: transactionManager,
                waitAfterPrint: waitTime,
                notify: showNotification
            )

            for state in finalPrintQueue {
                await ensureTransactionRecorded(for: state.volume, state: state)
            }

            // Force a refresh of the transactions in the UI
            transactionManager.refreshTransactions()

            // FIXED: Better logic to find an available partition for ejection
            let availablePartitions = partitions.filter {
                FileManager.default.fileExists(atPath: $0.path.path)
            }
            
            if let firstAvailable = availablePartitions.first {
                print("🔌 Attempting to eject drive \(driveKey) using partition \(firstAvailable.name)")
                
                // Monterey-specific handling - ensure we have a long enough delay

                if #available(macOS 12.0, *), !ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0)) {
                    // Extra delay on Monterey before ejection to ensure audio system is ready
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                }
                
                DriveEjectHandler.shared.attemptEject(
                    driveKey: driveKey,
                    partition: firstAvailable,
                    allPartitionsPrinted: success,
                    volumeMonitor: volumeMonitor,
                    notify: showNotification
                )
                self.playEjectCueIfNeeded(for: driveKey)
                print("self.playEjectCueIfNeeded(for: driveKey)")
                
            } else {
                print("🛑 No partitions left for safe ejection for drive \(driveKey)")
                PhysicalDriveTracker.shared.clearDrive(key: driveKey)
                completedPhysicalDrives.remove(driveKey)
            }
            
            // Use a longer delay on Monterey specifically
            let cleanupDelay: TimeInterval = {
                if #available(macOS 12.0, *), !ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0)) {
                    return 4.0 // 4 seconds on Monterey
                }
                return 2.0 // 2 seconds on other macOS versions
            }()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + cleanupDelay) { [weak self] in
                if let self = self {
                    print("⏲️ Clearing drive \(driveKey) from completed drives (timed cleanup)")
                    self.completedPhysicalDrives.remove(driveKey)
                }
            }
        }
    }

    private func playEjectCueIfNeeded(for driveKey: String) {
        print("🔊 Playing audio cue for \(driveKey)")
        
        // First play with the regular implementation
        AudioCueManager.shared.play(.driveSafeToRemove)
        
        // For Monterey specifically, add an extra redundant approach
        if #available(macOS 12.0, *), !ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0)) {
            // Schedule a second attempt after a short delay
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                print("🔊 Secondary audio cue attempt for \(driveKey) (Monterey specific)")
                AudioCueManager.shared.play(.driveSafeToRemove)
                
                // On Monterey, also try a system beep as an extra fallback
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSSound.beep()
                }
            }
        }
    }

    private func ensureTransactionRecorded(for volume: ExternalVolume, state: VolumeScanState) async {
        let exists = transactionManager.transactions.contains {
            $0.volumeUUID == volume.volumeUUID && $0.volumeName == volume.name
        }

        if !exists {
            print("📝 Recording transaction for \(volume.name)")
            if state.scanStatus != .clean && state.scanStatus != .infected {
                    state.scanStatus = state.infectedFiles.isEmpty ? .clean : .infected
                }
                transactionManager.addTransaction(from: state) // ⬅️ Record transaction first
                state.hasPrinted = true // ⬅️ Mark printed after transaction saved
            }
    }

    func printTransaction(_ transaction: ScanTransaction) async -> Bool {
        let volume = ExternalVolume(
            name: transaction.volumeName,
            path: URL(fileURLWithPath: "/"),
            volumeUUID: transaction.volumeUUID
        )
        let state = VolumeScanState(volume: volume)
        state.scanStartTime = transaction.scanStartTime
        state.scanEndTime = transaction.scanEndTime
        state.fileCount = transaction.fileCount
        state.scannedFiles = transaction.fileCount
        state.infectedFiles = transaction.infectedFiles
        state.scanProgress = 1.0

        let result = await PrintManager().tryPrintScanResults(for: state)
        if result {
            transactionManager.updateTransactionPrintTime(id: transaction.id)
        }
        return result
    }

    private func showNotification(title: String, message: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
