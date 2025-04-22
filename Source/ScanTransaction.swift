import Foundation
import SwiftUI

// Model to store a record of each scan transaction
struct ScanTransaction: Identifiable, Codable {
    var id: UUID
    let volumeName: String
    let volumeUUID: String
    let scanStartTime: Date
    let scanEndTime: Date
    var fileCount: Int
    var scannedFiles: Int
    let isInfected: Bool
    let infectedFiles: [String]
    let skippedFiles: Int
    var lastPrintTime: Date?
    // New field to store average files per second for reference
    let avgFilesPerSecond: Double?
    
    init(from state: VolumeScanState) {
        self.id = UUID()
        self.volumeName = state.volume.name
        self.fileCount       = state.fileCount
        self.scannedFiles    = state.scannedFiles
        self.skippedFiles    = state.skippedFiles
        self.volumeUUID = state.volume.volumeUUID
        
        // Ensure we have valid start/end times (default to current time if missing)
        if let startTime = state.scanStartTime {
            self.scanStartTime = startTime
        } else {
            // Only create a default value if missing
            self.scanStartTime = Date().addingTimeInterval(-60) // Default to 1 minute ago
            print("⚠️ Created default scanStartTime for \(state.volume.name)")
        }
        
        if let endTime = state.scanEndTime {
            self.scanEndTime = endTime
        } else {
            // Only create a default value if missing
            self.scanEndTime = Date() // Default to now
            print("⚠️ Created default scanEndTime for \(state.volume.name)")
        }
        
        // Ensure file counts are valid
        if state.fileCount > 0 && state.scannedFiles >= Int(0.95 * Double(state.fileCount)) {
            // Adjust for skipped files (e.g., permissions or hidden files)
            self.fileCount = state.scannedFiles
        } else {
            self.fileCount = max(state.fileCount, state.scannedFiles)
        }
        self.scannedFiles = state.scannedFiles
        
        // Infection status and files
        self.isInfected = state.isInfected
        self.infectedFiles = state.infectedFiles
        
        // Print status
        self.lastPrintTime = state.hasPrinted ? Date() : nil
        
        // Performance metrics
        self.avgFilesPerSecond = state.filesPerSecond > 0 ? state.filesPerSecond : nil
        
        print("📝 Created transaction for \(volumeName) [\(volumeUUID)] with \(scannedFiles)/\(fileCount) files")
    }
    
    init(id: UUID, from state: VolumeScanState) {
        self.id = id
        self.volumeName = state.volume.name
        self.volumeUUID = state.volume.volumeUUID
        self.scanStartTime = state.scanStartTime ?? Date().addingTimeInterval(-60)
        self.scanEndTime = state.scanEndTime ?? Date()
        self.fileCount       = state.fileCount
        self.scannedFiles    = state.scannedFiles
        self.skippedFiles    = state.skippedFiles
        self.isInfected = state.isInfected
        self.infectedFiles = state.infectedFiles
        self.lastPrintTime = state.hasPrinted ? Date() : nil
        self.avgFilesPerSecond = state.filesPerSecond > 0 ? state.filesPerSecond : nil
        
        print("📝 Created transaction with specified ID for \(volumeName) [\(volumeUUID)]")
    }
    
    var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: scanStartTime)
    }
    
    var formattedEndTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: scanEndTime)
    }
    
    var scanDuration: TimeInterval {
        scanEndTime.timeIntervalSince(scanStartTime)
    }
    
    var formattedDuration: String {
        let minutes = Int(scanDuration) / 60
        let seconds = Int(scanDuration) % 60
        return "\(minutes)m \(seconds)s"
    }
    
    var formattedScanRate: String {
        guard let rate = avgFilesPerSecond, rate > 0 else {
            return "Not available"
        }
        return "\(Int(rate)) files/sec"
    }
    
    var formattedLastPrintTime: String {
        guard let printTime = lastPrintTime else { return "Not printed" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: printTime)
    }
}

// Manages scan transactions and history
class TransactionManager: ObservableObject {
    @Published var transactions: [ScanTransaction] = []
    
    private let userDefaultsKey = "scanTransactions"
    
    init() {
        loadTransactions()
    }
    
