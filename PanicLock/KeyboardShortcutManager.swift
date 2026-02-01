import Foundation
import AppKit
import Carbon

class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()
    
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x504C4B00), id: 1) // "PLK\0"
    
    private init() {}
    
    func setupGlobalShortcut() {
        // Remove existing shortcut first
        removeGlobalShortcut()
        
        guard let shortcut = SettingsManager.shared.keyboardShortcut else {
            return
        }
        
        // Convert NSEvent modifier flags to Carbon modifier flags
        let carbonModifiers = convertToCarbonModifiers(shortcut.modifiers)
        
        // Register hot key
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        guard status == noErr else {
            print("Failed to register hot key: \(status)")
            return
        }
        
        self.hotKeyRef = hotKeyRef
        
        // Install event handler
        installEventHandler()
    }
    
    func removeGlobalShortcut() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
    
    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            guard status == noErr else { return status }
            
            // Trigger panic lock on main thread
            DispatchQueue.main.async {
                PanicLockManager.shared.executePanicLock()
            }
            
            return noErr
        }
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }
    
    private func convertToCarbonModifiers(_ cocoaModifiers: UInt32) -> UInt32 {
        var carbonModifiers: UInt32 = 0
        let flags = NSEvent.ModifierFlags(rawValue: UInt(cocoaModifiers))
        
        if flags.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        
        return carbonModifiers
    }
}
