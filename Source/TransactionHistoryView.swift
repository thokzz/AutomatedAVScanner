import SwiftUI

struct TransactionHistoryView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var themeManager: ThemeManager
    @State private var selectedTransaction: ScanTransaction? = nil
    @State private var showingClearAlert = false
    @State private var isPrinting = false
    @State private var isRefreshing = false
    @State private var lastRefreshTime = Date()
    
    private func refreshTransactions() {
        // Prevent rapid refreshes
        let now = Date()
        if now.timeIntervalSince(lastRefreshTime) < 1.0 {
            return
        }
        
        lastRefreshTime = now
        isRefreshing = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            coordinator.transactionManager.refreshTransactions()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isRefreshing = false
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Header
            HStack {
                Text("Scan History")
                    .font(.title2)
                    .bold()
                    .foregroundColor(themeManager.currentTheme.text)
                
                Spacer()
                
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 8)
                        .tint(themeManager.currentTheme.primary)
                }
                
                Button {
                    refreshTransactions()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .foregroundColor(themeManager.currentTheme.accent)
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
                
                Button {
                    showingClearAlert = true
                } label: {
                    Text("Clear History")
                        .foregroundColor(themeManager.currentTheme.error)
                }
                .buttonStyle(.bordered)
                .alert("Clear Scan History", isPresented: $showingClearAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Clear", role: .destructive) {
                        coordinator.transactionManager.clearHistory()
                        refreshTransactions()
                    }
                } message: {
                    Text("This will delete all scan records. This action cannot be undone.")
                }
            }
            .padding()
            .background(themeManager.currentTheme.background)
            
            // Table header
            HStack {
                Text("Drive")
                    .frame(width: 100, alignment: .leading)
                Text("Date")
                    .frame(width: 170, alignment: .leading)
                Text("Files")
                    .frame(width: 100, alignment: .center)
                Text("Status")
                    .frame(width: 100, alignment: .center)
                Text("Actions")
                    .frame(minWidth: 100, alignment: .trailing)
            }
            .font(.caption)
            .foregroundColor(themeManager.currentTheme.secondaryText)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(themeManager.currentTheme.secondaryBackground)
            
            Divider()
                .background(themeManager.currentTheme.secondaryText.opacity(0.2))
            
            if coordinator.transactionManager.transactions.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "externaldrive.badge.clock")
                        .font(.system(size: 48))
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                    Text("No scan history yet")
                        .font(.title3)
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                    Text("Drive scan records will appear here")
                        .font(.subheadline)
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                    Spacer()
                }
                .background(themeManager.currentTheme.background)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(coordinator.transactionManager.transactions.sorted(by: { $0.scanEndTime > $1.scanEndTime })) { transaction in
                            TransactionRowView(
                                transaction: transaction,
                                coordinator: coordinator,
                                themeManager: themeManager,
                                isPrinting: $isPrinting,
                                selectedTransaction: $selectedTransaction
                            )
                            .padding(.vertical, 8)
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .id(transaction.id) // Add this to force SwiftUI to recreate the view when the transaction changes
                            
                            Divider()
                                .background(themeManager.currentTheme.secondaryText.opacity(0.2))
                        }
                    }
                }
                .background(themeManager.currentTheme.background)
            }
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionDetailSheetView(
                transaction: transaction,
                coordinator: coordinator,
                themeManager: themeManager,
                isPrinting: $isPrinting
            )
        }
        .onAppear {
            refreshTransactions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .physicalDriveFullyScanned)) { _ in
            // Refresh when a drive is fully scanned
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                refreshTransactions()
            }
        }
    }
}

// A separate view for each transaction row
struct TransactionRowView: View {
    let transaction: ScanTransaction
    let coordinator: AppCoordinator
    let themeManager: ThemeManager
    @Binding var isPrinting: Bool
    @Binding var selectedTransaction: ScanTransaction?
    @State private var showingPrintAlert = false
    
