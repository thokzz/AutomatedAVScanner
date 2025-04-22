import SwiftUI

struct MiniDiskUtilityView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Warning header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(themeManager.currentTheme.warning)
                
                Text("Do not remove drives visible in this panel")
                    .font(.headline)
                    .foregroundColor(themeManager.currentTheme.text)
            }
            .padding(.bottom, 8)
            
            if coordinator.connectedVolumes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                    
                    Text("No active volumes")
                        .font(.subheadline)
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                        
                    Text("Connect a drive to begin scanning")
                        .font(.caption)
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(coordinator.connectedVolumes) { volume in
                            let key = "\(volume.volumeUUID)-\(volume.name)"
                            if let state = coordinator.volumeStates[key] {
                                MiniVolumeStatusView(
                                    volumeState: state,
                                    themeManager: themeManager
                                )
                            }
                        }
                    }
                }
            }
            
            Divider()
                .background(themeManager.currentTheme.secondaryText.opacity(0.2))
                .padding(.vertical, 8)
            
            // Recent Transactions Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Previous transactions:")
                    .font(.headline)
                    .foregroundColor(themeManager.currentTheme.text)
                
                if coordinator.transactionManager.transactions.isEmpty {
                    Text("No transaction history yet")
                        .font(.caption)
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(coordinator.transactionManager.transactions.prefix(5)) { transaction in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(transaction.volumeName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(themeManager.currentTheme.text)
                                        .lineLimit(1)
                                    
                                    HStack {
                                        Image(systemName: transaction.isInfected ? "exclamationmark.shield.fill" : "checkmark.circle.fill")
                                            .foregroundColor(transaction.isInfected ? themeManager.currentTheme.error : themeManager.currentTheme.success)
                                            .font(.caption)
                                        
                                        Text(transaction.isInfected ? "Infected" : "Clean")
                                            .font(.caption)
                                            .foregroundColor(transaction.isInfected ? themeManager.currentTheme.error : themeManager.currentTheme.success)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                                    .fill(themeManager.currentTheme.secondaryBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                                    .stroke(themeManager.currentTheme.secondaryText.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 280, maxWidth: 330)
        .background(themeManager.currentTheme.background)
    }
}

struct MiniVolumeStatusView: View {
    @ObservedObject var volumeState: VolumeScanState
    @ObservedObject var themeManager: ThemeManager
    @State private var isAnimating = false
    
    // Custom status icons specifically for mini view
    private func miniIconForStatus(_ status: ScanStatus) -> String {
        switch status {
        case .queued:
            return "timer"
        case .counting:
            return "list.bullet.clipboard"
        case .scanning:
            return "antenna.radiowaves.left.and.right"
        case .completed, .clean:
            return "shield.checkmark.fill"
        case .error:
            return "xmark.octagon.fill"
        case .infected:
            return "CustomBiohazard"
        case .waiting:
            return "clock.arrow.circlepath"
        }
    }
    
    // Get a more descriptive status text for mini view
    private func miniStatusText(_ status: ScanStatus) -> String {
        switch status {
        case .queued:
            return "Waiting"
        case .counting:
            return "Analyzing"
        case .scanning:
            return "Scanning"
        case .completed, .clean:
            return "Clean"
        case .error:
            return "Error"
        case .infected:
            return "⚠️ Infected"
        case .waiting:
            return "Finalizing"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Volume name and status with enhanced styling
            HStack {
                Image(systemName: "externaldrive.fill")
                    .foregroundColor(themeManager.currentTheme.primary)
                
                Text(volumeState.volume.name)
                    .font(.headline)
                    .foregroundColor(themeManager.currentTheme.text)
                    .lineLimit(1)
                
                Spacer()
                
                // Enhanced status indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeManager.colorForStatus(volumeState.scanStatus).opacity(0.2))
                        .frame(height: 24)
                    
                    HStack(spacing: 4) {
                        // Animated icon for active states
                        if volumeState.scanStatus == .scanning || volumeState.scanStatus == .counting {
                            Image(systemName: miniIconForStatus(volumeState.scanStatus))
                                .foregroundColor(themeManager.colorForStatus(volumeState.scanStatus))
                                .font(.system(size: 10, weight: .semibold))
                                .opacity(isAnimating ? 0.6 : 1.0)
                                .animation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
                                .onAppear {
                                    isAnimating = true
                                }
                        } else {
                            Image(systemName: miniIconForStatus(volumeState.scanStatus))
                                .foregroundColor(themeManager.colorForStatus(volumeState.scanStatus))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        
                        Text(miniStatusText(volumeState.scanStatus))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(themeManager.colorForStatus(volumeState.scanStatus))
                    }
                    .padding(.horizontal, 8)
                }
            }
            
            // Volume path
            Text(volumeState.volume.path.path)
                .font(.caption2)
                .foregroundColor(themeManager.currentTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 4)
            
            // Progress indicator for scanning states
            if volumeState.scanStatus == .scanning || volumeState.scanStatus == .counting {
                VStack(spacing: 2) {
                    // Fancy progress bar with gradient
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 2)
                                .fill(themeManager.currentTheme.secondaryBackground)
                                .frame(height: 4)
                            
                            // Progress bar with gradient
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [themeManager.colorForStatus(volumeState.scanStatus).opacity(0.6), themeManager.colorForStatus(volumeState.scanStatus)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(geometry.size.width * volumeState.scanProgress, 0), height: 4)
                            
                            // Animated "pulse" at the end of progress bar
                            if volumeState.scanProgress > 0.05 && volumeState.scanProgress < 0.99 {
                                Circle()
                                    .fill(themeManager.colorForStatus(volumeState.scanStatus))
                                    .frame(width: 6, height: 6)
                                    .opacity(isAnimating ? 0.6 : 1.0)
                                    .offset(x: (geometry.size.width * volumeState.scanProgress) - 3)
                            }
                        }
                    }
                    .frame(height: 4)
                    
                    // Show file count
                    HStack {
                        Text("\(volumeState.scannedFiles) of \(volumeState.fileCount) files")
                            .font(.system(size: 9))
                            .foregroundColor(themeManager.currentTheme.secondaryText)
                        
                        Spacer()
                        
                        Text("\(Int(volumeState.scanProgress * 100))%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(themeManager.colorForStatus(volumeState.scanStatus))
                    }
                    .padding(.top, 2)
                }
                .padding(.top, 2)
            }
            
            // Multi-partition info if relevant
            if volumeState.isPartOfMultiPartitionDrive {
                HStack {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.caption2)
                        .foregroundColor(themeManager.currentTheme.primary)
                    
                    Text("Part of \(volumeState.siblingPartitionCount + 1)-partition drive")
                        .font(.caption2)
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                }
                .padding(.top, 2)
            }
            
            // Infected status if applicable with enhanced styling
            if volumeState.isInfected {
                HStack {
                    Image("CustomBiohazard")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24) // Adjust size as needed
                        .foregroundColor(themeManager.currentTheme.primary)
                    
                    Text("\(volumeState.infectedFiles.count) infected files")
                        .font(.caption)
                        .foregroundColor(themeManager.currentTheme.error)
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(themeManager.currentTheme.error.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(themeManager.currentTheme.error.opacity(0.3), lineWidth: 1)
                )
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                .fill(themeManager.currentTheme.secondaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                .stroke(volumeState.scanStatus == .infected ?
                        themeManager.currentTheme.error.opacity(0.3) :
                        themeManager.currentTheme.secondaryText.opacity(0.2),
                       lineWidth: volumeState.scanStatus == .infected ? 1.5 : 1)
        )
        .shadow(
            color: themeManager.currentTheme.primary.opacity(0.1),
            radius: themeManager.currentTheme.shadowRadius / 2,
            x: 0, y: 1
        )
    }
}

// Preview for design purposes
struct MiniDiskUtilityView_Previews: PreviewProvider {
    static var previews: some View {
        MiniDiskUtilityView(
            coordinator: AppCoordinator(),
            themeManager: ThemeManager()
        )
        .frame(width: 300, height: 500)
    }
}
