import SwiftUI

struct ScanStatusView: View {
    @State private var isWhitelisted: Bool = false
    @ObservedObject var volumeState: VolumeScanState
    @ObservedObject var themeManager: ThemeManager
    var onCancelTap: () -> Void
    var onStartTap: () -> Void

    @State private var animatingProgress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "externaldrive.fill")
                    .foregroundColor(themeManager.currentTheme.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(volumeState.volume.name)
                        .font(.headline)
                        .foregroundColor(themeManager.currentTheme.text)
                    
                    // Show multi-partition indicator if this volume is part of a multi-partition drive
                    if volumeState.isPartOfMultiPartitionDrive && volumeState.scanStatus == .waiting {
                        Text("Waiting for other partitions to complete scanning before ejection.")
                            .font(.caption2)
                            .foregroundColor(themeManager.currentTheme.waitingColor)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("Whitelist")
                        .font(.caption2)
                        .foregroundColor(themeManager.currentTheme.secondaryText)

                    Toggle(isOn: $isWhitelisted) {
                        EmptyView()
                    }
                    .toggleStyle(SwitchToggleStyle(tint: themeManager.currentTheme.accent))
                    .labelsHidden()
                    .onChange(of: isWhitelisted) { newValue in
                        let volume = volumeState.volume
                        if newValue {
                            WhitelistManager.shared.addToWhitelist(volume: volume)
                            print("✅ Volume whitelisted: \(volume.name) [\(volume.volumeUUID)]")
                        } else {
                            WhitelistManager.shared.removeFromWhitelist(volume: volume)
                            print("❌ Volume removed from whitelist: \(volume.name) [\(volume.volumeUUID)]")
                        }
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: themeManager.iconForStatus(volumeState.scanStatus))
                        .foregroundColor(themeManager.colorForStatus(volumeState.scanStatus))

                    Text(volumeState.scanStatus.rawValue)
                        .font(.subheadline)
                        .foregroundColor(themeManager.colorForStatus(volumeState.scanStatus))
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Themed progress bar with GeometryReader
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background of progress bar
                        Rectangle()
                            .fill(themeManager.currentTheme.secondaryBackground)
                            .frame(height: 6)
                            .cornerRadius(3)
                        
                        // Filled portion of progress bar
                        Rectangle()
                            .fill(themeManager.colorForStatus(volumeState.scanStatus))
                            .frame(width: max(CGFloat(volumeState.scanProgress) * geometry.size.width, 0), height: 6)
                            .cornerRadius(3)
                    }
                }
                .frame(height: 6) // Set the height of the GeometryReader
                .animation(.linear, value: volumeState.scanProgress)
                
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scanned files: \(volumeState.scannedFiles)")
                            .font(.caption2)
                            .foregroundColor(themeManager.currentTheme.text)
                        Text("This will scan files inside zip, app, pkg, dmg, etc.")
                            .font(.caption2)
                            .foregroundColor(themeManager.currentTheme.secondaryText)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Files: \(volumeState.fileCountRange.isEmpty ? "\(volumeState.fileCount)" : volumeState.fileCountRange)")
                            .font(.caption2)
                            .foregroundColor(themeManager.currentTheme.secondaryText)

                                            // New skipped files line
                        Text("Skipped files: \(volumeState.skippedFiles)")
                            .font(.caption2)
                            .foregroundColor(themeManager.currentTheme.secondaryText)

                            if volumeState.scanStatus == .waiting {
                            Text("100% (waiting for other partitions)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(themeManager.currentTheme.waitingColor)
                            } else if volumeState.scanProgress >= 1.0 {
                                Text("Finalizing...")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                            } else {
                                Text("\(Int(volumeState.scanProgress * 100))%")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(themeManager.currentTheme.primary)
                        }
                    }
                }
            }
            
            HStack {
                if volumeState.scanStatus == .scanning && volumeState.filesPerSecond > 0 {
                    Text(volumeState.scanRate)
                        .font(.caption)
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                } else {
                    Text(" ")
                        .font(.caption)
                }
                
                Spacer()
                
                if volumeState.isInfected {
                    Text("⚠️ \(volumeState.infectedFiles.count) infected")
                        .foregroundColor(themeManager.currentTheme.error)
                        .font(.caption)
                }
                
                if volumeState.scanStatus == .scanning || volumeState.scanStatus == .counting {
                    HStack(spacing: 4) {
                        Text("Scan Logs")
                            .font(.caption2)
                            .foregroundColor(themeManager.currentTheme.text)

                        Button {
                            volumeState.showDetailedScanInfo.toggle()
                        } label: {
                            Image(systemName: volumeState.showDetailedScanInfo ? "eye.slash" : "eye")
                                .font(.caption)
                                .foregroundColor(themeManager.currentTheme.accent)
                        }
                        .buttonStyle(.borderless)
                        .help(volumeState.showDetailedScanInfo ? "Hide detailed scan info" : "Show detailed scan info")
                    }
                    .buttonStyle(.borderless)
                    .help(volumeState.showDetailedScanInfo ? "Hide detailed scan info" : "Show detailed scan info")
                    
                    Button("Cancel", action: onCancelTap)
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(themeManager.currentTheme.accent)
                } else if volumeState.scanStatus == .waiting {
                    // For waiting partitions, show the waiting status but allow rescan
                    Button("Rescan", action: onStartTap)
                        .font(.caption)
                        .buttonStyle(.bordered)
                } else if volumeState.scanStatus == .completed ||
                          volumeState.scanStatus == .clean ||
                          volumeState.scanStatus == .infected ||
                          volumeState.scanStatus == .error {
                    Button("Rescan", action: onStartTap)
                        .font(.caption)
                        .buttonStyle(.bordered)
                } else if volumeState.scanStatus == .queued {
                    Button("Force Scan") {
                        // Do more aggressive reset before initiating scan
                        PhysicalDriveTracker.shared.forceRescanDrive(for: volumeState.volume)
                        
                        // Start the scan after a brief delay to allow the notification to be processed
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onStartTap()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(themeManager.currentTheme.error)
                    .buttonStyle(.bordered)
                    .help("Force a rescan even if the drive is being tracked")
                }
            }
            
            // Show multi-partition status if relevant
            if volumeState.isPartOfMultiPartitionDrive && (volumeState.scanStatus == .clean || volumeState.scanStatus == .infected || volumeState.scanStatus == .waiting) {
                HStack {
                    Image("CustomExternalDriveShield")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24) // Adjust size as needed
                        .foregroundColor(themeManager.currentTheme.primary)
                    
                    Text("Waiting for all partitions to complete scanning before ejection")
                        .font(.caption2)
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                }
                .padding(.top, 2)
            }
            
            if volumeState.scanStatus == .scanning && volumeState.estimatedTimeRemaining != nil {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(themeManager.currentTheme.primary)
                        .font(.caption2)
                    
                    Text("Estimated time remaining: \(formatTimeRemaining(volumeState.estimatedTimeRemaining!))")
                        .font(.caption2)
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                }
                .padding(.top, 2)
            }
            
            if volumeState.scanStatus == .scanning && !volumeState.lastScannedFile.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundColor(themeManager.currentTheme.primary)
                        .font(.caption2)
                    
                    Text("Scanning: \(shortenPath(volumeState.lastScannedFile))")
                        .font(.caption2)
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            if volumeState.showDetailedScanInfo && volumeState.scanStatus == .scanning {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                        .background(themeManager.currentTheme.secondaryText.opacity(0.2))
                        .padding(.vertical, 4)
                    
                    Text("Detailed Scan Information")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(themeManager.currentTheme.text)
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Scan rate:")
                                .font(.caption2)
                                .foregroundColor(themeManager.currentTheme.secondaryText)
                            Text(volumeState.scanRate)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(themeManager.currentTheme.text)
                        }
                        
                        if let startTime = volumeState.scanStartTime {
                            VStack(alignment: .leading) {
                                Text("Elapsed:")
                                    .font(.caption2)
                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                Text(formatElapsedTime(since: startTime))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(themeManager.currentTheme.text)
                            }
                        }
                    }
                    
                    Text("Recent files:")
                        .font(.caption2)
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                        .padding(.top, 2)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(volumeState.lastScannedFiles.prefix(10), id: \.self) { file in
                                Text(shortenPath(file))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.trailing, 20)
                        .frame(maxHeight: 100)
                    }
                    .background(themeManager.currentTheme.secondaryBackground.opacity(0.5))
                    .cornerRadius(themeManager.currentTheme.cornerRadius / 2)
                }
                .transition(.opacity)
                .animation(.easeInOut, value: volumeState.showDetailedScanInfo)
                .padding(.vertical, 4)
            }
            
            if let start = volumeState.scanStartTime {
                HStack {
                    if let end = volumeState.scanEndTime {
                        Text("Duration: \(formatDuration(from: start, to: end))")
                            .font(.caption2)
                            .foregroundColor(themeManager.currentTheme.secondaryText)
                    } else if volumeState.scanStatus != .scanning {
                        Text("Started: \(formatTime(start))")
                            .font(.caption2)
                            .foregroundColor(themeManager.currentTheme.secondaryText)
                    }
                }
            }

            if volumeState.scanStatus == .error, let error = volumeState.error {
                Text("⚠️ \(error)")
                    .foregroundColor(themeManager.currentTheme.warning)
                    .font(.caption2)
            }
            
            // Add a prominent rescan button specifically for completed or queued drives
            if (volumeState.scanStatus == .clean ||
                volumeState.scanStatus == .infected ||
                volumeState.scanStatus == .queued) &&
                volumeState.scanProgress >= 0.95 {
                    
                Button(action: onStartTap) {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle.fill")
                        Text("Rescan Drive")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(themeManager.currentTheme.accent)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        
        .onAppear {
            let volume = volumeState.volume
            if isWhitelisted != WhitelistManager.shared.isWhitelisted(volume: volume) {
                withAnimation {
                    isWhitelisted = WhitelistManager.shared.isWhitelisted(volume: volume)
                }
            }
        }

        .padding()
        .background(
            RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                .fill(themeManager.currentTheme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                        .stroke(themeManager.currentTheme.secondaryText.opacity(0.2), lineWidth: 1)
                )
                .shadow(
                    color: themeManager.currentTheme.primary.opacity(0.1),
                    radius: themeManager.currentTheme.shadowRadius,
                    x: 0, y: 1
                )
        )
    }
    
    // Helper methods for formatting
    private func shortenPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count <= 3 {
            return path
        }
        
        let volumeName = volumeState.volume.name
        let lastComponents = components.suffix(2)
        return "\(volumeName)/…/\(lastComponents.joined(separator: "/"))"
    }
    
    private func formatDuration(from start: Date, to end: Date) -> String {
        let duration = end.timeIntervalSince(start)
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            return "\(seconds / 60)m \(seconds % 60)s"
        }
    }
    
    private func formatTimeRemaining(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    private func formatElapsedTime(since startTime: Date) -> String {
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
