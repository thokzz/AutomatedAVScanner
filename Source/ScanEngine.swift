// ScanEngine.swift
import Foundation

/// Tracks scan progress, skips and infections in a thread‑safe way
actor ScanState {
    private var scannedCount: Int = 0
    private var infectedList: [String] = []
    private var skippedByExtension: Int = 0
    private var skippedLargeFiles: Int = 0
    private var totalFilesToScan: Int = 0
    
    func setTotalFilesToScan(_ count: Int) {
        totalFilesToScan = count
    }
    func getTotalFilesToScan() -> Int { totalFilesToScan }
    
    func incrementScanned() -> Int {
        scannedCount += 1
        return scannedCount
    }
    
    func setSkippedByExtension(_ count: Int) {
        skippedByExtension = count
    }
    func setSkippedLargeFiles(_ count: Int) {
        skippedLargeFiles = count
    }
    
    func getCurrentScanned() -> Int { scannedCount }
    func getSkippedByExtension() -> Int { skippedByExtension }
    func getSkippedLargeFiles() -> Int { skippedLargeFiles }
    
    func addInfectedFile(_ path: String) {
        infectedList.append(path)
    }
    func getInfectedFiles() -> [String] { infectedList }
    
    func getTotalProcessed() -> Int { scannedCount }
    
    func getCompletionPercentage() -> Double {
        guard totalFilesToScan > 0 else { return 0.0 }
        return min(1.0, Double(scannedCount) / Double(totalFilesToScan))
    }
}

