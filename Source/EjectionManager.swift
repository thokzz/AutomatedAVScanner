import Foundation

@MainActor
class EjectionManager {
    static let shared = EjectionManager()

    private var ejectingDrives = Set<String>()
    private var playedEjectCueForDrives = Set<String>()
    private var lastEjectAttemptTimes = [String: Date]()
    
    // Track retries to avoid infinite loops
    private var ejectRetryCount = [String: Int]()
    private let maxRetries = 3
    
    // Improve mechanism to ensure audio cues are reliable
    private func playSafeToRemoveCue(for driveKey: String) {
        // Ensure we don't rapidly retry cue playback
        let now = Date()
        if let lastAttempt = lastEjectAttemptTimes[driveKey],
           now.timeIntervalSince(lastAttempt) < 2.0 {
            // Too soon since last attempt
            print("⚠️ Skipping audio cue - too soon since last attempt for \(driveKey)")
            return
        }
        
        if !playedEjectCueForDrives.contains(driveKey) {
            playedEjectCueForDrives.insert(driveKey)
            lastEjectAttemptTimes[driveKey] = now
            
            print("🔊 Playing safe to remove audio cue for \(driveKey)")
            
            // First attempt with regular cue
            AudioCueManager.shared.play(.driveSafeToRemove)
            
            // Schedule a secondary verification
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                
                // If we're still ejecting this drive, try to play the sound again
                // This helps on Monterey where the first attempt might fail
                if self.ejectingDrives.contains(driveKey) {
                    print("🔄 Secondary audio cue attempt for \(driveKey)")
                    AudioCueManager.shared.play(.driveSafeToRemove)
                }
            }
        } else {
            print("✅ Already played audio cue for \(driveKey)")
        }
    }

    func attemptEject(
        driveKey: String,
        partition: ExternalVolume,
        allPartitionsPrinted: Bool,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (String?) -> Void
    ) {
        // Don't eject if not all partitions are printed
        guard allPartitionsPrinted else {
            print("🛑 Not all partitions printed yet for \(driveKey), skipping ejection")
            onFailure("Not all partitions have been printed")
            return
        }

        // Prevent parallel ejection of the same drive
        guard !ejectingDrives.contains(driveKey) else {
            print("⚠️ Drive \(driveKey) is already being ejected.")
            return
        }

        // Track retry count
        let retryCount = ejectRetryCount[driveKey] ?? 0
        guard retryCount < maxRetries else {
            print("⚠️ Maximum retry count reached for \(driveKey), giving up")
            ejectRetryCount.removeValue(forKey: driveKey)
            onFailure("Maximum retry count reached")
            return
        }
        
        ejectRetryCount[driveKey] = retryCount + 1
        ejectingDrives.insert(driveKey)

        VolumeMonitor().ejectPhysicalDrive(for: partition) { [weak self] success, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                // First, play audio cue on success - do this before removing from tracking
                if success {
                    // Play audio cue for successful ejection
                    self.playSafeToRemoveCue(for: driveKey)
                    
                    // Schedule cleanup after delay in case audio is still playing
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                        await MainActor.run {
                            print("⏲️ Cleanup for \(driveKey) after successful ejection")
                            self.ejectingDrives.remove(driveKey)
                            self.ejectRetryCount.removeValue(forKey: driveKey)
                        }
                    }
                    
                    onSuccess()
                } else {
                    // If ejection failed, remove from tracking immediately
                    self.ejectingDrives.remove(driveKey)
                    
                    print("❌ Ejection failed for \(driveKey): \(error ?? "Unknown error")")
                    onFailure(error)
                }
            }
        }
    }

    func reset(for driveKey: String) {
        playedEjectCueForDrives.remove(driveKey)
        ejectingDrives.remove(driveKey)
        ejectRetryCount.removeValue(forKey: driveKey)
        lastEjectAttemptTimes.removeValue(forKey: driveKey)
    }
}
