import Foundation
import Combine

enum IconStyle: String, Codable, CaseIterable {
    case lock = "lock"
    case lockShield = "lockShield"
    case handRaised = "handRaised"
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let keyboardShortcut = "keyboardShortcut"
        static let iconStyle = "iconStyle"
        static let launchAtLogin = "launchAtLogin"
        static let confirmationSound = "confirmationSound"
    }
    
    @Published var keyboardShortcut: SavedKeyboardShortcut? {
        didSet {
            if let shortcut = keyboardShortcut {
                if let encoded = try? JSONEncoder().encode(shortcut) {
                    defaults.set(encoded, forKey: Keys.keyboardShortcut)
                }
            } else {
                defaults.removeObject(forKey: Keys.keyboardShortcut)
            }
        }
    }
    
    @Published var iconStyle: IconStyle = .lock {
        didSet {
            defaults.set(iconStyle.rawValue, forKey: Keys.iconStyle)
        }
    }
    
    @Published var launchAtLogin: Bool = false {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }
    
    @Published var confirmationSound: Bool = false {
        didSet {
            defaults.set(confirmationSound, forKey: Keys.confirmationSound)
        }
    }
    
    private init() {
        loadSettings()
    }
    
    private func loadSettings() {
        // Load keyboard shortcut
        if let data = defaults.data(forKey: Keys.keyboardShortcut),
           let shortcut = try? JSONDecoder().decode(SavedKeyboardShortcut.self, from: data) {
            keyboardShortcut = shortcut
        }
        
        // Load icon style
        if let styleString = defaults.string(forKey: Keys.iconStyle),
           let style = IconStyle(rawValue: styleString) {
            iconStyle = style
        }
        
        // Load launch at login
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        
        // Load confirmation sound
        confirmationSound = defaults.bool(forKey: Keys.confirmationSound)
    }
    
    func resetToDefaults() {
        keyboardShortcut = nil
        iconStyle = .lock
        launchAtLogin = false
        confirmationSound = false
    }
}