    var body: some View {
        HStack {
            // Drive name
            Text(transaction.volumeName)
                .fontWeight(.medium)
                .foregroundColor(themeManager.currentTheme.text)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
            
            // Date and time with enhanced information
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.formattedStartTime)
                    .font(.subheadline)
                    .foregroundColor(themeManager.currentTheme.text)
                HStack(spacing: 4) {
                    Text("Duration: \(transaction.formattedDuration)")
                        .font(.caption)
                    
                    // Add scan rate if available
                    if transaction.avgFilesPerSecond != nil && transaction.avgFilesPerSecond! > 0 {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(themeManager.currentTheme.secondaryText)
                        Text("\(Int(transaction.avgFilesPerSecond!)) files/sec")
                            .font(.caption)
                    }
                }
                .foregroundColor(themeManager.currentTheme.secondaryText)
            }
            .frame(width: 170, alignment: .leading)
            
            // File count with completion percentage
            VStack(alignment: .center, spacing: 2) {
                Text("\(transaction.scannedFiles)")
                    .font(.caption)
                    .foregroundColor(themeManager.currentTheme.secondaryText)
            }
            .frame(width: 100, alignment: .center)
            
            // Status with improved visual indicator
            HStack(spacing: 4) {
                Image(systemName: transaction.isInfected ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(transaction.isInfected ? themeManager.currentTheme.error : themeManager.currentTheme.success)
                Text(transaction.isInfected ? "Infected" : "Clean")
                    .foregroundColor(transaction.isInfected ? themeManager.currentTheme.error : themeManager.currentTheme.success)
            }
            .frame(width: 100, alignment: .center)
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                Button {
                    selectedTransaction = transaction
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(themeManager.currentTheme.accent)
                }
                .buttonStyle(.borderless)
                .help("View details")
                
                Button {
                    showingPrintAlert = true
                } label: {
                    Image(systemName: "printer")
                        .foregroundColor(themeManager.currentTheme.accent)
                }
                .buttonStyle(.borderless)
                .disabled(isPrinting)
                .help("Print report")
            }
            .frame(minWidth: 100, alignment: .trailing)
        }
        .alert("Print Scan Report", isPresented: $showingPrintAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Print") {
                Task {
                    isPrinting = true
                    _ = await coordinator.printTransaction(transaction)
                    isPrinting = false
                }
            }
        } message: {
            Text("Do you want to print the scan report for \(transaction.volumeName)?")
        }
    }
}

// A separate view for the transaction detail sheet
struct TransactionDetailSheetView: View {
    let transaction: ScanTransaction
    let coordinator: AppCoordinator
    let themeManager: ThemeManager
    @Binding var isPrinting: Bool
    @State private var showingPrintAlert = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            // Custom Title Bar with Close Button
            HStack {
                Text("Scan Details: \(transaction.volumeName)")
                    .font(.headline)
                    .foregroundColor(themeManager.currentTheme.text)
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .foregroundColor(themeManager.currentTheme.accent)
            }
            .padding()
            .background(themeManager.currentTheme.background)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header section with improved visual representation
                    Group {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(transaction.volumeName)
                                    .font(.title)
                                    .bold()
                                    .foregroundColor(themeManager.currentTheme.text)
                                
                                HStack {
                                    Text(transaction.isInfected ? "⚠️ Infected" : "✅ Clean")
                                        .font(.title3)
                                        .foregroundColor(transaction.isInfected ? themeManager.currentTheme.error : themeManager.currentTheme.success)
                                    
                                    // Add visual completion badge
//                                    if transaction.scannedFiles < transaction.fileCount {
//                                        Text("(\(calculateProgress())% Complete)")
//                                            .font(.subheadline)
//                                            .foregroundColor(themeManager.currentTheme.warning)
//                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Button {
                                showingPrintAlert = true
                            } label: {
                                Label("Print", systemImage: "printer")
                                    .foregroundColor(themeManager.currentTheme.accent)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isPrinting)
                        }
                        
