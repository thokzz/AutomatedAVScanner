// Replace the entire PrintHandler.swift file with this improved version:

import Foundation

@MainActor
class PrintHandler {
    static let shared = PrintHandler()
    private let logger = AuditLogger.shared
    
    // Keep track of volumes currently being printed to prevent parallel printing
    private var currentlyPrintingVolumes = Set<String>()

    private let logFileURL: URL = {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/DriveScanner", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("print-log.txt")
    }()

    private func logToFile(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fullMessage = "[\(timestamp)] \(message)\n"
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
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }

    func printPartitionsSequentially(
        partitions: [VolumeScanState],
        printManager: PrintManager,
        transactionManager: TransactionManager,
        waitAfterPrint: UInt64,
        notify: @escaping (String, String) async -> Void
    ) async -> Bool {
        var printedCount = 0
        let totalCount = partitions.count
        
        // Track volumes we're processing in this specific print session
        var processedInThisSession = Set<String>()

        // Filter out already printed ones or ones that are currently printing
        let filteredPartitions = partitions.filter {
            let volumeKey = "\($0.volume.volumeUUID)-\($0.volume.name)"
            return !$0.hasPrinted && !currentlyPrintingVolumes.contains(volumeKey)
        }

        if filteredPartitions.count < partitions.count {
            print("⚠️ \(partitions.count - filteredPartitions.count) partitions already printed or being printed - skipping")
        }

        if filteredPartitions.isEmpty {
            print("✅ All partitions already printed or being printed - skipping print operation")
            return true
        }

        // Prioritize infected partitions first
        let sortedPartitions = filteredPartitions.sorted {
            if $0.isInfected && !$1.isInfected { return true }
            if !$0.isInfected && $1.isInfected { return false }
            return $0.volume.name < $1.volume.name
        }

        logger.logInfo(message: "🖨️ Printing \(sortedPartitions.count)/\(partitions.count) partitions (others already printed)")

        for (index, state) in sortedPartitions.enumerated() {
            let volumeKey = "\(state.volume.volumeUUID)-\(state.volume.name)"
            
            // Skip if we've already processed this volume in this session
            if processedInThisSession.contains(volumeKey) {
                print("⚠️ Already processed \(state.volume.name) in this print session - skipping duplicate")
                continue
            }
            
            // Skip if this volume is currently being printed by another call
            if currentlyPrintingVolumes.contains(volumeKey) {
                print("⚠️ Volume \(state.volume.name) is already being printed by another process - skipping")
                continue
            }
            
            // Mark that we're about to print this volume
            processedInThisSession.insert(volumeKey)
            currentlyPrintingVolumes.insert(volumeKey)
            
            logToFile("📋 Print queue item #\(index+1): \(state.volume.name) [infected: \(state.isInfected)]")

            guard FileManager.default.fileExists(atPath: state.volume.path.path) else {
                let msg = "⚠️ Skipping print: \(state.volume.name) is no longer accessible"
                logger.logWarning(message: msg)
                logToFile(msg)
                currentlyPrintingVolumes.remove(volumeKey)
                continue
            }

            if state.hasPrinted {
                print("⚠️ Skipping final print: \(state.volume.name) already printed")
                currentlyPrintingVolumes.remove(volumeKey)
                continue
            }

            let maxAttempts = state.isInfected ? 3 : 2
            var success = false

            for attempt in 1...maxAttempts {
                if attempt > 1 {
                    let retryMsg = "🔄 Print attempt #\(attempt) for \(state.volume.name)"
                    logger.logInfo(message: retryMsg)
                    logToFile(retryMsg)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }

                do {
                    let bookmark = state.volume.path.startAccessingSecurityScopedResource()
                    try await printManager.printScanResults(for: state)
                    if bookmark { state.volume.path.stopAccessingSecurityScopedResource() }

                    state.hasPrinted = true
                    transactionManager.updateTransactionPrintTimeByVolumeUUID(volumeUUID: state.volume.volumeUUID)

                    printedCount += 1
                    success = true
                    let msg = "✅ Successfully printed results for \(state.volume.name) on attempt #\(attempt)"
                    logger.logInfo(message: msg)
                    logToFile(msg)
                    break
                } catch {
                    let msg = "❌ Print attempt #\(attempt) failed for \(state.volume.name): \(error.localizedDescription)"
                    logger.logError(message: msg)
                    logToFile(msg)

                    if attempt == maxAttempts {
                        if !state.isInfected {
                            state.hasPrinted = true
                            let skipMsg = "⚠️ Marking clean volume \(state.volume.name) as printed despite failure"
                            logger.logWarning(message: skipMsg)
                            logToFile(skipMsg)
                        } else {
                            await notify("Print Failed", "\(state.volume.name): \(error.localizedDescription)")
                        }
                    }
                }
            }
            
            // Remove from currently printing volumes
            currentlyPrintingVolumes.remove(volumeKey)

            let delayTime = state.isInfected ? 1_000_000_000 : 500_000_000
            try? await Task.sleep(nanoseconds: UInt64(delayTime))
        }

        // Make sure to clear any remaining volumes from the printing set
        for state in sortedPartitions {
            let volumeKey = "\(state.volume.volumeUUID)-\(state.volume.name)"
            currentlyPrintingVolumes.remove(volumeKey)
        }

        let successRatio = Double(printedCount) / Double(max(totalCount, 1))
        let success = printedCount > 0 && successRatio >= 0.5

        let summary = "📦 Print completed: \(printedCount)/\(totalCount) partitions (success: \(success ? "YES" : "NO"))"
        logger.logInfo(message: summary)
        logToFile(summary)
        
        // Force refresh of transaction manager to update UI
        transactionManager.refreshTransactions()
        
        try? await Task.sleep(nanoseconds: waitAfterPrint)
        return success
    }
}
