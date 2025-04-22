//
//  AuditLogger.swift
//  DriveScanner
//
//  Created by Jan Hernandez on 4/16/25.
//

import Foundation

class AuditLogger {
    static let shared = AuditLogger()
    private let logFileURL: URL
    
    private init() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/DriveScanner", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logFileURL = logsDir.appendingPathComponent("audit-log.txt")
    }
    
    func log(_ message: String, category: String = "INFO") {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fullMessage = "[\(timestamp)] [\(category)] \(message)\n"
        if let data = fullMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                do {
                    let fileHandle = try FileHandle(forWritingTo: logFileURL)
                    defer {
                        try? fileHandle.close()
                    }
                    try fileHandle.seekToEnd()
                    try fileHandle.write(contentsOf: data)
                } catch {
                    print("Error writing to log file: \(error.localizedDescription)")
                    // If we can't append, try to overwrite
                    try? data.write(to: logFileURL, options: .atomic)
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
        print(fullMessage)
    }
    
    func logDrive(action: String, driveKey: String, partitionCount: Int) {
        log("DRIVE \(action): \(driveKey) with \(partitionCount) partitions", category: "DRIVE")
    }
    
    func logPartition(action: String, volume: ExternalVolume, additionalInfo: String = "") {
        log("PARTITION \(action): \(volume.name) [\(volume.volumeUUID)] \(additionalInfo)", category: "PARTITION")
    }
    
    func logScan(action: String, volume: ExternalVolume, progress: Double, fileCount: Int, scannedFiles: Int) {
        log("SCAN \(action): \(volume.name) Progress: \(Int(progress * 100))% (\(scannedFiles)/\(fileCount) files)", category: "SCAN")
    }
    
    func logPrint(action: String, volume: String, success: Bool, errorMessage: String? = nil) {
        if success {
            log("PRINT \(action): \(volume) ✓", category: "PRINT")
        } else {
            log("PRINT \(action): \(volume) ✗ \(errorMessage ?? "unknown error")", category: "PRINT")
        }
    }
    
    func logEject(action: String, driveKey: String, success: Bool, errorMessage: String? = nil) {
        if success {
            log("EJECT \(action): \(driveKey) ✓", category: "EJECT")
        } else {
            log("EJECT \(action): \(driveKey) ✗ \(errorMessage ?? "unknown error")", category: "EJECT")
        }
    }
    
    func logInfo(message: String) {
        log(message, category: "INFO")
    }
    
    func logWarning(message: String) {
        log(message, category: "WARN")
    }
    
    func logError(message: String) {
        log(message, category: "ERROR")
    }
    
    func clearLog() {
        do {
            try "".data(using: .utf8)?.write(to: logFileURL)
        } catch {
            print("Error clearing log file: \(error.localizedDescription)")
        }
    }
}
