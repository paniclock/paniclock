import Foundation

class HelperTool: NSObject, NSXPCListenerDelegate, PanicLockHelperProtocol {
    
    private var cachedTimeout: Int?
    
    // MARK: - NSXPCListenerDelegate
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Verify the connecting process
        guard verifyConnection(newConnection) else {
            return false
        }
        
        newConnection.exportedInterface = NSXPCInterface(with: PanicLockHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        
        return true
    }
    
    private func verifyConnection(_ connection: NSXPCConnection) -> Bool {
        // Verify the code signature of the connecting app
        let pid = connection.processIdentifier
        
        // Expected values - must match main app
        let expectedBundleID = "com.paniclock.app"
        let expectedTeamID = "6UA5KMSP89"
        
        // Get the code signature of the connecting process
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let secCode = code else {
            NSLog("PanicLockHelper: Failed to get code for PID \(pid)")
            return false
        }
        
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(secCode, [], &staticCode) == errSecSuccess,
              let secStaticCode = staticCode else {
            NSLog("PanicLockHelper: Failed to get static code")
            return false
        }
        
        // Get signing information
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(secStaticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let signingInfo = info as? [String: Any] else {
            NSLog("PanicLockHelper: Failed to get signing information")
            return false
        }
        
        // Verify bundle identifier
        guard let bundleID = signingInfo[kSecCodeInfoIdentifier as String] as? String,
              bundleID == expectedBundleID else {
            NSLog("PanicLockHelper: Bundle ID mismatch")
            return false
        }
        
        // Verify team identifier
        guard let teamID = signingInfo[kSecCodeInfoTeamIdentifier as String] as? String,
              teamID == expectedTeamID else {
            NSLog("PanicLockHelper: Team ID mismatch")
            return false
        }
        
        // Verify the signature is valid
        let requirement = "identifier \"\(expectedBundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(expectedTeamID)\""
        var secRequirement: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &secRequirement) == errSecSuccess,
              let req = secRequirement else {
            NSLog("PanicLockHelper: Failed to create requirement")
            return false
        }
        
        let validationResult = SecStaticCodeCheckValidity(secStaticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), req)
        if validationResult != errSecSuccess {
            NSLog("PanicLockHelper: Code validation failed: \(validationResult)")
            return false
        }
        
        NSLog("PanicLockHelper: Connection verified for \(bundleID)")
        return true
    }
    
    // MARK: - PanicLockHelperProtocol
    
    func executePanicSequence(reply: @escaping (Bool, String?) -> Void) {
        // Step 1: Read current timeout
        readTouchIDTimeout { [weak self] currentTimeout, readError in
            guard let self = self else {
                reply(false, "Helper deallocated")
                return
            }
            
            // Use current timeout or default if read failed (indicated by -1)
            let timeout = currentTimeout > 0 ? currentTimeout : PanicLockDefaults.defaultTimeout
            self.cachedTimeout = timeout
            
            // Step 2: Set timeout to 1 second
            self.setTouchIDTimeout(PanicLockDefaults.minimumTimeout) { success, setError in
                guard success else {
                    reply(false, setError ?? "Failed to set timeout")
                    return
                }
                
                // Step 3: Lock screen
                self.lockScreen()
                
                // Step 4: Wait for timeout to expire
                DispatchQueue.global().asyncAfter(deadline: .now() + PanicLockDefaults.waitDuration) {
                    // Step 5: Restore original timeout
                    self.setTouchIDTimeout(timeout) { restoreSuccess, restoreError in
                        if !restoreSuccess {
                            print("Warning: Failed to restore timeout: \(restoreError ?? "Unknown error")")
                        }
                        reply(true, nil)
                    }
                }
            }
        }
    }
    
    func readTouchIDTimeout(reply: @escaping (Int, String?) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/bioutil")
        task.arguments = ["-r", "-s"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                reply(-1, "Failed to read bioutil output")
                return
            }
            
            // Parse "Touch ID timeout" value from output
            // Expected format: "Touch ID timeout: <seconds>"
            if let timeout = parseTouchIDTimeout(from: output) {
                reply(timeout, nil)
            } else {
                reply(-1, "Failed to parse Touch ID timeout from: \(output)")
            }
            
        } catch {
            reply(-1, "Failed to execute bioutil: \(error.localizedDescription)")
        }
    }
    
    func setTouchIDTimeout(_ seconds: Int, reply: @escaping (Bool, String?) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/bioutil")
        task.arguments = ["-w", "-s", "-o", String(seconds)]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                reply(true, nil)
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                reply(false, "bioutil failed with status \(task.terminationStatus): \(output)")
            }
            
        } catch {
            reply(false, "Failed to execute bioutil: \(error.localizedDescription)")
        }
    }
    
    func ping(reply: @escaping (Bool) -> Void) {
        reply(true)
    }
    
    // MARK: - Private Methods
    
    private func parseTouchIDTimeout(from output: String) -> Int? {
        // bioutil -r -s outputs:
        //     Biometric timeout (in seconds): 1800
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Biometric timeout") {
                let parts = trimmed.components(separatedBy: ":")
                if let value = parts.last?.trimmingCharacters(in: .whitespaces),
                   let timeout = Int(value) {
                    return timeout
                }
            }
        }
        return nil
    }
    
    private func lockScreen() {
        // Method 1: Use pmset (preferred)
        let pmsetTask = Process()
        pmsetTask.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        pmsetTask.arguments = ["displaysleepnow"]
        
        do {
            try pmsetTask.run()
            pmsetTask.waitUntilExit()
            return
        } catch {
            print("pmset failed: \(error)")
        }
        
        // Method 2: Fallback using loginwindow
        let loginTask = Process()
        loginTask.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession")
        loginTask.arguments = ["-suspend"]
        
        do {
            try loginTask.run()
            loginTask.waitUntilExit()
        } catch {
            print("CGSession failed: \(error)")
        }
    }
}