class ScanEngine {
    enum ScanError: Error, LocalizedError {
        case clamAVNotAvailable
        case scanCancelled
        case volumeRemoved
        case databaseNotFound
        case scanFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .clamAVNotAvailable: return "ClamAV engine is not available."
            case .scanCancelled: return "Scan was cancelled."
            case .volumeRemoved: return "Volume was removed."
            case .databaseNotFound: return "Virus database not found."
            case .scanFailed(let msg): return "Scan failed: \(msg)"
            }
        }
    }
    
    private func logDebug(_ message: String) {
        print("🔍 [ExtFilter] \(message)")
        extensionFilterLog.append(message)
    }

    // Function to clear debug log
    func clearDebugLog() {
        extensionFilterLog.removeAll()
    }

    // Function to get current debug log
    func getExtensionFilterDebugLog() -> [String] {
        return extensionFilterLog
    }
    
    // Define the file size limit constant (100 MB in bytes)
    private var fileSizeLimit: UInt64 {
        let mb = UserDefaults.standard.integer(forKey: "fileSizeLimitMB")
        return UInt64(max(mb, 1)) * 1024 * 1024
        }
    
    // System directories to skip (macOS + Windows)
    private let SYSTEM_DIRS_TO_SKIP = [
        ".fseventsd",
        ".Spotlight-V100",
        "$RECYCLE.BIN",
        "System Volume Information",
        "lost+found",                  // Linux/Unix system directory
        "$WINDOWS.~BT",                // Windows upgrade directory
        "Windows.old",                 // Old Windows installation
        "hiberfil.sys",                // Windows hibernation file
        "pagefile.sys",                // Windows page file
        "swapfile.sys",                // Windows swap file
        "Boot",                        // Windows boot files
        "Recovery",                    // Recovery partitions
        "EFI",                         // EFI system partition contents
        ".DocumentRevisions-V100",     // macOS document revisions
        ".TemporaryItems",             // macOS temporary items
        ".DS_Store",                   // macOS directory attributes files
        ".SyncArchive"                 // Synology archive folder
    ]
    
    // High risk extensions that should always be scanned
    private let HIGH_RISK_EXTENSIONS = [
        ".exe", ".dll", ".bat", ".com", ".cmd", ".ps1", ".vbs", ".js", ".wsf", ".hta",
        ".jar", ".py", ".php", ".pl", ".rb", ".sh", ".asp", ".aspx", ".jsp", ".jspx",
        ".htm", ".html", ".msi", ".msp", ".reg", ".vbe", ".vb", ".doc", ".docm", ".docx",
        ".xls", ".xlsm", ".xlsx", ".ppt", ".pptm", ".pptx", ".pdf", ".appx", ".msix",
        ".app", ".dmg", ".pkg", ".deb", ".rpm", ".scr", ".sys", ".bin", ".iso", ".run"
    ]
    
    private var isCancelled = false
    
    func cancelScan() {
        print("❌ Cancelling scan")
        isCancelled = true
    }
    
    private func clamScanExecutable() -> URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/clamscan_wrapper.sh")
    }
    
    private func clamAVDatabasePath() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("ClamAVDB")
    }
    

    private var extensionFilterLog: [String] = []


    // Replace the buildFindCommand function with this corrected version
    private func buildFindCommand(
        directory: String,
        skipExtensions: Bool,
        extensionsToSkip: [String],
        highRiskExtensions: [String]
    ) -> ([String], [String]) {
        var findArgs = [directory]
        var grepArgs: [String] = []
        
        // Start debug logging
        logDebug("Building file filter command")
        logDebug("Extension filtering enabled: \(skipExtensions)")
        
        // Basic find options - only files, no directories
        findArgs.append("-type")
        findArgs.append("f")
        
        // Exclude system directories
        logDebug("Excluding \(SYSTEM_DIRS_TO_SKIP.count) system directories")
        for dirName in SYSTEM_DIRS_TO_SKIP {
            findArgs.append("-not")
            findArgs.append("-path")
            findArgs.append("*/\(dirName)/*")
            
            // Also exclude the directory itself at the root level
            findArgs.append("-not")
            findArgs.append("-path")
            findArgs.append("*/\(dirName)")
        }
        
        // Extension filtering
        if skipExtensions && !extensionsToSkip.isEmpty {
            // Log which extensions will be skipped
            logDebug("User requested to skip \(extensionsToSkip.count) extensions:")
            for ext in extensionsToSkip {
                let cleanExt = ext.hasPrefix(".") ? ext : ".\(ext)"
                logDebug("  - Will skip: \(cleanExt)")
            }
            
            // Build grep pattern for excluded extensions (with proper formatting)
            var pattern = ""
            for ext in extensionsToSkip {
                let cleanExt = ext.hasPrefix(".") ? ext : ".\(ext)"
                if pattern.isEmpty {
                    pattern = "\(cleanExt)$"
                } else {
                    pattern += "\\|\(cleanExt)$"
                }
            }
            
            // Always ensure high-risk extensions are scanned
            logDebug("High-risk extensions that will always be scanned: \(highRiskExtensions.count) types")
            for ext in highRiskExtensions.prefix(10) {
                logDebug("  - Will always scan: \(ext)")
            }
            if highRiskExtensions.count > 10 {
                logDebug("  - ... and \(highRiskExtensions.count - 10) more")
            }
            
            // Only apply grep filter if there's a pattern to filter
            if !pattern.isEmpty {
                logDebug("Setting up grep command to exclude specified extensions")
                // Use grep with -v to invert match (exclude the specified extensions)
                grepArgs = ["-v", "-E", pattern]
                logDebug("Grep pattern: \(pattern)")
            } else {
                logDebug("No valid extensions to skip - will scan all files")
            }
        } else if !skipExtensions {
            logDebug("Extension filtering is disabled - scanning ALL files")
        } else {
            logDebug("Extension list is empty - scanning ALL files")
        }
        
        return (findArgs, grepArgs)
    }
    
    // Function to get a pre-filtered list of files to scan (optimized)
    func getFilesToScan(
        in directory: String,
        skipExtensions: Bool,
        extensionsToSkip: [String]
    ) async throws -> (Int, Int, [String]) {
        let task = Process()
        let pipe = Pipe()
        
        // Clear previous logs when starting a new scan
        clearDebugLog()
        
        // Build find command with appropriate arguments
        let (findArgs, grepArgs) = buildFindCommand(
            directory: directory,
            skipExtensions: skipExtensions,
            extensionsToSkip: extensionsToSkip,
            highRiskExtensions: HIGH_RISK_EXTENSIONS
        )
        
        var filesToScan: [String] = []
        var largeFilesSkipped = 0
        
        if grepArgs.isEmpty {
            // Simple find command without grep filtering
            task.executableURL = URL(fileURLWithPath: "/usr/bin/find")
            task.arguments = findArgs
            task.standardOutput = pipe
            logDebug("Using simple find command (no extension filtering)")
        } else {
            // Create a shell command that pipes find through grep
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            
            // Join arguments with spaces and escape special characters
            let findCmd = (["/usr/bin/find"] + findArgs)
                .map { $0.replacingOccurrences(of: " ", with: "\\ ") }
                .joined(separator: " ")
            
            // Create the grep command for exclusions
            let grepCmd = (["/usr/bin/grep"] + grepArgs)
                .map { $0.replacingOccurrences(of: " ", with: "\\ ") }
                .joined(separator: " ")
            
            // Create the full shell command
            let fullCmd = "\(findCmd) | \(grepCmd)"
            task.arguments = ["-c", fullCmd]
            task.standardOutput = pipe
            
            logDebug("Using complex find+grep command to filter by extension")
            logDebug("Final command: \(fullCmd)")
        }
        
        do {
            try task.run()
            
            // Create a buffer to read the output incrementally
            var buffer = Data()
            
            // Read up to 4MB of data at a time, to avoid memory issues
            let chunk = 4 * 1024 * 1024
            var keepReading = true
            
            while keepReading && !isCancelled {
                let data = pipe.fileHandleForReading.readData(ofLength: chunk)
                if data.isEmpty {
                    keepReading = false
                } else {
                    buffer.append(data)
                    
                    // Process the buffer to extract complete lines
                    // This avoids loading all files into memory at once
                    var processedUpTo = 0
                    var newlineIndex: Int = 0
                    while let range = buffer[processedUpTo...].firstRange(of: Data("\n".utf8)) {
                        newlineIndex = range.lowerBound
                        let lineData = buffer[processedUpTo..<newlineIndex]
                        
                        if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                            // Check file size limit before adding to scan list
                            if !fileExceedsLimit(at: line) {
                                filesToScan.append(line)
                            } else {
                                largeFilesSkipped += 1
                                if largeFilesSkipped % 10 == 0 {
                                    let mb = fileSizeLimit / 1_024 / 1_024
                                    print("📏 Skipped \(largeFilesSkipped) large files (>=\(mb) MB)")
                                }
                            }
                        }
                        
                        processedUpTo = newlineIndex + 1
                    }
                    
                    // Keep only the unprocessed remainder
                    buffer = Data(buffer[processedUpTo...])
                }
            }
            
            // Process any remaining data in the buffer
            if !buffer.isEmpty, let remainingText = String(data: buffer, encoding: .utf8) {
                let lines = remainingText.components(separatedBy: "\n")
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if !fileExceedsLimit(at: trimmed) {
                            filesToScan.append(trimmed)
                        } else {
                            largeFilesSkipped += 1
                        }
                    }
                }
            }
            
            task.waitUntilExit()
            
            // Calculate how many files were skipped by extension
            let skippedByExtension = skipExtensions ? calculateSkippedByExtension(
                directory: directory,
                extensionsToSkip: extensionsToSkip
            ) : 0
            
            print("🔍 Found \(filesToScan.count) files to scan")
            print("📏 Skipped \(largeFilesSkipped) large files")
            print("🔤 Estimated \(skippedByExtension) files skipped by extension")
            
            // Log summary of what will be scanned vs. skipped
            let totalSkipped = skippedByExtension + largeFilesSkipped
            logDebug("SCAN SUMMARY:")
            logDebug("Files to scan: \(filesToScan.count)")
            logDebug("Skipped by extension: \(skippedByExtension)")
            logDebug("Skipped large files: \(largeFilesSkipped)")
            logDebug("Total files processed: \(filesToScan.count + totalSkipped)")
            
            // Sample of files that will be scanned (for verification)
            if !filesToScan.isEmpty {
                logDebug("Sample of files that WILL be scanned:")
                for file in filesToScan.prefix(5) {
                    logDebug("  - \(URL(fileURLWithPath: file).lastPathComponent)")
                }
                if filesToScan.count > 5 {
                    logDebug("  - ... and \(filesToScan.count - 5) more")
                }
            }
            
            return (skippedByExtension, largeFilesSkipped, filesToScan)
        } catch {
            print("❌ Error finding files: \(error.localizedDescription)")
            logDebug("ERROR: Failed to find files: \(error.localizedDescription)")
            throw error
        }
    }
    
    // Estimate how many files were skipped by extension (without loading them all)
    private func calculateSkippedByExtension(directory: String, extensionsToSkip: [String]) -> Int {
        var count = 0
        
        // Only do a sample count to avoid performance issues
        // We're looking for a general estimate, not exact count
        
        // First, get a fast count of all files (including those we'd skip)
        let countTask = Process()
        let countPipe = Pipe()
        
        countTask.executableURL = URL(fileURLWithPath: "/bin/sh")
        
        // Sample count by looking at a subset of extensions
        var sampleExtensions = Array(extensionsToSkip.prefix(5))
        if sampleExtensions.isEmpty {
            return 0
        }
        
        let pattern = sampleExtensions.joined(separator: "\\|")
        countTask.arguments = ["-c", "find \(directory) -type f | grep -i \"\\.\\(\(pattern)\\)$\" | wc -l"]
        countTask.standardOutput = countPipe
        
        do {
            try countTask.run()
            let data = countPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let sampleCount = Int(output) {
                
                // Extrapolate based on the percentage of extensions we sampled
                let sampleRatio = Double(sampleExtensions.count) / Double(extensionsToSkip.count)
                count = Int(Double(sampleCount) / sampleRatio)
            }
            
            countTask.waitUntilExit()
        } catch {
            print("⚠️ Error estimating skipped files: \(error.localizedDescription)")
        }
        
        return count
    }
    
    // Function to check if a file exceeds the size limit
    private func fileExceedsLimit(at path: String) -> Bool {
        let fileManager = FileManager.default
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            if let fileSize = attributes[.size] as? UInt64 {
                return fileSize >= fileSizeLimit
            }
        } catch {
            // Silent error - don't log for every file
        }
        
        return false // If we can't determine the size, we'll scan the file
    }
    
    func scanVolume(
        volume: ExternalVolume,
        totalFiles: Int,
        progressCallback: @escaping (Int, [String], String) -> Void
    ) async throws -> (Int, [String]) {
        isCancelled = false
        
        // Check if extension filtering is enabled from settings
        let skipExtensionsEnabled = UserDefaults.standard.bool(forKey: "skipExtensionsEnabled")
        var extensionsToSkip: [String] = []
        
        if skipExtensionsEnabled {
            let extensionsString = UserDefaults.standard.string(forKey: "extensionsToSkip") ?? ""
            extensionsToSkip = extensionsString
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            
            print("🔤 Extension filtering enabled with \(extensionsToSkip.count) extensions to skip")
        }
        
        let clamScanPath = clamScanExecutable()
        let dbPath = clamAVDatabasePath()
        
        guard FileManager.default.fileExists(atPath: clamScanPath.path) else {
            throw ScanError.clamAVNotAvailable
        }
        
        // Get pre-filtered list of files to scan
        let (skippedByExtension, skippedLargeFiles, filesToScan) = try await getFilesToScan(
            in: volume.path.path,
            skipExtensions: skipExtensionsEnabled,
            extensionsToSkip: extensionsToSkip
        )
        
        // FIX: We'll reset the total files to just the ones we're actually scanning
        let actualFilesToScan = filesToScan.count
        
        // Report initial progress with the new file count
        progressCallback(0, [], "Preparing scan...")
        
        if isCancelled { throw ScanError.scanCancelled }
        if !FileManager.default.fileExists(atPath: volume.path.path) { throw ScanError.volumeRemoved }
        
        if filesToScan.isEmpty {
            print("⚠️ No files to scan after filtering")
            return (skippedByExtension + skippedLargeFiles, [])
        }
        
        // Create a temporary file with the filtered list of files to scan
        let tempDir = FileManager.default.temporaryDirectory
        let fileListPath = tempDir.appendingPathComponent("files_to_scan_\(UUID().uuidString).txt")
        
        do {
            // Write file list to temp file
            try filesToScan.joined(separator: "\n").write(to: fileListPath, atomically: true, encoding: .utf8)
            
            // Create task for ClamAV that will read from our pre-filtered list
            let task = Process()
            task.executableURL = clamScanPath
            task.arguments = [
                "--infected",
                "--verbose",
                "--file-list=\(fileListPath.path)",
                "--database=\(dbPath.path)"
            ]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            task.standardOutput = outputPipe
            task.standardError = errorPipe
            
            let scanState = ScanState()
            
            // FIX: Set the total files to scan to the actual number of files we're scanning
            await scanState.setTotalFilesToScan(actualFilesToScan)
            
            // Initialize with skipped file counts
            await scanState.setSkippedByExtension(skippedByExtension)
            await scanState.setSkippedLargeFiles(skippedLargeFiles)
            
            // Setup the output pipe handler
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.count > 0, let line = String(data: data, encoding: .utf8), !line.isEmpty {
                    Task {
                        await self.processScanLine(
                            line,
                            scanState: scanState,
                            totalToScan: actualFilesToScan,
                            progressCallback: progressCallback
                        )
                    }
                }
            }
            
            try task.run()
            task.waitUntilExit()
            
            // Clean up resources
            outputPipe.fileHandleForReading.readabilityHandler = nil
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: fileListPath)
            
            if isCancelled { throw ScanError.scanCancelled }
            if !FileManager.default.fileExists(atPath: volume.path.path) { throw ScanError.volumeRemoved }
            
            if task.terminationStatus > 1 {
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
                print("❌ ClamAV stderr: \(stderr)")
                throw ScanError.scanFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            
            let count = await scanState.getCurrentScanned()
            let skippedByExt = await scanState.getSkippedByExtension()
            let skippedLarge = await scanState.getSkippedLargeFiles()
            let infected = await scanState.getInfectedFiles()
            
            print("✅ Scan completed:")
            print("   - Files scanned: \(count)")
            print("   - Files skipped by extension: \(skippedByExt)")
            print("   - Large files skipped: \(skippedLarge)")
            print("   - Infected files found: \(infected.count)")
            
            // Calculate total processed files
            let totalProcessed = await scanState.getTotalProcessed() + skippedByExtension + skippedLargeFiles
            
            // FIX: Make sure we report 100% progress when done
            progressCallback(actualFilesToScan, infected, "Scan complete")
            
            return (totalProcessed, infected)
        } catch {
            // Clean up temporary file in case of error
            try? FileManager.default.removeItem(at: fileListPath)
            
            throw error is ScanError ? error : ScanError.scanFailed(error.localizedDescription)
        }
    }
    
    private func processScanLine(
        _ line: String,
        scanState: ScanState,
        totalToScan: Int,
        progressCallback: @escaping (Int, [String], String) -> Void
    ) async {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.hasSuffix("FOUND"), let range = trimmed.range(of: ": ") {
            // Handle infected file detection
            let path = String(trimmed[..<range.lowerBound])
            await scanState.addInfectedFile(path)
            
            // Get progress information
            let current = await scanState.getCurrentScanned()
            let infected = await scanState.getInfectedFiles()
            
            // FIX: Report progress based on actual scan count, not total files on drive
            progressCallback(current, infected, path)
            
            // Log the infection
            print("🔴 Found infection: \(path)")
        } else if trimmed.contains("Scanning ") {
            // Extract file path and increment counter
            let filePath = trimmed.replacingOccurrences(of: "Scanning ", with: "")
            let current = await scanState.incrementScanned()
            
            // FIX: Update progress based on scanned/totalToScan
            if current % 2 == 0 || current == totalToScan {
                let infected = await scanState.getInfectedFiles()
                progressCallback(current, infected, filePath)
                
                // Log progress less frequently
                if current % 10 == 0 || current == totalToScan {
                    print("🔄 Progress: \(current)/\(totalToScan) files scanned, currently scanning: \(filePath)")
                }
            }
        }
    }
    
    func updateVirusDefinitions(onSuccess: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
        print("🔄 Starting virus definitions update...")
        
        // Find the wrapper script path in the Resources folder
        let wrapperPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/freshclam_wrapper.sh")
        
        // Find the config file path
        let configPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/clamav/freshclam.conf")
        
        guard FileManager.default.fileExists(atPath: wrapperPath.path) else {
            print("❌ freshclam_wrapper.sh not found at \(wrapperPath.path)")
            onFailure("Update tool not found. Please reinstall the application.")
            return
        }
        
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            print("❌ freshclam.conf not found at \(configPath.path)")
            onFailure("Configuration file not found. Please reinstall the application.")
            return
        }
        
        // Make sure the script is executable
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperPath.path)
        
        let task = Process()
        task.executableURL = wrapperPath
        task.arguments = ["--config-file=\(configPath.path)"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            
            DispatchQueue.global(qos: .background).async {
                task.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    if task.terminationStatus == 0 {
                        print("✅ Virus definitions updated successfully")
                        print("📝 Update output: \(output)")
                        onSuccess()
                    } else {
                        print("❌ Virus definition update failed with status \(task.terminationStatus)")
                        print("📝 Error output: \(error)")
                        onFailure(error.isEmpty ? "Update failed (status \(task.terminationStatus))" : error)
                    }
                }
            }
        } catch {
            print("❌ Failed to start update process: \(error.localizedDescription)")
            onFailure("Failed to start update: \(error.localizedDescription)")
        }
    }
}
