# Changelog

All notable changes to PanicLock will be documented in this file.

## [1.0.2] - 2026-02-04

### Fixed
- DMG is now properly code-signed for smoother installation
- App inside DMG is stapled for offline Gatekeeper verification
- Release script improvements for more reliable builds

### Changed
- Updated copyright string

## [1.0.1] - 2026-02-03

### Fixed
- Improved release script with better state tracking
- Added DMG hash verification for build integrity

## [1.0.0] - 2026-02-01

### Added
- Initial release
- One-click panic lock from menu bar
- Temporarily disables Touch ID (forces password-only unlock)
- Automatic restore of Touch ID settings after unlock
- Keyboard shortcut support (configurable in Preferences)
- Launch at login option
- Confirmation sound option
- Menu bar icon style options (Lock, Shield, Hand)
- Built-in uninstaller
- Privileged helper with secure XPC communication
