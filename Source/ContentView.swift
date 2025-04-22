import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var scanSettings = ScanSettings()
    @State private var updateStatus: String?
    @State private var showingThemeSettings = false
    private let scanEngine = ScanEngine()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // App Header with toggles aligned to top-right
                HStack {
                    Image("CustomExternalDriveShield")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24) // Adjust size as needed
                        .foregroundColor(themeManager.currentTheme.primary)

                    Text("Automated Virus Scanner v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.title)
                        .bold()
                        .foregroundColor(themeManager.currentTheme.text)

                    Spacer()
                    
                    Button {
                        showingThemeSettings.toggle()
                    } label: {
                        Image(systemName: "paintpalette")
                            .foregroundColor(themeManager.currentTheme.accent)
                    }
                    .buttonStyle(.bordered)
                    .help("Theme Settings")
                    .padding(.trailing, 4)

                    Toggle("Auto Scan", isOn: $coordinator.autoScanEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(themeManager.currentTheme.accent)
                        .help("Toggle automatic scanning when a drive is connected")
                    Text("Auto Scan")
                        .font(.caption)
                        .foregroundColor(themeManager.currentTheme.text)

                    Toggle("Auto Print", isOn: $coordinator.autoPrintEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(themeManager.currentTheme.accent)
                        .help("Toggle automatic printing after a scan")
                    Text("Auto Print")
                        .font(.caption)
                        .foregroundColor(themeManager.currentTheme.text)
                }
                .padding()
                .background(themeManager.currentTheme.background)

                Divider()
                    .background(themeManager.currentTheme.secondaryText.opacity(0.2))

                TabView(selection: $coordinator.activeTab) {
                    ScanView(
                        coordinator: coordinator,
                        scanEngine: scanEngine,
                        updateStatus: $updateStatus,
                        themeManager: themeManager
                    )
                    .tabItem {
                        Label("Scan Drives", systemImage: "externaldrive.fill")
                    }
                    .tag(0)

                    TransactionHistoryView(
                        coordinator: coordinator,
                        themeManager: themeManager
                    )
                    .tabItem {
                        Label("History", systemImage: "clock")
                    }
                    .tag(1)
                    
                    SettingsView(
                        themeManager: themeManager
                    )
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(2)
                }
                .accentColor(themeManager.currentTheme.accent)
            }
            .frame(minWidth: 700)
            .background(themeManager.currentTheme.background)

            Divider()
                .background(themeManager.currentTheme.secondaryText.opacity(0.2))

            MiniDiskUtilityView(
                coordinator: coordinator,
                themeManager: themeManager
            )
            .frame(minWidth: 280, maxWidth: 330)
            .background(themeManager.currentTheme.background)
        }
        .frame(minWidth: 1150, minHeight: 500)
        .sheet(isPresented: $showingThemeSettings) {
            ThemeSettingsView(themeManager: themeManager)
        }
        .environmentObject(themeManager) // Make ThemeManager available throughout the app
        .environmentObject(scanSettings) // Make ScanSettings available throughout the app
    }
}

struct ScanView: View {
    @ObservedObject var coordinator: AppCoordinator
    let scanEngine: ScanEngine
    @Binding var updateStatus: String?
    @ObservedObject var themeManager: ThemeManager
    @AppStorage("hideWhitelistedDrives") private var hideWhitelistedDrives: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Active Drives")
                    .font(.title2)
                    .bold()
                    .foregroundColor(themeManager.currentTheme.text)

                Spacer()

                Toggle("Hide Whitelisted", isOn: $hideWhitelistedDrives)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(themeManager.currentTheme.accent)
                    .help("Hide volumes marked as whitelisted")
                Text("Hide Whitelisted")
                    .font(.caption)
                    .foregroundColor(themeManager.currentTheme.text)

                Button {
                    updateStatus = "Updating..."
                    scanEngine.updateVirusDefinitions {
                        updateStatus = "✅ Virus definitions updated"
                    } onFailure: { error in
                        updateStatus = "❌ Update failed: \(error)"
                    }
                } label: {
                    Label("Update Virus DB", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundColor(themeManager.currentTheme.accent)
                }
                .buttonStyle(.bordered)
                .tint(themeManager.currentTheme.accent)

                if let status = updateStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                }

                Button {
                    coordinator.volumeMonitor.refreshConnectedVolumes()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .foregroundColor(themeManager.currentTheme.accent)
                }
                .buttonStyle(.bordered)
                .tint(themeManager.currentTheme.accent)
            }
            .padding()
            .background(themeManager.currentTheme.background)

            Divider()
                .background(themeManager.currentTheme.secondaryText.opacity(0.2))

            ScrollView {
                VStack(spacing: 12) {
                    if coordinator.connectedVolumes.isEmpty {
                        VStack(spacing: 20) {
                            Spacer()
                            Image(systemName: "externaldrive.badge.plus")
                                .font(.system(size: 64))
                                .foregroundColor(themeManager.currentTheme.secondaryText)
                            Text("No external drives detected")
                                .font(.title3)
                                .foregroundColor(themeManager.currentTheme.secondaryText)
                            Text("Connect a USB drive to start scanning")
                                .font(.subheadline)
                                .foregroundColor(themeManager.currentTheme.secondaryText)
                            Spacer()
                        }
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        ForEach(coordinator.connectedVolumes.filter {
                            !hideWhitelistedDrives || !WhitelistManager.shared.isWhitelisted(volume: $0)
                        }) { volume in
                            let key = "\(volume.volumeUUID)-\(volume.name)"
                            if let state = coordinator.volumeStates[key] {
                                ScanStatusView(
                                    volumeState: state,
                                    themeManager: themeManager,
                                    onCancelTap: { coordinator.cancelScanForVolume(volume) },
                                    onStartTap: { coordinator.startScanningVolume(volume) }
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .background(themeManager.currentTheme.background)
        }
    }
}
