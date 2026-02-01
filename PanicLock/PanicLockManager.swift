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
    
    private init() {}
    
    // MARK: - Helper Installation
    
    func installHelperIfNeeded() {
        // Check if helper is already installed and running
        let installedHelperURL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(helperBundleIdentifier)")
        
        if FileManager.default.fileExists(atPath: installedHelperURL.path) {
            // Helper exists, verify it's running by pinging it
            pingHelper { isRunning in
                if !isRunning {
                    print("Helper exists but not responding, reinstalling...")
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
    
    private func installHelper() {
        // Use SMAppService to install the privileged helper (macOS 13+)
        let service = SMAppService.daemon(plistName: "com.paniclock.helper.plist")
        
        do {
            try service.register()
            print("Helper installed successfully")
        } catch {
            print("Helper installation failed: \(error)")
        }
    }
    
    // MARK: - XPC Connection
    
    private func getXPCConnection() -> NSXPCConnection {
        if let connection = xpcConnection, connection.invalidationHandler != nil {
            return connection
        }
        
        let connection = NSXPCConnection(machServiceName: helperBundleIdentifier, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: PanicLockHelperProtocol.self)
        
        connection.invalidationHandler = { [weak self] in
            self?.xpcConnection = nil
        }
        
        connection.interruptionHandler = { [weak self] in
            self?.xpcConnection = nil
        }
        
        connection.resume()
        xpcConnection = connection
        
        return connection
    }
    
    // MARK: - Panic Lock Execution
    
    func executePanicLock() {
        // Play confirmation sound if enabled
        if SettingsManager.shared.confirmationSound {
            AudioServicesPlaySystemSound(SystemSoundID(1004)) // Funk sound
        }
        
        let connection = getXPCConnection()
        
        guard let helper = connection.remoteObjectProxyWithErrorHandler({ error in
            print("XPC error: \(error)")
            // Fallback: just lock screen without disabling Touch ID
            self.lockScreenOnly()
        }) as? PanicLockHelperProtocol else {
            lockScreenOnly()
            return
        }
        
        helper.executePanicSequence { success, error in
            if !success {
                print("Panic sequence failed: \(error ?? "Unknown error")")
            } else {
                print("Panic sequence completed successfully")
            }
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
