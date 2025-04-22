// DriveEjectHandler.swift
import Foundation

@MainActor
class DriveEjectHandler {
    static let shared = DriveEjectHandler()

    private var ejectingDrives = Set<String>()
    private var playedEjectCueForDrives = Set<String>()
    private var ejectStartTimes = [String: Date]()
    
    // Add some retry management
    private var ejectRetryCount = [String: Int]()
    private let maxRetries = 3

    func attemptEject(
        driveKey: String,
        partition: ExternalVolume,
        allPartitionsPrinted: Bool,
        volumeMonitor: VolumeMonitor,
        notify: @escaping (String, String) async -> Void
    )
 {
        guard allPartitionsPrinted else {
            print("🛑 Not all partitions printed for \(driveKey), skipping ejection")
            return
        }

        guard !ejectingDrives.contains(driveKey) else {
            print("⚠️ Drive \(driveKey) is already being ejected")
            return
        }
        
        // Track retry count
        let retryCount = ejectRetryCount[driveKey] ?? 0
        if retryCount >= maxRetries {
            print("⚠️ Maximum retry count reached for \(driveKey), giving up")
            ejectRetryCount.removeValue(forKey: driveKey)
            return
        }
        
        ejectRetryCount[driveKey] = retryCount + 1
        ejectingDrives.insert(driveKey)
        ejectStartTimes[driveKey] = Date()

        volumeMonitor.ejectPhysicalDrive(for: partition) { [weak self] success, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                // First play the audio cue on success before any state changes
                if success {
                    // First clear any existing timer to avoid race conditions
                    if !self.playedEjectCueForDrives.contains(driveKey) {
                        self.playedEjectCueForDrives.insert(driveKey)
                        
                        // Play the cue - this is the important part
                        print("🔊 Playing eject cue for \(driveKey)")
                        //playEjectCue(driveKey)
                        
                        // Schedule secondary cue attempt for Monterey (redundancy)
                        if #available(macOS 12.0, *), !ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0)) {
                            // Code here runs only on Monterey
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                                print("🔊 Secondary eject cue attempt for \(driveKey) (Monterey)")
                                //playEjectCue(driveKey) // Try again to overcome Monterey issues
                            }
                        }
                    }
                    
                    // Show notification
                    await notify("Drive Ejected", "Drive \(driveKey) successfully ejected.")
                    
                    // Perform cleanup
                    volumeMonitor.finalizeDriveRemoval(for: driveKey)
                    PhysicalDriveTracker.shared.clearDrive(key: driveKey)
                    
                    // Schedule a delayed cleanup to ensure audio has time to play
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                        await MainActor.run {
                            print("⏲️ Final cleanup for \(driveKey) after successful ejection")
                            self.ejectingDrives.remove(driveKey)
                            self.ejectRetryCount.removeValue(forKey: driveKey)
                        }
                    }
                } else {
                    // On failure, immediately remove from tracking
                    self.ejectingDrives.remove(driveKey)
                    await notify("Eject Failed", error ?? "Unknown error during ejection")
                    
                    // Don't clear tracker on failure to allow retry
                    if self.ejectRetryCount[driveKey] ?? 0 >= self.maxRetries {
                        print("⚠️ Failed to eject \(driveKey) after \(self.maxRetries) attempts")
                        PhysicalDriveTracker.shared.clearDrive(key: driveKey)
                        self.ejectRetryCount.removeValue(forKey: driveKey)
                    }
                }
            }
        }
    }

    func reset(for driveKey: String) {
        ejectingDrives.remove(driveKey)
        playedEjectCueForDrives.remove(driveKey)
        ejectStartTimes.removeValue(forKey: driveKey)
        ejectRetryCount.removeValue(forKey: driveKey)
    }
}
