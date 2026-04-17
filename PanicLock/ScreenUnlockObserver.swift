import Foundation

/// Observes screen unlock events using the private `com.apple.screenIsUnlocked`
/// distributed notification. There is no public API that fires specifically after
/// the user authenticates at the lock screen:
/// - `sessionDidBecomeActiveNotification` is for fast user switching only
/// - `didWakeNotification` / `screensDidWakeNotification` fire before authentication
/// If Apple removes this notification in a future macOS version, the unlock
/// transition will not fire and Touch ID timeout will remain at 1s until app restart.
final class ScreenUnlockObserver {

    deinit {
        stop()
    }

    var onScreenUnlocked: (() -> Void)?

    func start() {
        guard observerToken == nil else { return }
        observerToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onScreenUnlocked?()
        }
    }

    func stop() {
        if let token = observerToken {
            DistributedNotificationCenter.default().removeObserver(token)
            observerToken = nil
        }
    }

    private var observerToken: NSObjectProtocol?
}
