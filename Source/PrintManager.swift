import Foundation
import AppKit

@MainActor
class PrintManager {
    enum PrintError: Error, LocalizedError {
        case noPrinterAvailable
        case printOperationFailed
        case invalidPrintInfo
        case volumeNotFound // Add this

        var errorDescription: String? {
            switch self {
            case .noPrinterAvailable:
                return "No printer is available. Please connect a printer and try again."
            case .printOperationFailed:
                return "Print operation failed. Please check if the printer is connected and has paper."
            case .invalidPrintInfo:
                return "Could not configure printer settings."
            case .volumeNotFound:
                return "Volume no longer accessible for printing."
            }
        }
    }

    // 🛡️ Global print guard to handle Monterey re-triggers
    // Using a map with timestamps to allow reprinting after a cooldown period
    private var printedVolumeTimestamps: [String: Date] = [:]
    
    // Cooldown period (5 minutes) - adjust as needed
    private let printCooldownPeriod: TimeInterval = 2
    
    // Print queue to ensure serialized printing operations
    private let printQueue = DispatchQueue(label: "com.app.printqueue", qos: .userInitiated)
    private var isPrinting = false

    func isPrinterAvailable() -> Bool {
        let printerNames = NSPrinter.printerNames
        if !printerNames.isEmpty {
            print("🖨️ Available printers: \(printerNames.joined(separator: ", "))")
            return true
        }
        print("⚠️ No printer available")
        return false
    }

