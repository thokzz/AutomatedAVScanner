import SwiftUI

@main
struct DriveScannerApp: App {
    // Add AppDelegate to your existing app structure
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
