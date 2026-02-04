import SwiftUI
import Carbon

struct PreferencesView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var isRecordingShortcut = false
    @State private var recordedShortcut: KeyboardShortcut?
    
    var body: some View {
        Form {
            Section("Keyboard Shortcut") {
                HStack {
                    Text("Global Shortcut:")
                    Spacer()
                    ShortcutRecorderView(
                        shortcut: $settings.keyboardShortcut,
                        isRecording: $isRecordingShortcut
                    )
                }
                
                if settings.keyboardShortcut != nil {
                    Button("Clear Shortcut") {
                        settings.keyboardShortcut = nil
                        KeyboardShortcutManager.shared.setupGlobalShortcut()
                    }
                    .foregroundColor(.red)
                }
            }
            
            Section("Appearance") {
                Picker("Menu Bar Icon:", selection: $settings.iconStyle) {
                    Text("Lock").tag(IconStyle.lock)
                    Text("Logo").tag(IconStyle.logo)
                    Text("Shield").tag(IconStyle.shield)
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.iconStyle) { _, _ in
                    NotificationCenter.default.post(name: .iconStyleDidChange, object: nil)
                }
            }
            
            Section("Behavior") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: newValue)
                    }
                
                Toggle("Play Confirmation Sound", isOn: $settings.confirmationSound)
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(.secondary)
                }
                
                Link("View on GitHub", destination: URL(string: "https://github.com/paniclock/paniclock")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 350)
        .padding()
    }
}

struct ShortcutRecorderView: View {
    @Binding var shortcut: SavedKeyboardShortcut?
    @Binding var isRecording: Bool
    
    var body: some View {
        Button(action: {
            isRecording.toggle()
        }) {
            if isRecording {
                Text("Press shortcut...")
                    .foregroundColor(.blue)
            } else if let shortcut = shortcut {
                Text(shortcut.displayString)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            } else {
                Text("Click to record")
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            setupKeyMonitor()
        }
    }
    
    private func setupKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else { return event }
            
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            // Require at least one modifier
            guard !modifiers.isEmpty else { return event }
            
            // Ignore modifier-only presses
            guard event.keyCode != 0 else { return event }
            
            shortcut = SavedKeyboardShortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: UInt32(modifiers.rawValue)
            )
            
            isRecording = false
            KeyboardShortcutManager.shared.setupGlobalShortcut()
            
            return nil
        }
    }
}

struct SavedKeyboardShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    
    var displayString: String {
        var result = ""
        
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        
        // Convert key code to string
        if let keyString = keyCodeToString(keyCode) {
            result += keyString
        }
        
        return result
    }
    
    private func keyCodeToString(_ keyCode: UInt32) -> String? {
        let keyCodeMap: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
            51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 118: "F4", 119: "F2",
            120: "F1", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        
        return keyCodeMap[keyCode] ?? "?"
    }
}

#Preview {
    PreferencesView()
}
