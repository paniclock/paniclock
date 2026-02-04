import AppKit
import SwiftUI

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var preferencesWindow: NSWindow?
    private var aboutWindow: NSWindow?
    
    override init() {
        super.init()
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            updateIcon()
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Observe icon style changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateIcon),
            name: .iconStyleDidChange,
            object: nil
        )
    }
    
    @objc func updateIcon() {
        guard let button = statusItem.button else { return }
        
        let iconStyle = SettingsManager.shared.iconStyle
        
        // Use custom asset for the logo icon
        if iconStyle == .logo {
            if let image = NSImage(named: "StatusIcon") {
                image.size = NSSize(width: 18, height: 18)  // Standard menu bar size
                button.image = image
            }
        } else {
            // Use SF Symbols for other icon options
            let symbolName: String
            
            switch iconStyle {
            case .lock:
                symbolName = "lock.fill"
            case .shield:
                symbolName = "lock.shield.fill"
            case .logo:
                return  // Already handled above
            }
            
            // Use 14pt and let SF Symbols size naturally for menu bar
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "PanicLock")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
        }
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        // Right-click OR Control+click shows the menu
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            triggerPanicLock()
        }
    }
    
    private func showMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Trigger Panic Lock", action: #selector(triggerPanicLock), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About PanicLock", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Uninstall PanicLock...", action: #selector(uninstallHelper), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        for item in menu.items {
            item.target = self
        }
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    
    @objc func triggerPanicLock() {
        PanicLockManager.shared.executePanicLock()
    }
    
    @objc private func openPreferences() {
        if preferencesWindow == nil {
            let preferencesView = PreferencesView()
            preferencesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            preferencesWindow?.title = "PanicLock Preferences"
            preferencesWindow?.contentView = NSHostingView(rootView: preferencesView)
            preferencesWindow?.center()
            preferencesWindow?.isReleasedWhenClosed = false
        }
        
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func showAbout() {
        if aboutWindow == nil {
            let aboutView = AboutView()
            aboutWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 340),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            aboutWindow?.title = "About PanicLock"
            aboutWindow?.contentView = NSHostingView(rootView: aboutView)
            aboutWindow?.center()
            aboutWindow?.isReleasedWhenClosed = false
        }
        
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func uninstallHelper() {
        let alert = NSAlert()
        alert.messageText = "Uninstall PanicLock?"
        alert.informativeText = "This will remove the PanicLock app and its privileged helper tool. You'll need to enter your admin password."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            PanicLockManager.shared.uninstallApp { success, error in
                DispatchQueue.main.async {
                    if success {
                        // Quit the app after successful uninstall
                        NSApp.terminate(nil)
                    } else {
                        let resultAlert = NSAlert()
                        resultAlert.messageText = "Uninstall Failed"
                        resultAlert.informativeText = error ?? "Unknown error occurred."
                        resultAlert.alertStyle = .critical
                        resultAlert.runModal()
                    }
                }
            }
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let iconStyleDidChange = Notification.Name("iconStyleDidChange")
}
