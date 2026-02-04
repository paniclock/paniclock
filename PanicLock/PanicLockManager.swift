import Foundation
import AudioToolbox
import AppKit
import ServiceManagement

class PanicLockManager {
    static let shared = PanicLockManager()
    
    private let helperBundleIdentifier = "com.paniclock.helper"
    private let defaultTimeout: Int = 172800 // 48 hours - Apple's default
    private var cachedTimeout: Int?
    private var xpcConnection: NSXPCConnection?
    private let connectionLock = NSLock()
    
    private init() {}
    
    // MARK: - Helper Installation
    
    func installHelperIfNeeded() {
        // Check if helper is already installed and running
        let installedHelperURL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(helperBundleIdentifier)")
        
        if FileManager.default.fileExists(atPath: installedHelperURL.path) {
            // Helper exists, verify it's running by pinging it with retries
            // launchd may still be starting the helper after boot
            pingHelperWithRetry(attempts: 3, delay: 1.0) { isRunning in
                if !isRunning {
                    print("Helper exists but not responding after retries, reinstalling...")
                    self.installHelper()
                } else {
                    print("Helper is installed and running")
                }
            }
        } else {
            print("Helper not installed, installing...")
            installHelper()
        }
    }
    
    private func pingHelper(completion: @escaping (Bool) -> Void) {
        let connection = getXPCConnection()
        
        guard let helper = connection.remoteObjectProxyWithErrorHandler({ error in
            print("Ping error: \(error)")
            completion(false)
        }) as? PanicLockHelperProtocol else {
            completion(false)
            return
        }
        
        helper.ping { success in
            completion(success)
        }
    }
    
