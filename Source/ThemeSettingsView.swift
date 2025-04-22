import SwiftUI

struct ThemeSettingsView: View {
    @ObservedObject var themeManager: ThemeManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Theme Settings")
                .font(.title)
                .padding(.top)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(themeManager.availableThemes) { theme in
                        ThemeOptionRow(
                            theme: theme,
                            isSelected: themeManager.currentTheme.id == theme.id,
                            onSelect: {
                                withAnimation {
                                    themeManager.setTheme(theme)
                                }
                            }
                        )
                    }
                }
                .padding()
            }
            
            Button("Close") {
                presentationMode.wrappedValue.dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .padding(.bottom)
        }
        .frame(width: 400, height: 400)
    }
}

struct ThemeOptionRow: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(theme.name)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(theme.primary)
                        .frame(width: 15, height: 15)
                    
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 15, height: 15)
                    
                    Circle()
                        .fill(theme.success)
                        .frame(width: 15, height: 15)
                    
                    Circle()
                        .fill(theme.error)
                        .frame(width: 15, height: 15)
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(theme.primary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(theme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .stroke(isSelected ? theme.primary : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                )
        )
        .onTapGesture {
            onSelect()
        }
    }
}
