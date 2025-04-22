import Foundation
import Combine
import AppKit
import AVFoundation
import UserNotifications

extension Notification.Name {
    static let newVolumeConnected = Notification.Name("newVolumeConnected")
}

@MainActor
class VolumeMonitor: ObservableObject {
    @Published var connectedVolumes: [ExternalVolume] = []
    @Published var volumeStates: [String: VolumeScanState] = [:]
    
    private var cancellables = Set<AnyCancellable>()
    private let workspace = NSWorkspace.shared
    private let driveTracker = PhysicalDriveTracker.shared
    private let transactionManager = TransactionManager()
    
    // Keep track of volumes that are part of multi-partition drives
    private var processingMultiPartitionVolumes: Set<String> = []
    private var ejectingDrives: Set<String> = []
    // Add this to track volumes that are actively being scanned
    private var activelyScanning: Set<String> = []
    // Add this to track completed drives
    private var completedPhysicalDrives: Set<String> = []
    
    init() {
        setupVolumeMonitoring()
        refreshConnectedVolumes()
    }
    
    private func setupVolumeMonitoring() {
        let center = workspace.notificationCenter
        
        center.publisher(for: NSWorkspace.didMountNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleVolumeMounted(notification)
            }
            .store(in: &cancellables)
        
        center.publisher(for: NSWorkspace.willUnmountNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleVolumeUnmounted(notification)
            }
            .store(in: &cancellables)
        
        center.publisher(for: NSWorkspace.didUnmountNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleVolumeUnmounted(notification)
            }
            .store(in: &cancellables)
        
    }
    
    
    
