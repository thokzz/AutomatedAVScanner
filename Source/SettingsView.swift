import SwiftUI

class ScanSettings: ObservableObject {
    @Published var skipExtensionsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(skipExtensionsEnabled, forKey: "skipExtensionsEnabled")
            self.settingsChanged = true
            self.updateDebugInfo()
        }
    }
    
    @Published var extensionsToSkip: String {
        didSet {
            self.extensionsEdited = true
            self.updateDebugInfo()
        }
    }
    
    @Published var fileSizeLimitMB: Int {
        didSet {
            UserDefaults.standard.set(fileSizeLimitMB, forKey: "fileSizeLimitMB")
            self.settingsChanged = true
            self.updateDebugInfo()
        }
    }
    
    // Debug and status properties
    @Published var extensionsEdited: Bool = false
    @Published var settingsChanged: Bool = false
    @Published var showSaveSuccess: Bool = false
    @Published var debugInfo: String = ""
    @Published var showDebugConsole: Bool = false
    
    // Default safe extensions based on our cybersecurity analysis
    static let defaultExtensionsToSkip = ".heic"
    
    init() {
        // Load saved settings or use defaults
        self.skipExtensionsEnabled = UserDefaults.standard.bool(forKey: "skipExtensionsEnabled")
        self.extensionsToSkip = UserDefaults.standard.string(forKey: "extensionsToSkip") ?? ScanSettings.defaultExtensionsToSkip
        self.fileSizeLimitMB = UserDefaults.standard.integer(forKey: "fileSizeLimitMB")
        
        // Apply default if unset
        if fileSizeLimitMB == 0 {
            fileSizeLimitMB = 100 // Default to 100 MB
        }
        
        // Initialize debug info
        updateDebugInfo()
    }
    
    func resetToDefaults() {
        extensionsToSkip = ScanSettings.defaultExtensionsToSkip
        extensionsEdited = true
        updateDebugInfo()
    }
    
    // Save extensions and show feedback
    func saveExtensions() {
        UserDefaults.standard.set(extensionsToSkip, forKey: "extensionsToSkip")
        extensionsEdited = false
        showSaveSuccess = true
        settingsChanged = true
        updateDebugInfo()
        
        // Hide success message after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showSaveSuccess = false
        }
    }
    
    // Parse the comma-separated string into a clean array of extensions
    func getExtensionsArray() -> [String] {
        let rawExtensions = extensionsToSkip.components(separatedBy: ",")
        return rawExtensions.map {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.hasPrefix(".") ? trimmed : ".\(trimmed)"
        }.filter { !$0.isEmpty }
    }
    
    // Update debug information
    func updateDebugInfo() {
        let extensions = getExtensionsArray()
        
        var info = "======= FILTER CONFIGURATION =======\n"
        info += "Extension filtering: \(skipExtensionsEnabled ? "ENABLED" : "DISABLED")\n"
        info += "File size limit: \(fileSizeLimitMB) MB\n\n"
        
        info += "===== EXTENSION FILTER STATUS =====\n"
        if skipExtensionsEnabled {
            if extensions.isEmpty {
                info += "No extensions configured to skip\n"
                info += "WARNING: Empty filter - all files will be scanned\n"
            } else {
                info += "Extensions that will be SKIPPED during scan:\n"
                for ext in extensions {
                    info += "- \(ext)\n"
                }
                
                info += "\nTotal extensions to skip: \(extensions.count)\n"
            }
            
            // Check for common high-risk extensions that should not be skipped
            let highRiskExtensions = [".exe", ".dll", ".bat", ".js", ".vbs", ".ps1", ".sh"]
            let skippedHighRiskExts = extensions.filter { highRiskExt in
                highRiskExtensions.contains { $0.lowercased() == highRiskExt.lowercased() }
            }
            
            if !skippedHighRiskExts.isEmpty {
                info += "\n⚠️ WARNING: You are skipping high-risk extensions:\n"
                for ext in skippedHighRiskExts {
                    info += "- \(ext) (SECURITY RISK!)\n"
                }
                info += "These extensions are commonly associated with malware.\n"
            }
            
            info += "\nFile types that will always be scanned:\n"
            info += "- Executables (.exe, .dll, etc.)\n"
            info += "- Scripts (.ps1, .bat, .sh, etc.)\n"
            info += "- Office documents with macros\n"
            info += "- System files\n"
        } else {
            info += "Extension filtering is disabled\n"
            info += "ALL files will be scanned regardless of extension\n"
        }
        
        info += "\n===== SIZE FILTER STATUS =====\n"
        info += "Files larger than \(fileSizeLimitMB) MB will be SKIPPED\n"
        
        // Display warning if file size limit is too low
        if fileSizeLimitMB < 50 {
            info += "⚠️ WARNING: Small file size limit may skip important files\n"
        }
        
        debugInfo = info
    }
}


