import Foundation
import ZIPFoundation

class FileCounter {
    enum FileCountingError: Error {
        case volumeNotFound
        case accessDenied
        case cancelled
        case zipOpenFailed
    }

    // System directories to skip (synced with ScanEngine)
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
        ".DS_Store"                    // macOS directory attributes files
    ]
    
    // Size limit to match ScanEngine
    private let FILE_SIZE_LIMIT: UInt64 = 100 * 1024 * 1024  // 100 MB in bytes

    private var isCancelled = false
    private var skippedSystemDirCount = 0
    private var skippedLargeFileCount = 0

    func countFiles(in volume: ExternalVolume, progressHandler: ((Int) -> Void)? = nil) async throws -> Int {
        isCancelled = false
        var count = 0
        skippedSystemDirCount = 0
        skippedLargeFileCount = 0

        print("🔍 Starting file count in volume: \(volume.name)")
        print("📂 Volume path: \(volume.path.path)")

        guard FileManager.default.fileExists(atPath: volume.path.path) else {
            throw FileCountingError.volumeNotFound
        }
        
        // Setup the find process with system directory exclusions
        let process = Process()
        let pipe = Pipe()
        
        // Build arguments with path exclusions, exactly like in ScanEngine
        var findArgs = [volume.path.path, "-type", "f"]
        
        // Add exclusions for system directories
        for dirName in SYSTEM_DIRS_TO_SKIP {
            findArgs.append("-not")
            findArgs.append("-path")
            findArgs.append("*/\(dirName)/*")
            
            // Also exclude the directory itself at the root level
            findArgs.append("-not")
            findArgs.append("-path")
            findArgs.append("*/\(dirName)")
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.arguments = findArgs
        process.standardOutput = pipe
        process.standardError = nil

        do {
            try process.run()
        } catch {
            throw FileCountingError.accessDenied
        }

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let outputString = String(data: outputData, encoding: .utf8) else {
            throw FileCountingError.accessDenied
        }

        let filePaths = outputString.split(separator: "\n")
        
        print("📊 Found \(filePaths.count) files initially (excluding system directories)")
        
        var actualFilesToScan = 0
        
        // Now process each file and check size limits
        for line in filePaths {
            if isCancelled {
                throw FileCountingError.cancelled
            }

            let filePath = String(line)
            
            // Skip large files (consistent with ScanEngine)
            if fileExceedsLimit(at: filePath) {
                skippedLargeFileCount += 1
                count += 1  // Still count it toward total but mark as skipped
                
                if skippedLargeFileCount % 100 == 0 {
                    print("📏 FileCounter: \(skippedLargeFileCount) large files skipped so far")
                }
                continue
            }
            
            actualFilesToScan += 1
            count += 1
            
            // Count files in ZIPs
            if filePath.lowercased().hasSuffix(".zip") {
                do {
                    let zipCount = try countFilesInZip(at: URL(fileURLWithPath: filePath))
                    count += zipCount
                    actualFilesToScan += zipCount
                    print("📦 Found .zip at \(URL(fileURLWithPath: filePath).lastPathComponent) → contains \(zipCount) files")
                } catch {
                    print("⚠️ Could not count .zip contents at \(filePath): \(error)")
                }
            }

            if count % 100 == 0 {
                progressHandler?(count)
            }
        }

        // Calculate min and max for the range
        let adjustedCount = count
        let minCount = Int(Double(adjustedCount) * 0.9) // Lower bound (90% of counted)
        let maxCount = Int(Double(adjustedCount) * 1.1) // Upper bound (110% of counted)

        print("📊 File counting summary:")
        print("   - Total files (including inside ZIPs): \(count)")
        print("   - Files to be scanned: \(actualFilesToScan)")
        print("   - Large files (>=100MB) to be skipped: \(skippedLargeFileCount)")
        print("   - File count range: \(minCount)-\(maxCount) files")
        
        // Final progress update with the actual count
        progressHandler?(count)
        print("✅ Final file count: \(count) total, \(actualFilesToScan) to be scanned")
        
        // Return the actual count for internal use
        return count
    }
    
    // Function to check if a file exceeds the size limit (identical to ScanEngine)
    private func fileExceedsLimit(at path: String) -> Bool {
        let fileManager = FileManager.default
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            if let fileSize = attributes[.size] as? UInt64 {
                return fileSize >= FILE_SIZE_LIMIT
            }
        } catch {
            print("⚠️ Could not check size of file at \(path): \(error.localizedDescription)")
        }
        
        return false // If we can't determine the size, we'll scan the file
    }

    private func countFilesInZip(at url: URL) throws -> Int {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw FileCountingError.zipOpenFailed
        }

        var zipFileCount = 0

        for entry in archive {
            if !entry.path.hasSuffix("/") {
                zipFileCount += 1
            }
        }

        return zipFileCount
    }

    func cancelCounting() {
        isCancelled = true
    }
    
    // Getter methods to access skipped file counts
    func getSkippedLargeFileCount() -> Int {
        return skippedLargeFileCount
    }
    
    func getSkippedSystemDirCount() -> Int {
        return skippedSystemDirCount
    }
}
