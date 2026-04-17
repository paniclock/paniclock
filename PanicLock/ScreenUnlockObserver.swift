import Foundation

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