                        Divider()
                            .background(themeManager.currentTheme.secondaryText.opacity(0.2))
                    }
                    
                    // Scan Performance Summary
                    Group {
                        Text("Scan Performance")
                            .font(.headline)
                            .foregroundColor(themeManager.currentTheme.text)
                        
                        HStack(spacing: 20) {
                            // Scan Duration
                            VStack {
                                Text(transaction.formattedDuration)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(themeManager.currentTheme.text)
                                Text("Duration")
                                    .font(.caption)
                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            
                            // Files Processed
                            VStack {
                                Text("\(transaction.scannedFiles)")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(themeManager.currentTheme.text)
                                Text("Files Scanned")
                                    .font(.caption)
                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            
                            // Scan Rate
                            VStack {
                                Text(transaction.formattedScanRate)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(themeManager.currentTheme.text)
                                Text("Scan Rate")
                                    .font(.caption)
                                    .foregroundColor(themeManager.currentTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .background(themeManager.currentTheme.primary.opacity(0.1))
                        .cornerRadius(themeManager.currentTheme.cornerRadius)
                        
                        Divider()
                            .background(themeManager.currentTheme.secondaryText.opacity(0.2))
                    }
                    
                    // Scan details
                    Group {
                        Text("Scan Details")
                            .font(.headline)
                            .foregroundColor(themeManager.currentTheme.text)
                        
                        DetailRowView(label: "Start Time", value: transaction.formattedStartTime, themeManager: themeManager)
                        DetailRowView(label: "End Time", value: transaction.formattedEndTime, themeManager: themeManager)
                        DetailRowView(label: "Duration", value: transaction.formattedDuration, themeManager: themeManager)
                        DetailRowView(label: "Total Files", value: "\(transaction.fileCount)", themeManager: themeManager)
                        DetailRowView(label: "Scanned Files", value: "\(transaction.scannedFiles)", themeManager: themeManager)
                        DetailRowView(label: "Skipped Files", value: "\(transaction.skippedFiles)", themeManager: themeManager)
                        DetailRowView(label: "Last Printed", value: transaction.formattedLastPrintTime, themeManager: themeManager)
                        
                        Divider()
                            .background(themeManager.currentTheme.secondaryText.opacity(0.2))
                    }
                    
                    // Infected files (if any)
                    if transaction.isInfected {
                        Group {
                            Text("Infected Files")
                                .font(.headline)
                                .foregroundColor(themeManager.currentTheme.text)
                            
                            Text("\(transaction.infectedFiles.count) infected files found")
                                .font(.subheadline)
                                .foregroundColor(themeManager.currentTheme.error)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(transaction.infectedFiles, id: \.self) { file in
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(themeManager.currentTheme.error)
                                        Text(file)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(themeManager.currentTheme.error)
                                    }
                                }
                            }
                            .padding()
                            .background(themeManager.currentTheme.error.opacity(0.1))
                            .cornerRadius(themeManager.currentTheme.cornerRadius)
                        }
                    }
                }
                .padding()
            }
            .background(themeManager.currentTheme.background)
            .alert("Print Scan Report", isPresented: $showingPrintAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Print") {
                    Task {
                        isPrinting = true
                        _ = await coordinator.printTransaction(transaction)
                        isPrinting = false
                    }
                }
            } message: {
                Text("Do you want to print the scan report for \(transaction.volumeName)?")
            }
        }
        .frame(width: 600, height: 500)
        .background(themeManager.currentTheme.background)
    }
    
    // Add this method to fix the compiler error
    private func calculateProgress() -> Int {
        guard transaction.fileCount > 0 else { return 100 }
        let progress = Double(transaction.scannedFiles) / Double(transaction.fileCount)
        return min(100, Int(progress * 100))
    }
}

// A helper view for detail rows
struct DetailRowView: View {
    let label: String
    let value: String
    let themeManager: ThemeManager
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(themeManager.currentTheme.secondaryText)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(themeManager.currentTheme.text)
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// Preview for design purposes
#Preview {
    TransactionHistoryView(
        coordinator: AppCoordinator(),
        themeManager: ThemeManager()
    )
}
