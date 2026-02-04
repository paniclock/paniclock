# PanicLock

<p align="center">
  <img src="assets/paniclock-logo-and-name-v1.png" alt="PanicLock" width="400">
</p>

A macOS menu bar utility that instantly disables Touch ID and locks the screen with a single click.

## Features

- **One-click panic lock** — Left-click the menu bar icon to instantly lock
- **Temporarily disables Touch ID** — Forces password-only unlock
- **Auto-restore** — Original Touch ID settings restored after unlock
- **Keyboard shortcut** — Configure a global hotkey (e.g., ⌃⌥⌘L)
- **Launch at login** — Start automatically when you log in

## Requirements

- macOS 14.0 (Sonoma) or later
- Mac with Touch ID

## Usage

| Action | Result |
|--------|--------|
| **Left-click** icon | Trigger panic lock immediately |
| **Right-click** icon | Open menu (Preferences, Uninstall, Quit) |

### First Launch

On first use, you'll be prompted for your admin password to install the privileged helper. This is a one-time setup.

## Building from Source

1. Clone this repository
2. Open `PanicLock.xcodeproj` in Xcode
3. Set your Development Team in both targets (PanicLock and PanicLockHelper)
4. Update Team ID in `Info.plist` (`SMPrivilegedExecutables`) and `Info-Helper.plist` (`SMAuthorizedClients`)
5. Build and run

## Uninstall

**From the app:** Right-click → "Uninstall PanicLock..." → Enter admin password

**Manual:**
```bash
sudo launchctl bootout system/com.paniclock.helper
sudo rm -f /Library/PrivilegedHelperTools/com.paniclock.helper
sudo rm -f /Library/LaunchDaemons/com.paniclock.helper.plist
rm -rf /Applications/PanicLock.app
```

## How It Works

PanicLock uses a privileged helper (installed via SMJobBless) to modify Touch ID timeout settings:

1. Reads current timeout via `bioutil -r -s`
2. Sets timeout to 1 second via `bioutil -w -s -o 1`
3. Locks screen via `pmset displaysleepnow`
4. Restores original timeout after ~2 seconds

## Security

- **Minimal privileges** — Helper only runs 3 hardcoded commands (`bioutil`, `pmset`)
- **No command injection** — Timeout parameter is a Swift `Int`, not a string
- **Code-signed XPC** — Helper verifies connecting app's bundle ID + team ID + certificate
- **No network activity** — App is 100% offline, no telemetry or analytics
- **No data collection** — Only stores preferences (icon style, keyboard shortcut)
- **Open source** — Full code available for audit

## Releasing

The release script handles building, signing, notarizing, and packaging:

```bash
./scripts/release.sh
```

**Features:**
- Extracts version from Xcode project automatically
- Signs with Developer ID for distribution outside the App Store
- Submits to Apple for notarization (can take minutes to hours)
- Creates a notarized DMG for distribution
- Supports parallel notarizations — each version gets its own `build/release/<version>/` directory

**Workflow:**
1. Bump `MARKETING_VERSION` in Xcode
2. Run `./scripts/release.sh` — builds and submits for notarization
3. Run again later to check status and continue when approved
4. Final output: `build/release/<version>/PanicLock-<version>.dmg`

## License

MIT License — See [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please open an issue or pull request.
