import SwiftUI

@main
struct PanicLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var settingsWindowController: NSWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize menu bar controller
        menuBarController = MenuBarController()
        
        // Setup global keyboard shortcut
        KeyboardShortcutManager.shared.setupGlobalShortcut()
        
        // Install helper if needed
        PanicLockManager.shared.installHelperIfNeeded()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        KeyboardShortcutManager.shared.removeGlobalShortcut()
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
