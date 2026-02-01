import Foundation

@main
struct HelperMain {
    static func main() {
        let helperTool = HelperTool()
        
        // Create the XPC listener
        let listener = NSXPCListener(machServiceName: PanicLockIdentifiers.helper)
        listener.delegate = helperTool
        listener.resume()
        
        // Keep the helper running
        RunLoop.main.run()
    }
}