struct SettingsView: View {
    @ObservedObject var themeManager: ThemeManager
    @StateObject private var settings = ScanSettings()
    @State private var showResetConfirmation = false
    @State private var showSecurityDetails = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with status indicator
            HStack {
                Text("Settings")
                    .font(.title2)
                    .bold()
                    .foregroundColor(themeManager.currentTheme.text)
                
                Spacer()
                
                if settings.settingsChanged {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(themeManager.currentTheme.success)
                        Text("Settings Applied")
                            .font(.caption)
                            .foregroundColor(themeManager.currentTheme.success)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(themeManager.currentTheme.success.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Add debug console toggle
                Button(action: {
                    settings.showDebugConsole.toggle()
                }) {
                    Label(settings.showDebugConsole ? "Hide Console" : "Show Console", systemImage: settings.showDebugConsole ? "terminal.fill" : "terminal")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(themeManager.currentTheme.accent)
            }
            .padding()
            .background(themeManager.currentTheme.background)
            
            Divider()
                .background(themeManager.currentTheme.secondaryText.opacity(0.2))
            
            // Debug console (collapsible)
            if settings.showDebugConsole {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Extension Filter Console")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(themeManager.currentTheme.text)
                        
                        Spacer()
                        
                        Button(action: {
                            settings.updateDebugInfo()
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(themeManager.currentTheme.accent)
                    }
                    
                    ScrollView {
                        Text(settings.debugInfo)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 200)
                    .background(themeManager.currentTheme.secondaryBackground.opacity(0.5))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // File Extension Filtering Section
                    GroupBox(label:
                                Label("File Extension Filtering", systemImage: "doc.text.magnifyingglass")
                        .foregroundColor(themeManager.currentTheme.text)
                    ) {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack {
                                Toggle("Enable Scan Skipping", isOn: $settings.skipExtensionsEnabled)
                                    .foregroundColor(themeManager.currentTheme.text)
                                    .padding(.vertical, 4)
                                
                                Spacer()
                                
                                // Status indicator for enabled/disabled
                                if settings.skipExtensionsEnabled {
                                    Text("Active")
                                        .font(.caption)
                                        .foregroundColor(themeManager.currentTheme.success)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(themeManager.currentTheme.success.opacity(0.1))
                                        .cornerRadius(8)
                                } else {
                                    Text("Disabled")
                                        .font(.caption)
                                        .foregroundColor(themeManager.currentTheme.secondaryText)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(themeManager.currentTheme.secondaryText.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                            
                            // Extension preview - quick summary of what will be skipped
                            if settings.skipExtensionsEnabled {
                                let extensions = settings.getExtensionsArray()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Files that will be skipped:")
                                        .font(.caption)
                                        .foregroundColor(themeManager.currentTheme.secondaryText)
                                    
                                    if extensions.isEmpty {
                                        Text("No extensions configured - all files will be scanned")
                                            .font(.caption)
                                            .foregroundColor(themeManager.currentTheme.warning)
                                            .padding(.top, 2)
                                    } else {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 4) {
                                                ForEach(extensions.prefix(10), id: \.self) { ext in
                                                    Text(ext)
                                                        .font(.caption2)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(themeManager.currentTheme.accent.opacity(0.1))
                                                        .foregroundColor(themeManager.currentTheme.accent)
                                                        .cornerRadius(4)
                                                }
                                                
                                                if extensions.count > 10 {
                                                    Text("+\(extensions.count - 10) more")
                                                        .font(.caption2)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(themeManager.currentTheme.secondaryText.opacity(0.1))
                                                        .foregroundColor(themeManager.currentTheme.secondaryText)
                                                        .cornerRadius(4)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                .padding(8)
                                .background(themeManager.currentTheme.secondaryBackground.opacity(0.3))
                                .cornerRadius(8)
                            }
                            
                            Text("Extensions to skip:")
                                .font(.callout)
                                .foregroundColor(themeManager.currentTheme.secondaryText)
                            
                            VStack(spacing: 4) {
                                TextEditor(text: $settings.extensionsToSkip)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.text)
                                    .frame(minHeight: 120)
                                    .padding(8)
                                    .background(themeManager.currentTheme.secondaryBackground)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(settings.extensionsEdited ? themeManager.currentTheme.accent : themeManager.currentTheme.secondaryText.opacity(0.3), lineWidth: settings.extensionsEdited ? 2 : 1)
                                    )
                                    .disabled(!settings.skipExtensionsEnabled)
                                    .opacity(settings.skipExtensionsEnabled ? 1.0 : 0.6)
                                
                                // Show indicator when changes are pending
                                if settings.extensionsEdited {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(themeManager.currentTheme.warning)
                                            .font(.caption2)
                                        
                                        Text("Unsaved changes")
                                            .font(.caption2)
                                            .foregroundColor(themeManager.currentTheme.warning)
                                        
                                        Spacer()
                                        
                                        Button("Save Changes") {
                                            settings.saveExtensions()
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(themeManager.currentTheme.accent)
                                        .font(.caption)
                                    }
                                    .padding(.top, 2)
                                }
                                
                                // Show success indicator
                                if settings.showSaveSuccess {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(themeManager.currentTheme.success)
                                            .font(.caption2)
                                        
                                        Text("Extension filters saved and applied")
                                            .font(.caption2)
                                            .foregroundColor(themeManager.currentTheme.success)
                                        
                                        Spacer()
                                    }
                                    .padding(.top, 2)
                                    .transition(.opacity)
                                }
                            }
                            
                            HStack {
                                Text("Enter file extensions separated by commas (e.g., .jpg, .mp3)")
                                    .font(.caption)
                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                
                                Spacer()
                                
                                Button("Reset to Defaults") {
                                    showResetConfirmation = true
                                }
                                .foregroundColor(themeManager.currentTheme.accent)
                                .disabled(!settings.skipExtensionsEnabled)
                            }
                            .padding(.top, 4)
                            
                            // Help text for extension format
                            Text("Make sure each extension includes the dot (.) prefix. For example: .jpg, .png, .mp3")
                                .font(.caption2)
                                .foregroundColor(themeManager.currentTheme.warning)
                                .padding(.top, 2)
                            
                            // Information about security implications
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Security Notes:")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(themeManager.currentTheme.text)
                                
                                Text("High-risk files (executables, scripts, documents with macros) are always scanned regardless of this setting.")
                                    .font(.caption)
                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                
                                DisclosureGroup(
                                    isExpanded: $showSecurityDetails,
                                    content: {
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text("Known risks with media files:")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(themeManager.currentTheme.error.opacity(0.8))
                                            
                                            Group {
                                                Text("Image Formats")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(themeManager.currentTheme.text)
                                                
                                                Text("• **.svg** - SVG can contain embedded JavaScript, making it capable of executing code when viewed in browsers or applications that render SVG with JavaScript enabled")
                                                    .font(.caption)
                                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                                
                                                Text("• **.png/.jpg/.gif** - Have been used in image-based exploits that target vulnerabilities in image processing libraries (known as \"IIFE\" or Image File Execution Exploits)")
                                                    .font(.caption)
                                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                            }
                                            
                                            Group {
                                                Text("Video Formats")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(themeManager.currentTheme.text)
                                                    .padding(.top, 4)
                                                
                                                Text("• **.mp4/.mov/.avi** - Certain malformed video files have been used to exploit vulnerabilities in media players")
                                                    .font(.caption)
                                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                                
                                                Text("• **.wmv** - Has been associated with some exploits targeting Windows Media Player vulnerabilities")
                                                    .font(.caption)
                                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                            }
                                            
                                            Group {
                                                Text("Audio Formats")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(themeManager.currentTheme.text)
                                                    .padding(.top, 4)
                                                
                                                Text("• **.wav/.mp3** - Have occasionally been used in buffer overflow attacks targeting media player vulnerabilities")
                                                    .font(.caption)
                                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                            }
                                        }
                                        .padding(.vertical, 8)
                                    },
                                    label: {
                                        HStack {
                                            Text("View Security Risks")
                                                .font(.caption)
                                                .foregroundColor(themeManager.currentTheme.accent)
                                            
                                            Image(systemName: showSecurityDetails ? "chevron.up" : "chevron.down")
                                                .font(.caption)
                                                .foregroundColor(themeManager.currentTheme.accent)
                                        }
                                    }
                                )
                                .padding(.vertical, 4)
                                
                                Text("File extension filtering can significantly improve scan speed. While these media formats rarely contain malware, they are occasionally vulnerable to exploits. This setting offers a balance between performance and comprehensive security.")
                                    .font(.caption)
                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                    .padding(.top, 4)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(themeManager.currentTheme.secondaryBackground.opacity(0.5))
                            .cornerRadius(8)
                        }
                        .padding()
                        .animation(.easeInOut(duration: 0.2), value: settings.extensionsEdited)
                        .animation(.easeInOut(duration: 0.2), value: settings.showSaveSuccess)
                    }
                    .groupBoxStyle(CardGroupBoxStyle(themeManager: themeManager))
                    
                    // File Size Skipping Section
                    GroupBox(label:
                                Label("File Size Skipping", systemImage: "externaldrive.badge.xmark")
                        .foregroundColor(themeManager.currentTheme.text)
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Skip files larger than:")
                                    .font(.callout)
                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                
                                Spacer()
                                
                                // Add status indicator
                                Text("Currently: \(settings.fileSizeLimitMB) MB")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(themeManager.currentTheme.accent.opacity(0.1))
                                    .foregroundColor(themeManager.currentTheme.accent)
                                    .cornerRadius(8)
                            }
                            
                            HStack {
                                Slider(value: Binding(
                                    get: { Double(settings.fileSizeLimitMB) },
                                    set: { settings.fileSizeLimitMB = Int($0) }
                                ), in: 10...1024, step: 10)
                                .onChange(of: settings.fileSizeLimitMB) { _ in
                                    // Show success message when slider value changes
                                    settings.showSaveSuccess = true
                                    
                                    // Hide success message after delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        settings.showSaveSuccess = false
                                    }
                                }
                                
                                Text("\(settings.fileSizeLimitMB) MB")
                                    .frame(width: 60, alignment: .leading)
                                    .font(.caption)
                                    .foregroundColor(themeManager.currentTheme.text)
                            }
                            
                            Text("Files larger than this size will be skipped during scanning.")
                                .font(.caption)
                                .foregroundColor(themeManager.currentTheme.secondaryText)
                                .padding(.bottom, 4)
                            
                            // Show when setting is saved
                            if settings.showSaveSuccess {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(themeManager.currentTheme.success)
                                        .font(.caption2)
                                    
                                    Text("Size limit updated and applied")
                                        .font(.caption2)
                                        .foregroundColor(themeManager.currentTheme.success)
                                    
                                    Spacer()
                                }
                                .padding(.top, 2)
                                .transition(.opacity)
                            }
                        }
                        .padding()
                        .animation(.easeInOut(duration: 0.2), value: settings.showSaveSuccess)
                    }
                    .groupBoxStyle(CardGroupBoxStyle(themeManager: themeManager))
                    
                    Spacer()
                }
                .padding()
            }
        }
        .background(themeManager.currentTheme.background)
        .animation(.easeInOut(duration: 0.3), value: settings.showDebugConsole)
        .alert("Reset to Defaults?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
            }
        } message: {
            Text("This will restore the default list of low-risk file extensions.")
        }
    }
}

// Custom GroupBox style to match app theme
struct CardGroupBoxStyle: GroupBoxStyle {
    var themeManager: ThemeManager
    
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading) {
            configuration.label
                .font(.headline)
                .padding(.bottom, 4)
            
            configuration.content
        }
        .background(themeManager.currentTheme.background)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(themeManager.currentTheme.secondaryText.opacity(0.2), lineWidth: 1)
        )
        .shadow(
            color: themeManager.currentTheme.primary.opacity(0.1),
            radius: themeManager.currentTheme.shadowRadius / 2,
            x: 0, y: 1
        )
    }
}
