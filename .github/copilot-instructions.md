# PanicLock - Copilot Instructions

## Project Overview
PanicLock is a macOS menu bar utility that instantly disables Touch ID and locks the screen with a single click or keyboard shortcut.

## Architecture
- **Main App**: SwiftUI menu bar app (LSUIElement = true, no dock icon)
- **Privileged Helper**: XPC service for bioutil commands requiring elevated privileges
- **Distribution**: Direct download, Developer ID signed, Apple notarized

## Key Components
- `PanicLockApp.swift` - App entry point, menu bar setup
- `MenuBarController.swift` - Menu bar icon and click handling
- `PanicLockManager.swift` - Core panic lock sequence logic
- `PreferencesView.swift` - Settings UI
- `KeyboardShortcutManager.swift` - Global hotkey registration
- `XPCService/` - Privileged helper for bioutil access

## Panic Sequence
1. Read current Touch ID timeout: `bioutil -r -s`
2. Cache the timeout value
3. Set timeout to 1 second: `bioutil -w -s -o 1`
4. Lock screen: `pmset displaysleepnow`
5. Wait ~2 seconds
6. Restore original timeout: `bioutil -w -s -o {cached_value}`

## Default Values
- Fallback timeout: 172800 seconds (48 hours - Apple's default)
- Menu bar icon: Monochrome lock symbol

## Build & Run
- Xcode 15+ required
- macOS 14.0+ deployment target
- Requires code signing for privileged helper installation
