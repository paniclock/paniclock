# PanicLock

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

## License

MIT License — See [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please open an issue or pull request.
