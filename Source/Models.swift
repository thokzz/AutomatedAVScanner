// Models.swift
import Foundation

// MARK: - External Volume Model
struct ExternalVolume: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let path: URL
    let volumeUUID: String
    var bsdName: String?  // Added to track which physical disk this partition belongs to

    static func == (lhs: ExternalVolume, rhs: ExternalVolume) -> Bool {
        lhs.volumeUUID == rhs.volumeUUID && lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(volumeUUID)
        hasher.combine(name)
    }
}

// MARK: - Scan Status Enum
enum ScanStatus: String {
    case queued = "Queued"
    case counting = "Counting Files"
    case scanning = "Scanning"
    case completed = "Complete"
    case error = "Error"
    case infected = "Infected"
    case clean = "No Virus Detected"
    case waiting = "Waiting for Other Partitions"  // Status for multi-partition coordination
}

// MARK: - Volume Scan State
class VolumeScanState: ObservableObject, Identifiable {
    let id = UUID()
    let volume: ExternalVolume

    @Published var scanStatus: ScanStatus = .queued
    @Published var fileCount: Int = 0
    @Published var skippedFiles: Int = 0
    @Published var minFileCount: Int = 0
    @Published var maxFileCount: Int = 0
    @Published var fileCountRange: String = ""
    @Published var scannedFiles: Int = 0
    @Published var infectedFiles: [String] = []
    @Published var scanProgress: Double = 0.0
    @Published var scanStartTime: Date?
    @Published var scanEndTime: Date?
    @Published var error: String?
    @Published var lastScannedFile: String = ""
    @Published var hasPrinted: Bool = false
    @Published var isPartOfMultiPartitionDrive: Bool = false  // Property to track multi-partition drives
    @Published var siblingPartitionCount: Int = 0  // Number of other partitions on the same physical drive
    @Published var siblingPartitions: [String] = []

    // Properties for enhanced progress tracking
    @Published var lastScannedFiles: [String] = []
    @Published var filesPerSecond: Double = 0.0
    @Published var lastProgressUpdateTime: Date = Date()
    @Published var recentFilesScanned: [Int] = []
    @Published var showDetailedScanInfo: Bool = false

    var isPartOfPhysicalDrive: Bool {
        guard volume.bsdName != nil else { return false }
        return PhysicalDriveTracker.shared.getDriveKey(for: volume) != nil
    }
    
    // Update siblings based on PhysicalDriveTracker
    func updateSiblingInfo() {
        let siblings = PhysicalDriveTracker.shared.getSiblingVolumes(for: volume)
        siblingPartitionCount = siblings.count
        siblingPartitions = siblings.map { $0.name }
        isPartOfMultiPartitionDrive = !siblings.isEmpty
    }
    
    var isInfected: Bool {
        !infectedFiles.isEmpty
    }

    var scanDuration: TimeInterval? {
        guard let start = scanStartTime, let end = scanEndTime else { return nil }
        return end.timeIntervalSince(start)
    }

    var estimatedTimeRemaining: TimeInterval? {
        guard filesPerSecond > 0, scanProgress > 0.05, scanProgress < 0.99 else { return nil }
        let remainingFiles = fileCount - scannedFiles
        return Double(remainingFiles) / filesPerSecond
    }

    var scanRate: String {
        if filesPerSecond < 1 {
            return "< 1 file/sec"
        } else {
            return "\(Int(filesPerSecond)) files/sec"
        }
    }

    init(volume: ExternalVolume) {
        self.volume = volume
    }
}
