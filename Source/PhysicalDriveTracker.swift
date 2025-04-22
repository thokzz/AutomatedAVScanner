import Foundation

// Class to track physical drives and their partitions
class PhysicalDriveTracker {
    static let shared = PhysicalDriveTracker()
    
    internal var physicalDrives: [String: PhysicalDrive] = [:]
    
    struct PhysicalDrive {
        let bsdName: String
        var partitions: [ExternalVolume] = []
        var scanningPartitions: Int = 0
        var completedPartitions: Int = 0
        var hasInfectedPartition: Bool = false
        
        var isFullyScanned: Bool {
            // MODIFIED: Make sure no scanning is in progress and all partitions are complete
            completedPartitions == partitions.count && !partitions.isEmpty && scanningPartitions == 0
        }
    }
    
    func resetDriveState(key: String) {
        guard var drive = physicalDrives[key] else {
            print("⚠️ Cannot reset drive state for \(key): drive not found")
            return
        }
        
        print("🔄 Resetting state for drive \(key) with \(drive.partitions.count) partitions")
        
        drive.scanningPartitions = 0
        drive.completedPartitions = 0
        drive.hasInfectedPartition = false
        
        physicalDrives[key] = drive
    }
    
    func getDriveKey(for volume: ExternalVolume) -> String? {
        // FIXED: Properly extract the base drive name (e.g., disk2 from disk2s1)
        guard let bsdName = volume.bsdName else { return nil }
        
        // Use regex to extract the base drive name (disk2 from disk2s1)
        if let match = bsdName.range(of: #"^disk\d+"#, options: .regularExpression) {
            return String(bsdName[match])
        }
        
        return nil
    }

    
    @discardableResult
    func addVolume(_ volume: ExternalVolume, bsdName: String) -> String {
        // Extract the base drive name for proper grouping
        let baseDriveKey: String
        if let match = bsdName.range(of: #"^disk\d+"#, options: .regularExpression) {
            baseDriveKey = String(bsdName[match])
        } else {
            baseDriveKey = bsdName
        }
        
        if physicalDrives[baseDriveKey] == nil {
            physicalDrives[baseDriveKey] = PhysicalDrive(bsdName: baseDriveKey)
        }
        
        if !physicalDrives[baseDriveKey]!.partitions.contains(where: { $0.volumeUUID == volume.volumeUUID }) {
            physicalDrives[baseDriveKey]!.partitions.append(volume)
            print("🔢 Added volume \(volume.name) to physical drive \(baseDriveKey) (total partitions: \(physicalDrives[baseDriveKey]!.partitions.count))")
        }
        
        return baseDriveKey
    }
    
    func getPhysicalDriveKey(for volumeUUID: String) -> String? {
        for (key, drive) in physicalDrives {
            if drive.partitions.contains(where: { $0.volumeUUID == volumeUUID }) {
                return key
            }
        }
        return nil
    }
    
    func getPartitions(for physicalDriveKey: String) -> [ExternalVolume] {
        physicalDrives[physicalDriveKey]?.partitions ?? []
    }
    
    func markScanStarted(for volumeUUID: String) {
        guard let driveKey = getPhysicalDriveKey(for: volumeUUID) else { return }
        physicalDrives[driveKey]?.scanningPartitions += 1
        print("🚦 Scan started for partition \(volumeUUID). Active scans: \(physicalDrives[driveKey]?.scanningPartitions ?? 0)")
    }
    
    func markScanCompleted(for volumeUUID: String, infected: Bool) {
        guard let driveKey = getPhysicalDriveKey(for: volumeUUID),
              var drive = physicalDrives[driveKey] else { return }

        drive.scanningPartitions = max(drive.scanningPartitions - 1, 0)
        drive.completedPartitions += 1

        if infected {
            drive.hasInfectedPartition = true
        }

        physicalDrives[driveKey] = drive  // update dictionary explicitly
        
        print("🏁 Scan completed for partition \(volumeUUID). Completed partitions: \(drive.completedPartitions)/\(drive.partitions.count), Active scans: \(drive.scanningPartitions)")

        checkAndNotifyIfDriveComplete(driveKey: driveKey, drive: drive)
    }