    func refreshTransactions() {
        loadTransactions()
        // Force UI refresh
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.objectWillChange.send()
        }
    }
    
    func updateTransactionPrintTimeByVolumeUUID(volumeUUID: String) {
        // Load the latest transactions first
        loadTransactions()
        
        // Find the MOST RECENT transaction with this UUID
        if let index = transactions.firstIndex(where: { $0.volumeUUID == volumeUUID }) {
            var transaction = transactions[index]
            transaction.lastPrintTime = Date()
            transactions[index] = transaction
            saveTransactions()
            print("🔄 Updated print time for \(transactions[index].volumeName) [UUID: \(volumeUUID)]")
            
            // Force UI refresh
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }
    
    func addTransaction(from state: VolumeScanState) {
        // ALWAYS create a new transaction - no exceptions or conditions
        let transaction = ScanTransaction(from: state)
        
        print("✅ Added new transaction for \(state.volume.name)")
        transactions.append(transaction)
        saveTransactions()
    }
    
    // FIXED: Modified method to always create a new transaction for each scan
    func addAndSaveTransaction(from state: VolumeScanState) -> UUID {
        // Create a brand new transaction with a unique ID
        let newTransaction = ScanTransaction(from: state)
        
        // Load any existing transactions first to make sure we have the latest
        loadTransactions()
        
        // Add the new transaction to the beginning of the array (most recent first)
        transactions.insert(newTransaction, at: 0)
        
        // Save all transactions including the new one
        do {
            // Sort all transactions by date (newest first)
            transactions.sort { $0.scanEndTime > $1.scanEndTime }
            
            // Take the most recent 100 transactions to avoid excessive storage
            let transactionsToSave = Array(transactions.prefix(100))
            
            // Encode and save to UserDefaults
            let encoded = try JSONEncoder().encode(transactionsToSave)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            UserDefaults.standard.synchronize()
            
            print("✅ Successfully added and saved new transaction for \(state.volume.name)")
            
            // Force UI refresh
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        } catch {
            print("❌ Failed to save transactions: \(error.localizedDescription)")
        }
        
        return newTransaction.id
    }
    
    func updateTransactionPrintTime(id: UUID) {
        if let index = transactions.firstIndex(where: { $0.id == id }) {
            var transaction = transactions[index]
            transaction.lastPrintTime = Date()
            transactions[index] = transaction
            print("🔄 Updated print time for transaction \(id)")
            saveTransactions()
        } else {
            print("⚠️ Could not find transaction with ID \(id) to update print time")
        }
    }
    
    func isAllPrintingCompleted(for driveVolumes: [ExternalVolume]) -> Bool {
        // Get all transactions for the volumes on this drive
        let relevantTransactions = transactions.filter { transaction in
            driveVolumes.contains { volume in
                transaction.volumeUUID == volume.volumeUUID && transaction.volumeName == volume.name
            }
        }
        
        // If no transactions were found or fewer than expected, return false
        if relevantTransactions.isEmpty || relevantTransactions.count < driveVolumes.count {
            return false
        }
        
        // Check if all have been printed
        return relevantTransactions.allSatisfy { $0.lastPrintTime != nil }
    }
    
    private func saveTransactions() {
        // Sort transactions by scan end time, newest first
        var sortedTransactions = transactions
        sortedTransactions.sort { $0.scanEndTime > $1.scanEndTime }
        
        // Take at most 100 transactions to avoid excessive storage
        if sortedTransactions.count > 100 {
            sortedTransactions = Array(sortedTransactions.prefix(100))
        }
        
        print("💾 Saving \(sortedTransactions.count) transactions to UserDefaults")
        
        do {
            let encoded = try JSONEncoder().encode(sortedTransactions)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            UserDefaults.standard.synchronize() // Force synchronize
            print("✅ Successfully saved \(sortedTransactions.count) transactions to UserDefaults")
            
            // Update our local copy with the sorted version
            self.transactions = sortedTransactions
            
            // Force UI refresh
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        } catch {
            print("❌ Failed to save transactions: \(error.localizedDescription)")
        }
    }

    
    func debugTransactions() {
        print("🔍 CURRENT TRANSACTIONS IN MEMORY: \(transactions.count)")
        for (index, transaction) in transactions.enumerated() {
            print("   [\(index)] \(transaction.volumeName) - \(transaction.formattedStartTime)")
        }
        
        if let savedData = UserDefaults.standard.data(forKey: userDefaultsKey),
           let loadedTransactions = try? JSONDecoder().decode([ScanTransaction].self, from: savedData) {
            print("🔍 TRANSACTIONS IN USER DEFAULTS: \(loadedTransactions.count)")
            for (index, transaction) in loadedTransactions.enumerated() {
                print("   [\(index)] \(transaction.volumeName) - \(transaction.formattedStartTime)")
            }
        } else {
            print("🔍 NO TRANSACTIONS IN USER DEFAULTS")
        }
    }
    
    func loadTransactions() {
        if let savedData = UserDefaults.standard.data(forKey: userDefaultsKey) {
            do {
                let loadedTransactions = try JSONDecoder().decode([ScanTransaction].self, from: savedData)
                
                // Sort transactions by date, newest first
                var sortedTransactions = loadedTransactions
                sortedTransactions.sort { $0.scanEndTime > $1.scanEndTime }
                
                transactions = sortedTransactions
                print("📤 Loaded \(transactions.count) transactions from UserDefaults")
                
                // Log each transaction for debugging
                for transaction in transactions {
                    print("📋 Loaded transaction: \(transaction.volumeName) - \(transaction.formattedStartTime)")
                }
                
                // Force UI update
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                }
            } catch {
                print("❌ Failed to load transactions: \(error.localizedDescription)")
            }
        } else {
            print("ℹ️ No saved transactions found")
        }
    }
    
    func forceClearAllTransactions() {
        print("⚠️ Force clearing all transactions")
        transactions.removeAll()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.synchronize()
        
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func clearHistory() {
        transactions.removeAll()
        saveTransactions()
    }

}
