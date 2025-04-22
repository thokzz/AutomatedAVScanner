import SwiftUI

// An enhanced progress view with animation and additional visual cues
struct AnimatedProgressView: View {
    let progress: Double
    let showIndicator: Bool
    var color: Color = .blue
    var height: CGFloat = 8
    
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: height)
                    .cornerRadius(height / 2)
                
                // Progress bar
                Rectangle()
                    .fill(color)
                    .frame(width: max(geometry.size.width * progress, 0), height: height)
                    .cornerRadius(height / 2)
                
                // Animated scanning indicator that moves along the progress bar
                if showIndicator && progress > 0.02 && progress < 0.98 {
                    Circle()
                        .fill(Color.white)
                        .frame(width: height * 1.2, height: height * 1.2)
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                        .offset(x: (geometry.size.width * progress) - (height / 2))
                        .opacity(isAnimating ? 1.0 : 0.7)
                        .animation(
                            Animation.easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true),
                            value: isAnimating
                        )
                        .onAppear {
                            isAnimating = true
                        }
                }
            }
        }
        .frame(height: height)
    }
}

// A view showing file count progress with visual elements
struct ScanProgressIndicator: View {
    let scannedFiles: Int
    let totalFiles: Int
    let isScanning: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            AnimatedProgressView(
                progress: calculateProgress(),
                showIndicator: isScanning,
                color: isScanning ? .blue : .green,
                height: 8
            )
            
            // Files count and percentage
            HStack {
                Text("\(scannedFiles)/\(totalFiles) files")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(Int(calculateProgress() * 100))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(isScanning ? .blue : .green)
            }
        }
    }
    
    private func calculateProgress() -> Double {
        guard totalFiles > 0 else { return 0.0 }
        return min(1.0, Double(scannedFiles) / Double(totalFiles))
    }
}

// A view that displays estimated scan time
struct ScanTimeEstimateView: View {
    let estimatedTimeRemaining: TimeInterval?
    let scanStartTime: Date?
    
    var body: some View {
        HStack(spacing: 6) {
            // Time icon
            Image(systemName: "clock.fill")
                .font(.caption2)
                .foregroundColor(.blue.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 2) {
                // Remaining time
                if let remaining = estimatedTimeRemaining, let start = scanStartTime {
                    HStack(spacing: 4) {
                        Text("Remaining:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(formatTimeRemaining(remaining))
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    
                    // Elapsed time
                    HStack(spacing: 4) {
                        Text("Elapsed:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(formatElapsedTime(since: start))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if let start = scanStartTime {
                    // Just show elapsed time if we can't estimate remaining
                    HStack(spacing: 4) {
                        Text("Elapsed:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(formatElapsedTime(since: start))
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                } else {
                    Text("Calculating time...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
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
}

// A component to display a list of recently scanned files with animations
struct RecentFilesView: View {
    let files: [String]
    let volumeName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recently scanned files:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(files.prefix(10), id: \.self) { file in
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 8))
                                .foregroundColor(.blue.opacity(0.7))
                            
                            Text(shortenPath(file, volumeName: volumeName))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 2)
                        .transition(.opacity)
                    }
                }
            }
            .frame(maxHeight: 120)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }
    
    private func shortenPath(_ path: String, volumeName: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count <= 3 {
            return path
        }
        
        // Return just the volume name and the last 2 components
        let lastComponents = components.suffix(2)
        return "\(volumeName)/…/\(lastComponents.joined(separator: "/"))"
    }
}

// Preview for design purposes
struct AnimatedProgressView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AnimatedProgressView(progress: 0.35, showIndicator: true)
                .padding()
            
            ScanProgressIndicator(scannedFiles: 1250, totalFiles: 5000, isScanning: true)
                .padding()
            
            ScanTimeEstimateView(
                estimatedTimeRemaining: 145,
                scanStartTime: Date().addingTimeInterval(-60)
            )
            .padding()
            
            RecentFilesView(
                files: [
                    "/Volumes/MyDrive/Documents/file1.pdf",
                    "/Volumes/MyDrive/Documents/nested/file2.doc",
                    "/Volumes/MyDrive/Pictures/image.jpg"
                ],
                volumeName: "MyDrive"
            )
            .padding()
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