    private func checkAndNotifyIfDriveComplete(driveKey: String, drive: PhysicalDrive) {
        // If drive is fully scanned, notify
        if drive.isFullyScanned && drive.partitions.count > 0 {
            // Wait a longer moment to ensure all operations are completed
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                // Double-check that conditions are still met
                if let currentDrive = self.physicalDrives[driveKey],
                   currentDrive.isFullyScanned && currentDrive.partitions.count > 0 {
                    print("🎉 Physical drive \(driveKey) is fully scanned with \(drive.partitions.count) partitions")
                    
                    // Log the status of all partitions for verification
                    for partition in drive.partitions {
                        print("   - Partition \(partition.name) [\(partition.volumeUUID)] is completed")
                    }
                    
                    NotificationCenter.default.post(
                        name: .physicalDriveFullyScanned,
                        object: nil,
                        userInfo: [
                            "driveKey": driveKey,
                            "partitions": drive.partitions,
                            "hasInfectedPartition": drive.hasInfectedPartition
                        ]
                    )
                } else {
                    print("⚠️ Drive state changed during delay - cancelling notification for \(driveKey)")
                }
            }
        } else {
            // If not fully scanned yet, explain why
            let remaining = drive.partitions.count - drive.completedPartitions
            print("⏳ Physical drive \(driveKey) is not fully scanned yet. Remaining partitions: \(remaining), Active scans: \(drive.scanningPartitions)")
        }
    }
    
    func markScanCompletedWithError(for volumeUUID: String) {
        guard let driveKey = getPhysicalDriveKey(for: volumeUUID),
              var drive = physicalDrives[driveKey] else { return }

        drive.scanningPartitions = max(drive.scanningPartitions - 1, 0)
        drive.completedPartitions += 1
        
        physicalDrives[driveKey] = drive  // update dictionary explicitly
        
        print("🏁 Scan completed (with error) for partition \(volumeUUID). Completed partitions: \(drive.completedPartitions)/\(drive.partitions.count), Active scans: \(drive.scanningPartitions)")

        checkAndNotifyIfDriveComplete(driveKey: driveKey, drive: drive)
    }
    
    func isPhysicalDriveFullyScanned(for volumeUUID: String) -> Bool {
        guard let driveKey = getPhysicalDriveKey(for: volumeUUID),
              let drive = physicalDrives[driveKey] else { return false }
        
        // ADDED: More detailed logging
        if !drive.isFullyScanned {
            print("📊 Drive status - Total: \(drive.partitions.count), Completed: \(drive.completedPartitions), Active: \(drive.scanningPartitions)")
        }
        
        return drive.isFullyScanned
    }
    
    // Add to PhysicalDriveTracker.swift
    func forceRescanDrive(for volume: ExternalVolume) {
        guard let driveKey = getDriveKey(for: volume) else {
            print("⚠️ Cannot force rescan: No drive key found for volume \(volume.name)")
            return
        }
        
        print("🔨 Force clearing \(driveKey) from tracking for rescan")
        
        // Reset the drive's internal state
        resetDriveState(key: driveKey)
        
        // Post a notification that AppCoordinator will observe
        NotificationCenter.default.post(
            name: Notification.Name("ForceRescanRequested"),
            object: nil,
            userInfo: ["driveKey": driveKey, "volumeUUID": volume.volumeUUID]
        )
    }
    
    func hasInfectedPartition(for volumeUUID: String) -> Bool {
        guard let driveKey = getPhysicalDriveKey(for: volumeUUID),
              let drive = physicalDrives[driveKey] else { return false }
        return drive.hasInfectedPartition
    }
    
    func clearDrive(key: String) {
        // FIXED: Add delay and verification before clearing
        let partitionCount = physicalDrives[key]?.partitions.count ?? 0
        print("🗑️ Preparing to clear drive tracking for \(key) with \(partitionCount) partitions")
        
        // Only proceed if we have confirmation that everything is properly handled
        if partitionCount > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("🗑️ Cleared drive tracking for \(key)")
                self.physicalDrives.removeValue(forKey: key)
            }
        } else {
            print("🗑️ Immediately cleared drive tracking for \(key) (no partitions)")
            physicalDrives.removeValue(forKey: key)
        }
    }
    
    func getSiblingVolumes(for volume: ExternalVolume) -> [ExternalVolume] {
        guard let driveKey = getPhysicalDriveKey(for: volume.volumeUUID),
              let drive = physicalDrives[driveKey] else { return [] }
        return drive.partitions.filter { $0.volumeUUID != volume.volumeUUID }
    }
    
    func reset() {
        physicalDrives.removeAll()
        print("🔄 Reset PhysicalDriveTracker state")
    }
}