    private func pingHelperWithRetry(attempts: Int, delay: TimeInterval, completion: @escaping (Bool) -> Void) {
        pingHelper { isRunning in
            if isRunning {
                completion(true)
            } else if attempts > 1 {
                // Clear stale connection before retry
                self.connectionLock.lock()
                self.xpcConnection?.invalidate()
                self.xpcConnection = nil
                self.connectionLock.unlock()
                
                print("Helper not responding, retrying in \(delay)s... (\(attempts - 1) attempts left)")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.pingHelperWithRetry(attempts: attempts - 1, delay: delay, completion: completion)
                }
            } else {
                completion(false)
            }
        }
    }
    
    @available(macOS, deprecated: 13.0, message: "SMJobBless is deprecated but required for privileged helpers")
    private func installHelper() {
        // SMJobBless is deprecated but SMAppService doesn't support privileged helpers
        // that need root access (like running bioutil). Must use SMJobBless.
        var authRef: AuthorizationRef?
        let authFlags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]
        
        let authItemName = kSMRightBlessPrivilegedHelper
        
        var authItem = authItemName.withCString { name in
            AuthorizationItem(
                name: name,
                valueLength: 0,
                value: nil,
                flags: 0
            )
        }
        
        var authRights = withUnsafeMutablePointer(to: &authItem) { pointer in
            AuthorizationRights(count: 1, items: pointer)
        }
        
        let status = AuthorizationCreate(&authRights, nil, authFlags, &authRef)
        
        guard status == errAuthorizationSuccess, let auth = authRef else {
            print("Authorization failed: \(status)")
            return
        }
        
        defer {
            AuthorizationFree(auth, [])
        }
        
        var error: Unmanaged<CFError>?
        let success = SMJobBless(
            kSMDomainSystemLaunchd,
            helperBundleIdentifier as CFString,
            auth,
            &error
        )
        
        if !success {
            if let err = error?.takeRetainedValue() {
                print("Helper installation failed: \(err)")
            }
        } else {
            print("Helper installed successfully")
        }
    }
    
    // MARK: - XPC Connection
    
    private func getXPCConnection() -> NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        
        if let connection = xpcConnection {
            return connection
        }
        
        let connection = NSXPCConnection(machServiceName: helperBundleIdentifier, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: PanicLockHelperProtocol.self)
        
        connection.invalidationHandler = { [weak self] in
            self?.connectionLock.lock()
            self?.xpcConnection = nil
            self?.connectionLock.unlock()
            print("XPC connection invalidated")
        }
        
        connection.interruptionHandler = { [weak self] in
            // Interruption means helper crashed but launchd will restart it
            // Clear connection so next call creates a fresh one
            self?.connectionLock.lock()
            self?.xpcConnection = nil
            self?.connectionLock.unlock()
            print("XPC connection interrupted - helper may have restarted")
        }
        
        connection.resume()
        xpcConnection = connection
        
        return connection
    }
    
    private func executeWithRetry<T>(
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1.0,
        operation: @escaping (PanicLockHelperProtocol, @escaping (T) -> Void) -> Void,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        var attempts = 0
        
        func attempt() {
            attempts += 1
            let connection = getXPCConnection()
            
            guard let helper = connection.remoteObjectProxyWithErrorHandler({ error in
                print("XPC error (attempt \(attempts)): \(error)")
                if attempts < maxRetries {
                    // Clear connection and retry after delay
                    self.connectionLock.lock()
                    self.xpcConnection?.invalidate()
                    self.xpcConnection = nil
                    self.connectionLock.unlock()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                        attempt()
                    }
                } else {
                    completion(.failure(error))
                }
            }) as? PanicLockHelperProtocol else {
                let error = NSError(domain: "PanicLock", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get helper proxy"])
                completion(.failure(error))
                return
            }
            
            operation(helper) { result in
                completion(.success(result))
            }
        }
        
        attempt()
    }
    
    // MARK: - Panic Lock Execution
    
    func executePanicLock() {
        // Ensure screen lock is set to immediate (one-time, persists)
        ensureImmediateLock()
        
        // Play confirmation sound if enabled
        if SettingsManager.shared.confirmationSound {
            AudioServicesPlaySystemSound(SystemSoundID(1004)) // Funk sound
        }
        
        executeWithRetry(
            maxRetries: 3,
            retryDelay: 0.5,
            operation: { helper, completion in
                helper.executePanicSequence { success, error in
                    completion((success, error))
                }
            },
            completion: { [weak self] (result: Result<(Bool, String?), Error>) in
                switch result {
                case .success(let (success, error)):
                    if !success {
                        print("Panic sequence failed: \(error ?? "Unknown error")")
                    } else {
                        print("Panic sequence completed successfully")
                    }
                case .failure(let error):
                    print("XPC failed after retries: \(error)")
                    // Fallback: just lock screen without disabling Touch ID
                    self?.lockScreenOnly()
                }
            }
        )
    }
    
    private func ensureImmediateLock() {
        // Check current screen lock delay setting
        let statusTask = Process()
        statusTask.executableURL = URL(fileURLWithPath: "/usr/sbin/sysadminctl")
        statusTask.arguments = ["-screenLock", "status"]
        
        let statusPipe = Pipe()
        statusTask.standardOutput = statusPipe
        statusTask.standardError = statusPipe
        
        do {
            try statusTask.run()
            statusTask.waitUntilExit()
            
            let data = statusPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // If already set to immediate, no action needed
            if output.contains("immediate") {
                print("Screen lock already set to immediate")
                return
            }
            
            print("Setting screen lock to immediate")
            
        } catch {
            print("Failed to check screen lock status: \(error)")
        }
        
        // Set screen lock to immediate using empty password (works for current user)
        let setTask = Process()
        setTask.executableURL = URL(fileURLWithPath: "/usr/sbin/sysadminctl")
        setTask.arguments = ["-screenLock", "immediate", "-password", "-"]
        
        // Provide empty password via stdin
        let inputPipe = Pipe()
        setTask.standardInput = inputPipe
        setTask.standardOutput = FileHandle.nullDevice
        setTask.standardError = FileHandle.nullDevice
        
        do {
            try setTask.run()
            // Write empty string and close to simulate: echo "" | sysadminctl ...
            inputPipe.fileHandleForWriting.write("\n".data(using: .utf8)!)
            inputPipe.fileHandleForWriting.closeFile()
            setTask.waitUntilExit()
            
            if setTask.terminationStatus == 0 {
                print("Screen lock set to immediate successfully")
            } else {
                print("sysadminctl exited with status \(setTask.terminationStatus)")
            }
        } catch {
            print("Failed to set screen lock: \(error)")
        }
    }
    
    private func lockScreenOnly() {
        // Fallback: lock screen without disabling Touch ID
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession")
        task.arguments = ["-suspend"]
        
        do {
            try task.run()
        } catch {
            print("Failed to lock screen: \(error)")
        }
    }
    
    // MARK: - Uninstall App
    
    func uninstallApp(completion: @escaping (Bool, String?) -> Void) {
        // Get the app's bundle path and escape it for shell
        let appPath = Bundle.main.bundlePath
        
        // Escape single quotes in path: replace ' with '\'' 
        let escapedPath = appPath.replacingOccurrences(of: "'", with: "'\\''")
        
        let script = """
        do shell script "launchctl bootout system/com.paniclock.helper 2>/dev/null; rm -f /Library/PrivilegedHelperTools/com.paniclock.helper /Library/LaunchDaemons/com.paniclock.helper.plist; rm -rf '\(escapedPath)'" with administrator privileges
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            
            if let error = error {
                let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                completion(false, errorMessage)
            } else {
                // Invalidate XPC connection
                xpcConnection?.invalidate()
                xpcConnection = nil
                completion(true, nil)
            }
        } else {
            completion(false, "Failed to create uninstall script")
        }
    }
}
