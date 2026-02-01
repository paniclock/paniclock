import Foundation

/// Protocol for communication between the main app and the privileged helper tool
@objc(PanicLockHelperProtocol)
public protocol PanicLockHelperProtocol {
    /// Execute the full panic lock sequence:
    /// 1. Read current Touch ID timeout
    /// 2. Set timeout to 1 second
    /// 3. Lock screen
    /// 4. Wait for timeout to expire
    /// 5. Restore original timeout
    func executePanicSequence(reply: @escaping (Bool, String?) -> Void)
    
    /// Read the current Touch ID timeout value
    /// Returns -1 if reading failed, along with an error message
    func readTouchIDTimeout(reply: @escaping (Int, String?) -> Void)
    
    /// Set the Touch ID timeout value
    func setTouchIDTimeout(_ seconds: Int, reply: @escaping (Bool, String?) -> Void)
    
    /// Check if the helper is properly installed and running
    func ping(reply: @escaping (Bool) -> Void)
}

/// Bundle identifiers
public struct PanicLockIdentifiers {
    public static let mainApp = "com.paniclock.app"
    public static let helper = "com.paniclock.helper"
}

/// Default values
public struct PanicLockDefaults {
    /// Apple's default Touch ID timeout (48 hours in seconds)
    public static let defaultTimeout: Int = 172800
    
    /// Minimum timeout to disable Touch ID
    public static let minimumTimeout: Int = 1
    
    /// Time to wait for timeout to take effect
    public static let waitDuration: TimeInterval = 2.0
}
