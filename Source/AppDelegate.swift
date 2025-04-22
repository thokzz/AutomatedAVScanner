import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🏁 App is running at: \(Bundle.main.bundlePath)") // ← Add here

        // Request accessibility permission
        requestAccessibilityPermission()

        // Request volume permissions on first launch
        requestVolumePermissions()

        // Redirect logs to file (only in release builds)
        #if !DEBUG
        redirectLogsToFile()
        #endif
    }

    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessEnabled {
            print("⚠️ Accessibility permission not granted. Some features may be limited.")
        } else {
            print("✅ Accessibility permission granted.")
        }
    }

    func requestVolumePermissions() {
        let openPanel = NSOpenPanel()
        openPanel.message = "Please select an external drive to grant access for scanning"
        openPanel.prompt = "Select External Drive"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.directoryURL = URL(fileURLWithPath: "/Volumes")

        if openPanel.runModal() == .OK, let url = openPanel.url {
            print("✅ User granted access to: \(url.path)")

            do {
                let bookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmarkData, forKey: "ExternalVolumeBookmark")
                print("✅ Bookmark created successfully")
            } catch {
                print("❌ Failed to create bookmark: \(error.localizedDescription)")
            }
        }
    }

    func redirectLogsToFile() {
        let logPath = FileManager.default.temporaryDirectory.appendingPathComponent("drivescanner_log.txt")
        freopen(logPath.path, "a+", stderr)
        freopen(logPath.path, "a+", stdout)
        print("✅ Log redirection active: \(logPath.path)")
    }
}