    func printScanResults(for state: VolumeScanState) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            printQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: PrintError.printOperationFailed)
                    return
                }

                Task {
                    // Async-safe wait for ongoing prints to finish
                    let waitStep: UInt64 = state.isInfected ? 50_000_000 : 100_000_000 // nanoseconds
                    let maxWaitTime: UInt64 = state.isInfected ? 500_000_000 : 2_000_000_000
                    var waited: UInt64 = 0

                    while await MainActor.run(body: { self.isPrinting }) && waited < maxWaitTime {
                        try? await Task.sleep(nanoseconds: waitStep)
                        waited += waitStep
                    }

                    if await MainActor.run(body: { self.isPrinting }) {
                        if state.isInfected {
                            print("⚠️ Forcing print for infected volume despite ongoing print job")
                        } else {
                            continuation.resume(throwing: PrintError.printOperationFailed)
                            return
                        }
                    }

                    // Check if volume is still available
                    guard FileManager.default.fileExists(atPath: state.volume.path.path) else {
                        print("⚠️ Cannot print - volume no longer exists: \(state.volume.name)")
                        await MainActor.run {
                            if !state.isInfected {
                                state.hasPrinted = true
                            }
                        }
                        continuation.resume(throwing: PrintError.volumeNotFound)
                        return
                    }

                    await MainActor.run {
                        self.isPrinting = true
                    }

                    // Try printing with retries
                    var retryCount = 0
                    let maxRetries = state.isInfected ? 5 : 3
                    var lastError: Error? = nil

                    while retryCount < maxRetries {
                        do {
                            try await self._printScanResults(for: state)
                            await MainActor.run {
                                self.isPrinting = false
                                print("🖨️ Marking \(state.volume.name) as printed at \(Date())")
                            }
                            continuation.resume()
                            return
                        } catch PrintError.noPrinterAvailable {
                            retryCount += 1
                            lastError = PrintError.noPrinterAvailable
                            print("⚠️ Printer not available, retry \(retryCount)/\(maxRetries)")

                            let delay: UInt64 = state.isInfected ? 300_000_000 : 1_000_000_000
                            try? await Task.sleep(nanoseconds: delay)


                            if !FileManager.default.fileExists(atPath: state.volume.path.path) {
                                print("⚠️ Volume \(state.volume.name) no longer accessible after retry delay")
                                break
                            }
                        } catch {
                            await MainActor.run {
                                self.isPrinting = false
                            }
                            continuation.resume(throwing: error)
                            return
                        }
                    }

                    // Retry limit reached
                    await MainActor.run {
                        self.isPrinting = false
                        if !state.isInfected {
                            state.hasPrinted = true
                            print("🖨️ Marking \(state.volume.name) as printed (fallback after failure)")
                        }
                    }

                    continuation.resume(throwing: lastError ?? PrintError.printOperationFailed)
                }
            }
        }
    }

    // Add this error type to your PrintError enum
    
    
    // Internal implementation of print functionality
    // Add this updated method to your PrintManager.swift file

    private func _printScanResults(for state: VolumeScanState) async throws {
        let volumeKey = "\(state.volume.volumeUUID)-\(state.volume.name)"
        let now = Date()
        
        // CRITICAL: Check volume accessibility first thing and fail fast
        guard FileManager.default.fileExists(atPath: state.volume.path.path) else {
            print("⚠️ Volume no longer accessible for printing: \(state.volume.name)")
            throw PrintError.volumeNotFound
        }
        
        // PRIORITY PRINTING: For infected volumes, print with no cooldown check
        if state.isInfected {
            print("⚠️ Infected volume - bypassing all cooldown checks")
            // Skip all cooldown/hasPrinted checks for infected volumes
        } else {
            // Only do cooldown checks for clean volumes
            let cooldownPeriod = state.isPartOfMultiPartitionDrive ? 0.1 : self.printCooldownPeriod
            
            if let lastPrintTime = printedVolumeTimestamps[volumeKey],
               now.timeIntervalSince(lastPrintTime) < cooldownPeriod {
                print("⚠️ Skipping print: already printed for volume \(volumeKey) within cooldown period")
                return
            }
            
            // For clean volumes, check hasPrinted
            if state.hasPrinted {
                print("⚠️ Skipping print: clean volume already marked as printed in state")
                return
            }
        }

        // Check printer availability - retry a few times for infected volumes
        if !isPrinterAvailable() {
            // Special handling for infected volumes - try a bit harder
            if state.isInfected {
                for attempt in 1...3 {
                    print("🔄 Retry \(attempt)/3 getting printer for infected volume")
                    try await Task.sleep(nanoseconds: 200_000_000) // 200ms delay
                    if isPrinterAvailable() {
                        print("✅ Printer found on retry \(attempt)")
                        break
                    }
                    if attempt == 3 {
                        throw PrintError.noPrinterAvailable
                    }
                }
            } else {
                throw PrintError.noPrinterAvailable
            }
        }

        // The rest of the printing code remains the same
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let currentDate = Date()
        let dateString = dateFormatter.string(from: currentDate)

        // Fetch volume format - handle errors gracefully for infected volumes
        let volumeFormat: String
        do {
            volumeFormat = try getVolumeFormat(for: state.volume.path) ?? "Unknown"
        } catch {
            print("⚠️ Error getting volume format: \(error.localizedDescription)")
            volumeFormat = "Unknown (error reading)"
        }

        // Add info about multi-partition drives to the receipt
        var receipt = """
        = DRIVE SCAN REPORT =
        Drive Name: \(state.volume.name)
        Status: \(state.isInfected ? "⚠️ INFECTED" : "✅ CLEAN")
        Valid Until: \(formattedValidity(endDate: state.scanEndTime))
        Date: \(dateString)
        Volume Format: \(volumeFormat)
        """
        
        // Add multi-partition information if applicable
        if state.isPartOfMultiPartitionDrive {
            receipt += "\nPartition: \(state.volume.name) (Part of a \(state.siblingPartitionCount + 1)-partition drive)"
        }
        
        // Add more info for partial scans
        if let error = state.error, state.scanProgress < 1.0 {
            receipt += "\nNote: \(error)"
        }
        
        receipt += """

        Start: \(dateFormatter.string(from: state.scanStartTime ?? currentDate))
        End:   \(dateFormatter.string(from: state.scanEndTime ?? currentDate))
        Time:  \(formatDuration(from: state.scanStartTime, to: state.scanEndTime))
        Files: \(state.scannedFiles)
        Skipped Files: \(state.skippedFiles)
        """

        if state.isInfected {
            receipt += "\n\nInfected Files:\n"
            for file in state.infectedFiles.prefix(5) {
                receipt += "- \(shorten(file))\n"
            }
            if state.infectedFiles.count > 5 {
                receipt += "... \(state.infectedFiles.count - 5) more\n"
            }
        }

        receipt += "\n=== SCAN COMPLETE ==="
        
        if state.isInfected {
                print("🔴 Printing INFECTED volume \(state.volume.name) with \(state.infectedFiles.count) infected files")
            }
        
        let viewWidth: CGFloat = 200
        let viewHeight: CGFloat = 500

        let textView = NSTextView(frame: NSRect(x: 0, y: -5, width: viewWidth, height: viewHeight))
        textView.string = receipt
        textView.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.widthTracksTextView = true

        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: viewWidth, height: viewHeight)
        printInfo.leftMargin = 5
        printInfo.rightMargin = 5
        printInfo.topMargin = 0
        printInfo.bottomMargin = 5
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false

        let printerNames = NSPrinter.printerNames
            print("🖨️ Available printers: \(printerNames.joined(separator: ", "))")

            if let thermalPrinterName = printerNames.first(where: {
                $0.contains("Epson") || $0.contains("TM-T") || $0.contains("Thermal") || $0.contains("Receipt")
            }), let printer = NSPrinter(name: thermalPrinterName) {
                printInfo.printer = printer
                print("🖨️ Using thermal printer: \(thermalPrinterName)")

            } else if let firstPrinterName = printerNames.first,
                      let fallbackPrinter = NSPrinter(name: firstPrinterName) {
                printInfo.printer = fallbackPrinter
                print("🖨️ Using fallback printer: \(firstPrinterName)")
            }

            let operation = NSPrintOperation(view: textView, printInfo: printInfo)
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false

            print("🖨️ Printing scan report for \(state.volume.name)")
            let success = operation.run()

            if !success {
                print("❌ Print operation failed")
                throw PrintError.printOperationFailed
            }

            // Only mark as printed after successful printing
            print("✅ Print completed successfully for \(state.volume.name)")
            printedVolumeTimestamps[volumeKey] = Date()
        }
    
    // Method to clean up old timestamps (optional, call periodically)
    func cleanupOldPrintRecords() {
        let now = Date()
        let keysToRemove = printedVolumeTimestamps.keys.filter { key in
            guard let timestamp = printedVolumeTimestamps[key] else { return false }
            return now.timeIntervalSince(timestamp) > printCooldownPeriod
        }
        
        for key in keysToRemove {
            printedVolumeTimestamps.removeValue(forKey: key)
        }
    }

    func tryPrintScanResults(for state: VolumeScanState) async -> Bool {
        do {
            try await printScanResults(for: state)
            return true
        } catch {
            print("⚠️ Print failed: \(error.localizedDescription)")
            return false
        }
    }

    private func getVolumeFormat(for url: URL) throws -> String? {
        let values = try url.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey])
        return values.volumeLocalizedFormatDescription
    }

    private func formatDuration(from start: Date?, to end: Date?) -> String {
        guard let s = start, let e = end else { return "Unknown" }
        let seconds = Int(e.timeIntervalSince(s))
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
    }

    private func formattedValidity(endDate: Date?) -> String {
        guard let end = endDate else { return "Unknown" }
        let validityDate = end.addingTimeInterval(30 * 60)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: validityDate)
    }

    private func shorten(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.count > 30 ? String(name.prefix(30)) + "…" : name
    }
}
