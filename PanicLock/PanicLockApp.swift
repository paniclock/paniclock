import SwiftUI
import Combine

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
    private let powerMonitor = PowerMonitor()
    private let screenUnlockObserver = ScreenUnlockObserver()
    private let stateMachine = LockStateMachine()
    private var cancellables = Set<AnyCancellable>()
    private var pendingSleepToken: PowerMonitor.SleepToken?
    private var sleepTimeoutWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize menu bar controller
        menuBarController = MenuBarController()

        // Setup global keyboard shortcut
        KeyboardShortcutManager.shared.setupGlobalShortcut()

        // Sync launch-at-login: if user setting is enabled but system registration is not, register now
        // This handles first launch (default is true) and cases where system state was reset
        if SettingsManager.shared.launchAtLogin && !LaunchAtLoginManager.shared.isEnabled {
            LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: true)
        }

        // Install helper if needed
        PanicLockManager.shared.installHelperIfNeeded()

        // Setup lock-on-close
        setupLockOnClose()
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeyboardShortcutManager.shared.removeGlobalShortcut()
        powerMonitor.stop()
        screenUnlockObserver.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Lock on Close

    private func setupLockOnClose() {
        SettingsManager.shared.$lockOnClose
            .sink { [weak self] enabled in
                self?.stateMachine.isEnabled = enabled
            }
            .store(in: &cancellables)

        powerMonitor.onSleepRequest = { [weak self] token in
            guard let self else { return }
            if token.isClamshellSleep && stateMachine.isEnabled {
                storeSleepToken(token)
                stateMachine.handle(.systemWillSleep)
                if stateMachine.state != .locking {
                    // State machine didn't transition — don't hold system sleep.
                    acknowledgePendingSleep()
                }
            } else {
                powerMonitor.acknowledgeSleep(token)
            }
        }

        powerMonitor.onWake = { [weak self] in
            self?.stateMachine.handle(.systemDidWake)
        }

        screenUnlockObserver.onScreenUnlocked = { [weak self] in
            self?.stateMachine.handle(.screenUnlocked)
        }

        stateMachine.$state
            .removeDuplicates()
            .sink { [weak self] newState in
                self?.handleStateChange(newState)
            }
            .store(in: &cancellables)

        powerMonitor.start()
        screenUnlockObserver.start()
    }

    private func handleStateChange(_ state: LockState) {
        switch state {
        case .locking:
            PanicLockManager.shared.executePanicLock()
            stateMachine.completeLocking()
            acknowledgePendingSleep()
        case .unlocking:
            stateMachine.completeUnlocking()
        case .idle, .waitingForUnlock, .locked:
            break
        }
    }

    private func storeSleepToken(_ token: PowerMonitor.SleepToken) {
        acknowledgePendingSleep()
        pendingSleepToken = token
        let work = DispatchWorkItem { [weak self] in
            guard let self, pendingSleepToken != nil else { return }
            print("Sleep acknowledgment timeout — force acknowledging")
            acknowledgePendingSleep()
        }
        sleepTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
    }

    private func acknowledgePendingSleep() {
        if let token = pendingSleepToken {
            powerMonitor.acknowledgeSleep(token)
            pendingSleepToken = nil
        }
        sleepTimeoutWork?.cancel()
        sleepTimeoutWork = nil
    }
}
