import Foundation
import AVFoundation

@MainActor
final class ScanHandler {
    static let shared = ScanHandler()
    
    private let fileCounter = FileCounter()
    private let scanEngine = ScanEngine()
    private let printManager = PrintManager()
    private let transactionManager = TransactionManager()
    private let logger = AuditLogger.shared
    
    func startScanning(
        volume: ExternalVolume,
        state: VolumeScanState,
        autoPrintEnabled: Bool,
        volumeMonitor: VolumeMonitor,
        notify: @escaping (String, String) async -> Void,
        playEjectCue: @escaping (String) -> Void
    ) -> Task<Void, Never> {
        // Reset state
        state.scanStatus = .queued
        if let key = PhysicalDriveTracker.shared.getDriveKey(for: volume) {
            PhysicalDriveTracker.shared.resetDriveState(key: key)
        }
        volumeMonitor.markVolumeAsScanning(volume)
        
        // Drive‑association logic (unchanged)…
        let driveKey: String?
        if volume.bsdName != nil {
            driveKey = PhysicalDriveTracker.shared.getDriveKey(for: volume)
            logger.logDrive(action: "START_SCAN", driveKey: driveKey ?? "unknown", partitionCount: 1)
            PhysicalDriveTracker.shared.markScanStarted(for: volume.volumeUUID)
            state.updateSiblingInfo()
        } else {
            driveKey = nil
            logger.logInfo(message: "\(volume.name) part of multi-partition drive, waiting")
        }
        logger.logPartition(action: "START_SCAN", volume: volume)
        
        return Task { [self] in
            do {
                // Initialize
                await MainActor.run {
                    state.scanStatus       = .counting
                    state.scanStartTime    = Date()
                    state.scanProgress     = 0
                    state.scannedFiles     = 0
                    state.infectedFiles    = []
                    state.error            = nil
                    state.hasPrinted       = false
                }
                
                // 1) Rough count for estimating UI ranges (unchanged)…
                let fileCount = try await fileCounter.countFiles(in: volume) { count in
                    Task { @MainActor in
                        state.fileCount       = count
                        state.minFileCount    = Int(Double(count) * 0.9)
                        state.maxFileCount    = Int(Double(count) * 1.1)
                        state.fileCountRange  = "\(state.minFileCount)-\(state.maxFileCount)"
                        logger.logInfo(message: "Counted \(count) files")
                    }
                }
                await MainActor.run { state.scanStatus = .scanning }
                
                // 2) Build extension‑skip list
                let skipExt = UserDefaults.standard.bool(forKey: "skipExtensionsEnabled")
                let extsToSkip = (UserDefaults.standard.string(forKey: "extensionsToSkip") ?? "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
                
                // ─── NEW: get exact filtered list & skip counts ───
                // This mirrors the “🔍 Found X files to scan” log
                let (_, _, filesToScan) = try await scanEngine.getFilesToScan(
                    in: volume.path.path,
                    skipExtensions: skipExt,
                    extensionsToSkip: extsToSkip
                )
                
                let rawCount = fileCount
                let actualCount = filesToScan.count
                let skippedFilesCount = rawCount - actualCount
                
                await MainActor.run {
                    state.skippedFiles   = skippedFilesCount   // number of files filtered out
                    state.fileCount      = actualCount         // e.g. “40”
                    state.minFileCount   = actualCount
                    state.maxFileCount   = actualCount
                    state.fileCountRange = ""                  // show just “40”
                }
             
                let (_, infected) = try await scanEngine.scanVolume(
                    volume: volume,
                    totalFiles: actualCount
                ) { progress, infectedFiles, filename in
                    Task { @MainActor in
                        state.scannedFiles   = progress
                        state.infectedFiles  = infectedFiles
                        state.lastScannedFile = filename
                        
                        let denom = max(state.minFileCount, 1)
                        state.scanProgress = Double(progress) / Double(denom)
                        if progress >= denom { state.scanProgress = 1.0 }
                        
                        if state.scanProgress >= 1.0 && state.scanStatus == .scanning {
                            state.scanStatus = state.isPartOfMultiPartitionDrive
                                ? .waiting
                                : (infectedFiles.isEmpty ? .clean : .infected)
                        }
                        
                        if progress % 100 == 0 || state.scanProgress >= 1.0 {
                            logger.logScan(
                                action:    "PROGRESS",
                                volume:    volume,
                                progress:  state.scanProgress,
                                fileCount: actualCount,
                                scannedFiles: progress
                            )
                        }
                    }
                }
                
                // 4) Finalize status & logging (unchanged)…
                await MainActor.run {
                    state.scanEndTime = Date()
                    if !state.isPartOfMultiPartitionDrive {
                        state.scanStatus = infected.isEmpty ? .clean : .infected
                    }
                    logger.logInfo(message: infected.isEmpty
                                   ? "Clean"
                                   : "Infected: \(infected.count)")
                }
                
                let txId = transactionManager.addAndSaveTransaction(from: state)
                logger.logInfo(message: "Recorded TX \(txId)")
                
                // 5) Print & multi‑partition eject (unchanged)…
                PhysicalDriveTracker.shared.markScanCompleted(for: volume.volumeUUID,
                                                             infected: !infected.isEmpty)
                volumeMonitor.markVolumeAsDoneScanning(volume)
                if let key = driveKey,
                   PhysicalDriveTracker.shared.isPhysicalDriveFullyScanned(for: volume.volumeUUID) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    volumeMonitor.notifyDriveFullyScanned(for: volume.volumeUUID)
                }
                
            } catch {
                // Error handling (unchanged)…
                await MainActor.run {
                    state.scanStatus = state.scannedFiles > 0
                        ? (state.isInfected ? .infected : .clean)
                        : .error
                    state.error = error.localizedDescription
                }
                PhysicalDriveTracker.shared.markScanCompletedWithError(for: volume.volumeUUID)
                volumeMonitor.markVolumeAsDoneScanning(volume)
                await notify("Scan Error", error.localizedDescription)
            }
        }
    }
}
