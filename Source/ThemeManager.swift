import SwiftUI

// Define the structure for a theme
struct AppTheme: Equatable, Identifiable {
    var id: String
    var name: String
    
    // Colors
    var primary: Color
    var secondary: Color
    var background: Color
    var secondaryBackground: Color
    var text: Color
    var secondaryText: Color
    var accent: Color
    var success: Color
    var warning: Color
    var error: Color
    
    // Status-specific colors
    var scanningColor: Color
    var completedColor: Color
    var infectedColor: Color
    var queuedColor: Color
    var waitingColor: Color
    
    // Other theme properties
    var cornerRadius: CGFloat
    var shadowRadius: CGFloat
}

// Theme manager to handle theme switching
class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme
    @Published var availableThemes: [AppTheme]
    
    // Key for storing the selected theme ID in UserDefaults
    private let themeKey = "selectedThemeId"
    
    init() {
        // 1. Netflix Theme
        let netflixTheme = AppTheme(
            id: "netflix",
            name: "Netflix Theme",
            primary: Color.red,
            secondary: Color.red.opacity(0.7),
            background: Color.black,
            secondaryBackground: Color(red: 0.1, green: 0.1, blue: 0.1),
            text: Color.white,
            secondaryText: Color.gray,
            accent: Color.red,
            success: Color.green,
            warning: Color.yellow,
            error: Color.red,
            scanningColor: Color.red,
            completedColor: Color.green,
            infectedColor: Color.red,
            queuedColor: Color.orange,
            waitingColor: Color.yellow,
            cornerRadius: 10,
            shadowRadius: 4
        )

        // 2. Spotify Theme
        let spotifyTheme = AppTheme(
            id: "spotify",
            name: "Spotify Theme",
            primary: Color(red: 30/255, green: 215/255, blue: 96/255),
            secondary: Color(red: 30/255, green: 215/255, blue: 96/255).opacity(0.7),
            background: Color(red: 18/255, green: 18/255, blue: 18/255),
            secondaryBackground: Color(red: 24/255, green: 24/255, blue: 24/255),
            text: Color.white,
            secondaryText: Color.gray,
            accent: Color(red: 30/255, green: 215/255, blue: 96/255),
            success: Color.green,
            warning: Color.yellow,
            error: Color.red,
            scanningColor: Color(red: 30/255, green: 215/255, blue: 96/255),
            completedColor: Color.green,
            infectedColor: Color.red,
            queuedColor: Color.orange,
            waitingColor: Color.yellow,
            cornerRadius: 12,
            shadowRadius: 3
        )

        // 3. Ubuntu Black Theme
        let ubuntuTheme = AppTheme(
            id: "ubuntu",
            name: "Ubuntu Black Theme",
            primary: Color(red: 221/255, green: 72/255, blue: 20/255),
            secondary: Color(red: 221/255, green: 72/255, blue: 20/255).opacity(0.7),
            background: Color.black,
            secondaryBackground: Color(red: 0.12, green: 0.12, blue: 0.12),
            text: Color.white,
            secondaryText: Color.gray,
            accent: Color(red: 221/255, green: 72/255, blue: 20/255),
            success: Color.green,
            warning: Color.yellow,
            error: Color.red,
            scanningColor: Color.orange,
            completedColor: Color.green,
            infectedColor: Color.red,
            queuedColor: Color.purple,
            waitingColor: Color.yellow,
            cornerRadius: 10,
            shadowRadius: 4
        )

        // 4. Black Theme
        let blackTheme = AppTheme(
            id: "black",
            name: "Black Theme",
            primary: Color.white,
            secondary: Color.gray,
            background: Color.black,
            secondaryBackground: Color(red: 0.1, green: 0.1, blue: 0.1),
            text: Color.white,
            secondaryText: Color.gray,
            accent: Color.white,
            success: Color.green,
            warning: Color.yellow,
            error: Color.red,
            scanningColor: Color.white,
            completedColor: Color.green,
            infectedColor: Color.red,
            queuedColor: Color.orange,
            waitingColor: Color.yellow,
            cornerRadius: 10,
            shadowRadius: 3
        )
        
        let monokaiTheme = AppTheme(
            id: "monokai",
            name: "Monokai Pro",
            primary: Color(red: 249/255, green: 38/255, blue: 114/255),
            secondary: Color(red: 166/255, green: 226/255, blue: 46/255),
            background: Color(red: 39/255, green: 40/255, blue: 34/255),
            secondaryBackground: Color(red: 50/255, green: 51/255, blue: 45/255),
            text: Color.white,
            secondaryText: Color.gray,
            accent: Color(red: 102/255, green: 217/255, blue: 239/255),
            success: Color.green,
            warning: Color.yellow,
            error: Color.red,
            scanningColor: Color.orange,
            completedColor: Color.green,
            infectedColor: Color.red,
            queuedColor: Color.purple,
            waitingColor: Color.yellow,
            cornerRadius: 10,
            shadowRadius: 4
        )
        
        let tokyonightTheme = AppTheme(
            id: "tokyonight",
            name: "Tokyo Night",
            primary: Color(red: 94/255, green: 129/255, blue: 172/255),
            secondary: Color(red: 198/255, green: 160/255, blue: 246/255),
            background: Color(red: 24/255, green: 25/255, blue: 38/255),
            secondaryBackground: Color(red: 30/255, green: 32/255, blue: 48/255),
            text: Color.white,
            secondaryText: Color.gray,
            accent: Color(red: 198/255, green: 160/255, blue: 246/255),
            success: Color.green,
            warning: Color.yellow,
            error: Color(red: 255/255, green: 85/255, blue: 85/255),
            scanningColor: Color.purple,
            completedColor: Color.green,
            infectedColor: Color.red,
            queuedColor: Color.cyan,
            waitingColor: Color.yellow,
            cornerRadius: 10,
            shadowRadius: 4
        )

        let matrixTheme = AppTheme(
            id: "matrix",
            name: "Matrix",
            primary: Color.green,
            secondary: Color.green.opacity(0.7),
            background: Color.black,
            secondaryBackground: Color(red: 0.1, green: 0.1, blue: 0.1),
            text: Color.green,
            secondaryText: Color.green.opacity(0.6),
            accent: Color.green,
            success: Color.green,
            warning: Color.yellow,
            error: Color.red,
            scanningColor: Color.green,
            completedColor: Color.green,
            infectedColor: Color.red,
            queuedColor: Color.orange,
            waitingColor: Color.yellow,
            cornerRadius: 0,
            shadowRadius: 1
        )

        let draculaTheme = AppTheme(
            id: "dracula",
            name: "Dracula",
            primary: Color.purple,
            secondary: Color.purple.opacity(0.7),
            background: Color(red: 40/255, green: 42/255, blue: 54/255),
            secondaryBackground: Color(red: 68/255, green: 71/255, blue: 90/255),
            text: Color.white,
            secondaryText: Color.gray,
            accent: Color(red: 189/255, green: 147/255, blue: 249/255),
            success: Color.green,
            warning: Color.yellow,
            error: Color.red,
            scanningColor: Color.purple,
            completedColor: Color.green,
            infectedColor: Color.red,
            queuedColor: Color.cyan,
            waitingColor: Color.orange,
            cornerRadius: 12,
            shadowRadius: 3
        )

        let nordTheme = AppTheme(
            id: "nord",
            name: "Nord",
            primary: Color(red: 136/255, green: 192/255, blue: 208/255),
            secondary: Color(red: 129/255, green: 161/255, blue: 193/255),
            background: Color(red: 46/255, green: 52/255, blue: 64/255),
            secondaryBackground: Color(red: 59/255, green: 66/255, blue: 82/255),
            text: Color.white,
            secondaryText: Color.gray,
            accent: Color(red: 94/255, green: 129/255, blue: 172/255),
            success: Color.green,
            warning: Color.yellow,
            error: Color.red,
            scanningColor: Color.cyan,
            completedColor: Color.green,
            infectedColor: Color.red,
            queuedColor: Color.purple,
            waitingColor: Color.orange,
            cornerRadius: 10,
            shadowRadius: 2
        )

            let cyberpunkTheme = AppTheme(
            id: "cyberpunk",
            name: "Cyberpunk 2077",
            primary: Color.yellow,
            secondary: Color.pink,
            background: Color.black,
            secondaryBackground: Color(red: 25/255, green: 25/255, blue: 25/255),
            text: Color(red: 255/255, green: 255/255, blue: 153/255),
            secondaryText: Color.pink,
            accent: Color.yellow,
            success: Color.green,
            warning: Color.orange,
            error: Color.red,
            scanningColor: Color.pink,
            completedColor: Color.green,
            infectedColor: Color.red,
            queuedColor: Color.purple,
            waitingColor: Color.yellow,
            cornerRadius: 10,
            shadowRadius: 5
        )

        // Store themes
        let themes = [netflixTheme, spotifyTheme, ubuntuTheme, blackTheme, monokaiTheme, tokyonightTheme, matrixTheme, draculaTheme, nordTheme, cyberpunkTheme]

        if let savedThemeId = UserDefaults.standard.string(forKey: themeKey),
           let savedTheme = themes.first(where: { $0.id == savedThemeId }) {
            self.currentTheme = savedTheme
        } else {
            self.currentTheme = netflixTheme
        }

        self.availableThemes = themes
    }
    
    func setTheme(_ theme: AppTheme) {
        self.currentTheme = theme
        UserDefaults.standard.set(theme.id, forKey: themeKey)
    }
    
    // Helper function to get the color for a scan status
    func colorForStatus(_ status: ScanStatus) -> Color {
        switch status {
        case .scanning, .counting:
            return currentTheme.scanningColor
        case .completed, .clean:
            return currentTheme.completedColor
        case .infected, .error:
            return currentTheme.infectedColor
        case .queued, .waiting:
            return currentTheme.waitingColor
        }
    }
    
    // Helper function for icon for a scan status
    func iconForStatus(_ status: ScanStatus) -> String {
        switch status {
        case .queued:
            return "clock"
        case .counting:
            return "number"
        case .scanning:
            return "doc.text.magnifyingglass"
        case .completed, .clean:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .infected:
            return "exclamationmark.shield.fill"
        case .waiting:
            return "hourglass"
        }
    }
}
