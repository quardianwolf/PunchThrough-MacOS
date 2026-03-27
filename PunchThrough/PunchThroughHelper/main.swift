import Foundation

/// Helper tool entry point
/// This runs as a LaunchDaemon with root privileges
final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let helperTool = HelperTool()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // Verify the connecting process
        guard verifyConnection(newConnection) else {
            return false
        }

        // Configure exported interface
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = helperTool

        // Configure remote interface for callbacks
        newConnection.remoteObjectInterface = NSXPCInterface(with: HelperClientProtocol.self)

        // Store client connection for callbacks
        helperTool.setClientConnection(newConnection)

        // Handle connection lifecycle
        newConnection.invalidationHandler = {
            // Connection was invalidated
        }

        newConnection.interruptionHandler = {
            // Connection was interrupted
        }

        newConnection.resume()
        return true
    }

    private func verifyConnection(_ connection: NSXPCConnection) -> Bool {
        // In production, verify code signing requirements
        // For now, accept all connections from our app bundle

        let pid = connection.processIdentifier
        guard pid > 0 else { return false }

        // Get process path
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))

        guard pathLength > 0 else { return false }

        let processPath = String(cString: pathBuffer)

        // Verify it's our main app
        // In production, also verify code signature
        return processPath.contains("PunchThrough.app")
    }
}

// MARK: - Main

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

// Keep the helper running
RunLoop.main.run()
