import Foundation
import IOKit
import IOKit.pwr_mgt

// IOKit C macros not bridged to Swift
private let messageSystemWillSleep: UInt32 = 0xe000_0280
private let messageSystemHasPoweredOn: UInt32 = 0xe000_0300
private let messageCanSystemSleep: UInt32 = 0xe000_0240

final class PowerMonitor {

    deinit {
        stop()
    }

    struct SleepToken {
        let rootPort: io_connect_t
        let messageArgument: Int
        let isClamshellSleep: Bool
    }

    var onWake: (() -> Void)?

    /// Caller must call `acknowledgeSleep(_:)` within 30s.
    var onSleepRequest: ((SleepToken) -> Void)?

    func start() {
        // C callback — cannot capture context, uses refcon pointer instead
        let callback: IOServiceInterestCallback = { refcon, _, messageType, messageArgument in
            guard let refcon else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handleSleepWake(messageType: messageType, argument: messageArgument)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(
            refcon,
            &notificationPort,
            callback,
            &notifierObject
        )

        guard rootPort != 0, let port = notificationPort else {
            print("PowerMonitor: Failed to register for system power notifications")
            return
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
            .defaultMode
        )
    }

    func stop() {
        if notifierObject != 0 {
            IODeregisterForSystemPower(&notifierObject)
            notifierObject = 0
        }
        if let port = notificationPort {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
                .defaultMode
            )
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
        rootPort = 0
    }

    func acknowledgeSleep(_ token: SleepToken) {
        IOAllowPowerChange(token.rootPort, token.messageArgument)
    }

    // MARK: - Private

    private var rootPort: io_connect_t = 0
    private var notificationPort: IONotificationPortRef?
    private var notifierObject: io_object_t = 0

    /// Lid Closed & No External Display
    private static func checkClamshellSleep() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        defer { IOObjectRelease(service) }
        guard service != 0 else { return false }

        func boolProperty(_ key: String) -> Bool {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
                .map { ($0.takeRetainedValue() as? Bool) ?? false } ?? false
        }

        return boolProperty("AppleClamshellState") && boolProperty("AppleClamshellCausesSleep")
    }

    private func handleSleepWake(messageType: UInt32, argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case messageSystemWillSleep:
            let clamshell = Self.checkClamshellSleep()
            let token = SleepToken(
                rootPort: rootPort,
                messageArgument: argument.map { Int(bitPattern: $0) } ?? 0,
                isClamshellSleep: clamshell
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let onSleepRequest {
                    onSleepRequest(token)
                } else {
                    acknowledgeSleep(token)
                }
            }

        case messageSystemHasPoweredOn:
            DispatchQueue.main.async { [weak self] in
                self?.onWake?()
            }

        case messageCanSystemSleep:
            if let argument {
                IOAllowPowerChange(rootPort, Int(bitPattern: argument))
            }

        default:
            break
        }
    }
}
