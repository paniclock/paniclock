import Combine

enum LockEvent {
    case systemWillSleep
    case systemDidWake
    case screenUnlocked
}

enum LockState {
    case idle
    case locking
    case locked
    case waitingForUnlock
    case unlocking
}

final class LockStateMachine: ObservableObject {
    @Published private(set) var state = LockState.idle
    var isEnabled = false

    func handle(_ event: LockEvent) {
        switch (state, event) {
        case (.idle, .systemWillSleep) where isEnabled:
            state = .locking
        case (.locked, .systemDidWake):
            state = .waitingForUnlock
        case (.waitingForUnlock, .screenUnlocked):
            state = .unlocking
        default:
            break
        }
    }

    func completeLocking() {
        guard state == .locking else { return }
        state = .locked
    }

    func completeUnlocking() {
        guard state == .unlocking else { return }
        state = .idle
    }
}
