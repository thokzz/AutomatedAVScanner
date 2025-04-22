import SwiftUI

struct ExtensionFilterDebugView: View {
    @ObservedObject var themeManager: ThemeManager
    @State private var logEntries: [String] = []
    @State private var isRefreshing = false
    let scanEngine = ScanEngine()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Extension Filter Debug")
                    .font(.headline)
                    .foregroundColor(themeManager.currentTheme.text)
                
                Spacer()
                
                Button(action: {
                    refreshLog()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
            }
            .padding()
            .background(themeManager.currentTheme.background)
            
            Divider()
                .background(themeManager.currentTheme.secondaryText.opacity(0.2))
            
            // Console output
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if logEntries.isEmpty {
                        HStack {
                            Spacer()
                            
                            VStack(spacing: 10) {
                                Image(systemName: "text.magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                
                                Text("No filter logs available")
                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                
                                Text("Run a scan to see extension filtering in action")
                                    .font(.caption)
                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                
                                Button("Run Test Filter") {
                                    runTestFilter()
                                }
                                .buttonStyle(.bordered)
                                .padding(.top, 8)
                            }
                            .padding(.vertical, 50)
                            
                            Spacer()
                        }
                    } else {
                        ForEach(logEntries, id: \.self) { entry in
                            Text(entry)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(logColor(for: entry))
                                .padding(.vertical, 1)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal)
            }
            .background(themeManager.currentTheme.background)
            
            // Control buttons
            HStack {
                Button(action: {
                    runTestFilter()
                }) {
                    Label("Test Filter", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                .tint(themeManager.currentTheme.accent)
                
                Spacer()
                
                Button(action: {
                    scanEngine.clearDebugLog()
                    logEntries.removeAll()
                }) {
                    Label("Clear Log", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(themeManager.currentTheme.error)
            }
            .padding()
            .background(themeManager.currentTheme.background)
        }
        .frame(width: 600, height: 400)
        .onAppear {
            refreshLog()
        }
    }
    
    private func refreshLog() {
        isRefreshing = true
        logEntries = scanEngine.getExtensionFilterDebugLog()
        
        // If empty, add a hint
        if logEntries.isEmpty {
            logEntries = [
                "No filter logs available yet.",
                "Use the 'Test Filter' button to simulate extension filtering.",
                "When you run a real scan, detailed logs will appear here."
            ]
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isRefreshing = false
        }
    }
    
    private func runTestFilter() {
        isRefreshing = true
        
        // Get current settings
        let skipEnabled = UserDefaults.standard.bool(forKey: "skipExtensionsEnabled")
        let extensionsString = UserDefaults.standard.string(forKey: "extensionsToSkip") ?? ""
        let extensions = extensionsString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        
        // Create a temporary directory with test file types
        DispatchQueue.global().async {
            do {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("filter_test")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                // Create some test files
                let testFiles = [
                    "document.pdf", "image.jpg", "archive.zip", "script.js",
                    "movie.mp4", "executable.exe", "spreadsheet.xlsx", "music.mp3"
                ]
                
                for file in testFiles {
                    let filePath = tempDir.appendingPathComponent(file)
                    try Data().write(to: filePath)
                }
                
                // Run the filter
                Task {
                    do {
                        _ = try await self.scanEngine.getFilesToScan(
                            in: tempDir.path,
                            skipExtensions: skipEnabled,
                            extensionsToSkip: extensions
                        )
                        
                        // Update the UI on main thread
                        DispatchQueue.main.async {
                            self.refreshLog()
                            self.isRefreshing = false
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.logEntries.append("Error running test: \(error.localizedDescription)")
                            self.isRefreshing = false
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.logEntries.append("Error creating test files: \(error.localizedDescription)")
                    self.isRefreshing = false
                }
            }
        }
    }
    
    private func logColor(for entry: String) -> Color {
        if entry.contains("WARNING") || entry.contains("Skip") {
            return themeManager.currentTheme.warning
        } else if entry.contains("Error") || entry.contains("fail") {
            return themeManager.currentTheme.error
        } else if entry.contains("Will") || entry.contains("WILL") {
            return themeManager.currentTheme.primary
        } else if entry.contains("SUMMARY") || entry.contains("scan:") {
            return themeManager.currentTheme.success
        } else {
            return themeManager.currentTheme.text
        }
    }
}