    // Add missing methods to handle notifications and support volume monitoring
    private func showNotification(title: String, message: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    private func ensureTransactionRecorded(for volume: ExternalVolume, state: VolumeScanState) async {
        let exists = transactionManager.transactions.contains {
            $0.volumeUUID == volume.volumeUUID && $0.volumeName == volume.name
        }
        
        if !exists {
            print("📝 Recording transaction for \(volume.name)")
            if state.scanEndTime == nil { state.scanEndTime = Date() }
            if state.scanStatus != .clean && state.scanStatus != .infected {
                state.scanStatus = state.infectedFiles.isEmpty ? .clean : .infected
            }
            transactionManager.addTransaction(from: state)
        }
    }
    
    private func playEjectCueIfNeeded(for driveKey: String) {
        print("🔊 Playing audio cue for \(driveKey)")
        AudioCueManager.shared.play(.driveSafeToRemove)
    }
    
    @objc private func handlePhysicalDriveFullyScanned(_ notification: Notification) {
        // This method is intentionally left empty to prevent duplicate handling
        // The AppCoordinator will handle this notification instead
        print("⚠️ VolumeMonitor.handlePhysicalDriveFullyScanned called, but this should be handled by AppCoordinator")
            }
    
    // In VolumeMonitor class where you process new volumes
    func processNewVolume(_ volume: ExternalVolume) {
        // Extract the physical drive key from the BSD name
        if let bsdName = volume.bsdName, let baseDrive = extractBaseDriveName(from: bsdName) {
            PhysicalDriveTracker.shared.addVolume(volume, bsdName: baseDrive)
            
            // Update each volume's state to know it's part of a multi-partition drive
            let key = "\(volume.volumeUUID)-\(volume.name)"
            let state = volumeStates[key]
            state?.updateSiblingInfo()  // This will set isPartOfMultiPartitionDrive
        }
    }

    private func extractBaseDriveName(from bsdName: String) -> String? {
        if let match = bsdName.range(of: #"^disk\d+"#, options: .regularExpression) {
            return String(bsdName[match])
        }
        return nil
    }
    
    private func handleVolumeMounted(_ notification: Notification) {
        guard let volumePath = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL,
              isExternalVolume(at: volumePath) else { return }
        
        addExternalVolumeIfNeeded(from: volumePath)
    }
    
    private func handleVolumeUnmounted(_ notification: Notification) {
        guard let volumePath = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
        let uuid = getVolumeUUID(for: volumePath) ?? ""
        let volumeName = volumePath.lastPathComponent
        let volumeKey = "\(uuid)-\(volumeName)"
        
        let bsdName = getBSDName(for: volumePath)
        let physicalDriveKey = bsdName?.replacingOccurrences(of: #"(disk\\d+)s\\d+"#, with: "$1", options: .regularExpression)
        
        let isPartOfEjectingDrive = physicalDriveKey != nil && ejectingDrives.contains(physicalDriveKey!)
        
        // FIX: Prevent removal if this volume is actively being scanned
        if processingMultiPartitionVolumes.contains(volumeKey) ||
           isPartOfEjectingDrive ||
           activelyScanning.contains(volumeKey) {
            print("🔄 Keeping volume \(volumeName) in UI despite ejection.")
            return
        }
        
        if let state = volumeStates[volumeKey], !state.hasPrinted {
            print("🔄 Holding back unmount of \(volumeName) until printing completes.")
            return
        }
        
        // FIX: Check if this volume is part of a multi-partition drive with active scans
        if let physicalDriveKey = physicalDriveKey,
           let partitions = driveTracker.physicalDrives[physicalDriveKey]?.partitions {
            for partition in partitions {
                let partitionKey = "\(partition.volumeUUID)-\(partition.name)"
                if activelyScanning.contains(partitionKey) {
                    print("🔄 Keeping volume \(volumeName) in UI because sibling partition is being scanned.")
                    return
                }
            }
        }
        
        connectedVolumes.removeAll { $0.volumeUUID == uuid }
        volumeStates.removeValue(forKey: volumeKey)
    }
    
    func ejectPhysicalDrive(for volume: ExternalVolume, completion: @escaping (Bool, String?) -> Void) {
        guard let bsdName = volume.bsdName else {
            completion(false, "Missing BSD Name for ejection.")
            return
        }
        
        let masterBSD = bsdName.replacingOccurrences(of: #"(disk\\d+)s\\d+"#, with: "$1", options: .regularExpression)
        
        DispatchQueue.global().async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            task.arguments = ["eject", masterBSD]
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let success = task.terminationStatus == 0
                DispatchQueue.main.async {
                    completion(success, success ? nil : "diskutil eject failed (code: \(task.terminationStatus))")
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
    
    // FIX: Add methods to track scanning status
    func markVolumeAsScanning(_ volume: ExternalVolume) {
        let volumeKey = "\(volume.volumeUUID)-\(volume.name)"
        activelyScanning.insert(volumeKey)
        
        // Also mark sibling partitions to prevent them from being removed
        if let bsdName = volume.bsdName {
            let masterBSD = bsdName.replacingOccurrences(of: #"(disk\\d+)s\\d+"#, with: "$1", options: .regularExpression)
            let partitions = driveTracker.getPartitions(for: masterBSD)
            
            for partition in partitions {
                if partition.volumeUUID != volume.volumeUUID {
                    let siblingKey = "\(partition.volumeUUID)-\(partition.name)"
                    processingMultiPartitionVolumes.insert(siblingKey)
                }
            }
        }
    }
    
    func markVolumeAsDoneScanning(_ volume: ExternalVolume) {
        let volumeKey = "\(volume.volumeUUID)-\(volume.name)"
        activelyScanning.remove(volumeKey)
        
        // Only remove sibling partitions from processing if all scans are done
        if let bsdName = volume.bsdName {
            let masterBSD = bsdName.replacingOccurrences(of: #"(disk\\d+)s\\d+"#, with: "$1", options: .regularExpression)
            let partitions = driveTracker.getPartitions(for: masterBSD)
            
            let anyPartitionStillScanning = partitions.contains { partition in
                let partitionKey = "\(partition.volumeUUID)-\(partition.name)"
                return activelyScanning.contains(partitionKey)
            }
            
            if !anyPartitionStillScanning {
                for partition in partitions {
                    if partition.volumeUUID != volume.volumeUUID {
                        let siblingKey = "\(partition.volumeUUID)-\(partition.name)"
                        // Only remove from processing if not part of ejecting drive
                        if !ejectingDrives.contains(masterBSD) {
                            processingMultiPartitionVolumes.remove(siblingKey)
                        }
                    }
                }
            }
        }
    }
    
    func refreshConnectedVolumes() {
        let fileManager = FileManager.default
        guard let volumeURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeUUIDStringKey,
                .volumeNameKey,
                .volumeIsRemovableKey,
                .volumeIsEjectableKey
            ],
            options: []
        ) else { return }
        
        var updatedVolumes: [ExternalVolume] = []
        
        // First, collect all currently mounted volumes
        for url in volumeURLs {
            guard isExternalVolume(at: url),
                  let uuid = getVolumeUUID(for: url) else { continue }
            
            let name = url.lastPathComponent
            let key = "\(uuid)-\(name)"
            
            // Get BSD name (disk identifier) for this volume
            let bsdName = getBSDName(for: url)
            
            // Get physical drive key
            let physicalDriveKey = bsdName?.replacingOccurrences(of: #"(disk\d+)s\d+"#, with: "$1", options: .regularExpression)
            
            // Skip if this volume is part of a drive being ejected
            if physicalDriveKey != nil && ejectingDrives.contains(physicalDriveKey!) {
                print("🚫 Skipping volume \(name) as it's part of a drive that's being ejected: \(physicalDriveKey!)")
                continue
            }
            
            if let existingIndex = connectedVolumes.firstIndex(where: { $0.volumeUUID == uuid }) {
                var existing = connectedVolumes[existingIndex]
                existing.bsdName = bsdName
                updatedVolumes.append(existing)
                
                // Update the drive tracker
                if let bsdName = bsdName {
                    driveTracker.addVolume(existing, bsdName: bsdName)
                }
            } else {
                let volume = ExternalVolume(name: name, path: url, volumeUUID: uuid, bsdName: bsdName)
                print("🔁 New external volume found: \(volume.name) at \(volume.path.path)" + (bsdName != nil ? " (BSD: \(bsdName!))" : ""))
                
                // Update the drive tracker
                if let bsdName = bsdName {
                    driveTracker.addVolume(volume, bsdName: bsdName)
                }
                
                AudioCueManager.shared.play(.driveDetected)
                updatedVolumes.append(volume)
                
                if volumeStates[key] == nil {
                    let state = VolumeScanState(volume: volume)
                    
                    // Update multi-partition properties
                    if let bsdName = bsdName {
                        let siblings = driveTracker.getPartitions(for: bsdName).filter { $0.volumeUUID != volume.volumeUUID }
                        state.isPartOfMultiPartitionDrive = !siblings.isEmpty
                        state.siblingPartitionCount = siblings.count
                    }
                    
                    volumeStates[key] = state
                }
                
                NotificationCenter.default.post(name: .newVolumeConnected, object: volume)
            }
        }
        
        // Next, add volumes that are part of multi-partition drives being processed or actively scanning
        // These might be physically ejected but we want to keep them in the UI
        let trackedKeys = processingMultiPartitionVolumes.union(activelyScanning)
        
        for key in trackedKeys {
            if let state = volumeStates[key], !updatedVolumes.contains(where: { "\($0.volumeUUID)-\($0.name)" == key }) {
                // This is a volume we want to keep tracking even though it's been ejected
                updatedVolumes.append(state.volume)
                print("🔄 Keeping ejected volume \(key) in UI for multi-partition coordination or ongoing scan")
            }
        }
        
        // Update all partition counts for multi-partition drives
        for (_, state) in volumeStates {
            if let bsdName = state.volume.bsdName {
                let siblings = driveTracker.getPartitions(for: bsdName).filter { $0.volumeUUID != state.volume.volumeUUID }
                state.isPartOfMultiPartitionDrive = !siblings.isEmpty
                state.siblingPartitionCount = siblings.count
            }
        }
        
        // Update the connected volumes list
        connectedVolumes = updatedVolumes
        
        // Clean up any volume states that no longer have a matching connected volume
        // and are not marked for preservation
        let volumeKeys = Set(connectedVolumes.map { "\($0.volumeUUID)-\($0.name)" })
        let preserveKeys = volumeKeys.union(processingMultiPartitionVolumes).union(activelyScanning)
        
        for key in volumeStates.keys {
            if !preserveKeys.contains(key) {
                // Only remove if not scanning and not in processingMultiPartitionVolumes
                if let state = volumeStates[key],
                   state.scanStatus != .scanning &&
                    state.scanStatus != .counting {
                    volumeStates.removeValue(forKey: key)
                }
            }
        }
    }
    
    private func addExternalVolumeIfNeeded(from url: URL) {
        let volumeUUID = getVolumeUUID(for: url) ?? UUID().uuidString
        let volumeName = url.lastPathComponent
        let bsdName = getBSDName(for: url)
        
        // Check if this is part of a drive being ejected
        let physicalDriveKey = bsdName?.replacingOccurrences(of: #"(disk\d+)s\d+"#, with: "$1", options: .regularExpression)
        if physicalDriveKey != nil && ejectingDrives.contains(physicalDriveKey!) {
            print("🚫 Ignoring volume \(volumeName) as it's part of a drive that's being ejected: \(physicalDriveKey!)")
            return
        }
        
        let volume = ExternalVolume(name: volumeName, path: url, volumeUUID: volumeUUID, bsdName: bsdName)
        
        if !connectedVolumes.contains(where: { $0.volumeUUID == volume.volumeUUID }) {
            print("🔌 External partition mounted: \(volume.name) at \(volume.path.path)" + (bsdName != nil ? " (BSD: \(bsdName!))" : ""))
            
            // Add to drive tracker
            if let bsdName = bsdName {
                driveTracker.addVolume(volume, bsdName: bsdName)
            }
            
            AudioCueManager.shared.play(.driveDetected)
            connectedVolumes.append(volume)
            let key = "\(volume.volumeUUID)-\(volume.name)"
            
            let state = VolumeScanState(volume: volume)
            
            // Update multi-partition properties
            if let bsdName = bsdName {
                let siblings = driveTracker.getPartitions(for: bsdName).filter { $0.volumeUUID != volume.volumeUUID }
                state.isPartOfMultiPartitionDrive = !siblings.isEmpty
                state.siblingPartitionCount = siblings.count
            }
            
            volumeStates[key] = state
            NotificationCenter.default.post(name: .newVolumeConnected, object: volume)
        }
    }
    
    private func getVolumeUUID(for url: URL) -> String? {
        try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }
    
    // Replace the existing isExternalVolume method with this comprehensive version
    private func isExternalVolume(at url: URL) -> Bool {
        // First check if this is a network volume
        if isNetworkVolume(at: url) {
            print("🌐 Ignoring network volume: \(url.path)")
            return false
        }
        
        // Then check if it's an external volume we should scan
        guard let values = try? url.resourceValues(forKeys: [
            .volumeIsRemovableKey,
            .volumeIsEjectableKey
        ]) else {
            return false
        }
        
        // Consider a volume external if it's either removable, ejectable, or in /Volumes/
        let isExternal = (values.volumeIsRemovable == true ||
                          values.volumeIsEjectable == true ||
                          url.path.hasPrefix("/Volumes/"))
        
        if isExternal {
            print("💾 Detected external volume: \(url.path)")
        }
        
        return isExternal
    }
    
    // Helper method to check if a volume is a network drive
    private func isNetworkVolume(at url: URL) -> Bool {
        // Method 1: Check URL scheme directly
        let urlString = url.absoluteString
        if urlString.hasPrefix("smb://") ||
            urlString.hasPrefix("afp://") ||
            urlString.hasPrefix("nfs://") ||
            urlString.hasPrefix("cifs://") {
            return true
        }
        
        // Method 2: Check volume format description
        do {
            let values = try url.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey])
            if let format = values.volumeLocalizedFormatDescription {
                if format.contains("SMB") ||
                    format.contains("AFP") ||
                    format.contains("NFS") ||
                    format.contains("CIFS") ||
                    format.contains("WebDAV") ||
                    format.contains("Network") {
                    return true
                }
            }
        } catch {
            // Ignore errors here
        }
        
        // Method 3: Use diskutil info
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["info", url.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            
            guard let output = String(data: data, encoding: .utf8) else { return false }
            
            // Look for specific indicators of network drives in diskutil output
            if output.contains("Protocol: AFP") ||
                output.contains("Protocol: SMB") ||
                output.contains("Protocol: NFS") ||
                output.contains("Type: Network") ||
                output.contains("Type: autofs") ||
                output.contains("File System: autofs") ||
                (output.contains("Mount Point: /Volumes/") && output.contains("Type: network")) {
                return true
            }
        } catch {
            // Ignore errors here
        }
        
        // Method 4: Check mount command output
        let mountTask = Process()
        mountTask.executableURL = URL(fileURLWithPath: "/sbin/mount")
        
        let mountPipe = Pipe()
        mountTask.standardOutput = mountPipe
        
        do {
            try mountTask.run()
            let mountData = mountPipe.fileHandleForReading.readDataToEndOfFile()
            let mountOutput = String(data: mountData, encoding: .utf8) ?? ""
            
            // Find the line for this mount point
            let mountLines = mountOutput.components(separatedBy: "\n")
            for line in mountLines {
                if line.contains(url.path) {
                    // Check for network filesystem identifiers
                    if line.contains("smb") ||
                        line.contains("afp") ||
                        line.contains("nfs") ||
                        line.contains("cifs") ||
                        line.contains("webdav") ||
                        line.contains("macfuse") ||  // Some network mounts use macFUSE
                        line.contains("remote") {
                        return true
                    }
                }
            }
        } catch {
            // Ignore errors here
        }
        
        return false
    }
    
    // Helper to get the BSD name (disk identifier) of a volume
    private func getBSDName(for url: URL) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["info", url.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            
            // Parse diskutil output to find Device Identifier
            if let range = output.range(of: "Device Identifier:") {
                let line = output[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if let endOfLine = line.firstIndex(of: "\n") {
                    let deviceIdentifier = line[..<endOfLine].trimmingCharacters(in: .whitespaces)
                    return String(deviceIdentifier)
                }
            }
        } catch {
            print("⚠️ Failed to get BSD name: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    // This method is now only used for single-partition drives
    func ejectVolume(volume: ExternalVolume, completion: @escaping (Bool, String?) -> Void) {
        // Check if this is a multi-partition drive
        if let bsdName = volume.bsdName {
            // Get the master BSD name
            let masterBSD = bsdName.replacingOccurrences(of: #"(disk\d+)s\d+"#, with: "$1", options: .regularExpression)
            
            // Check if this is a multi-partition drive
            if let drive = driveTracker.physicalDrives[masterBSD], drive.partitions.count > 1 {
                print("⚠️ Attempt to eject individual partition of multi-partition drive. Using ejectPhysicalDrive instead.")
                ejectPhysicalDrive(for: volume, completion: completion)
                return
            }
        }
        
        // This is a single partition drive, proceed with normal ejection
        DispatchQueue.global().async {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volume.path)
                DispatchQueue.main.async {
                    completion(true, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
    
    // Notify when all partitions of a physical drive have been scanned
    // In VolumeMonitor.swift
    
    func finalizeDriveRemoval(for driveKey: String) {
        let partitions = PhysicalDriveTracker.shared.getPartitions(for: driveKey)

        for volume in partitions {
            let volumeKey = "\(volume.volumeUUID)-\(volume.name)"
            processingMultiPartitionVolumes.remove(volumeKey)
            activelyScanning.remove(volumeKey)
            connectedVolumes.removeAll { $0.volumeUUID == volume.volumeUUID }
            volumeStates.removeValue(forKey: volumeKey)
        }

        ejectingDrives.remove(driveKey)
        completedPhysicalDrives.remove(driveKey)  // Make sure to clear this
        PhysicalDriveTracker.shared.clearDrive(key: driveKey)

        refreshConnectedVolumes()
    }

    func notifyDriveFullyScanned(for volumeUUID: String) {
        guard let physicalDriveKey = PhysicalDriveTracker.shared.getPhysicalDriveKey(for: volumeUUID) else {
            print("⚠️ Cannot find physical drive for volume UUID: \(volumeUUID)")
            return
        }

        let partitions = PhysicalDriveTracker.shared.getPartitions(for: physicalDriveKey)
        let hasInfected = PhysicalDriveTracker.shared.hasInfectedPartition(for: volumeUUID)

        print("📢 Notifying that physical drive \(physicalDriveKey) with \(partitions.count) partitions is fully scanned")
        
        // Double-check that all partitions are marked as completed
        for partition in partitions {
            let key = "\(partition.volumeUUID)-\(partition.name)"
            let state = volumeStates[key]
            print("   - Partition \(partition.name) status: \(state?.scanStatus.rawValue ?? "unknown")")
        }

        // Generate a unique notification identifier to prevent duplicate handling
        let notificationID = UUID().uuidString
        
        // Post notification about physical drive completion with a unique identifier
        NotificationCenter.default.post(
            name: .physicalDriveFullyScanned,
            object: nil,
            userInfo: [
                "driveKey": physicalDriveKey,
                "partitions": partitions,
                "hasInfectedPartition": hasInfected,
                "notificationID": notificationID  // Add a unique ID to identify this notification
            ]
        )
    }
}

