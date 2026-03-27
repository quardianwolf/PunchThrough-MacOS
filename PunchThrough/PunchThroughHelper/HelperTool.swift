import Foundation

/// Main helper tool implementation
final class HelperTool: NSObject, HelperProtocol {
    private var currentProcess: Process?
    private var clientConnection: NSXPCConnection?

    // MARK: - HelperProtocol Implementation

    func startBypass(
        method: String,
        binaryPath: String,
        arguments: [String],
        withReply reply: @escaping (Bool, String?) -> Void
    ) {
        // Stop any existing process
        stopCurrentProcess()

        // Validate binary exists
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            reply(false, "Binary not found at: \(binaryPath)")
            return
        }

        // Create and configure process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments

        // Set up output handling
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Handle stdout
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                self?.notifyClient(output: output)
            }
        }

        // Handle stderr
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let error = String(data: data, encoding: .utf8) {
                self?.notifyClient(error: error)
            }
        }

        // Handle termination
        process.terminationHandler = { [weak self] process in
            self?.notifyClient(terminated: process.terminationStatus)
            self?.currentProcess = nil
        }

        // Start the process
        do {
            try process.run()
            currentProcess = process
            reply(true, nil)
        } catch {
            reply(false, "Failed to start process: \(error.localizedDescription)")
        }
    }

    func stopBypass(withReply reply: @escaping (Bool, String?) -> Void) {
        guard let process = currentProcess else {
            reply(true, nil) // Already stopped
            return
        }

        if process.isRunning {
            process.terminate()

            // Give it time to terminate gracefully
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if process.isRunning {
                    process.interrupt()
                }
                self?.currentProcess = nil
                reply(true, nil)
            }
        } else {
            currentProcess = nil
            reply(true, nil)
        }
    }

    func getStatus(withReply reply: @escaping (Bool, String, Int32) -> Void) {
        if let process = currentProcess, process.isRunning {
            reply(true, "running", 0)
        } else if let process = currentProcess {
            reply(false, "terminated", process.terminationStatus)
        } else {
            reply(false, "stopped", 0)
        }
    }

    func configureSystemProxy(
        enable: Bool,
        host: String,
        port: Int,
        networkService: String,
        withReply reply: @escaping (Bool, String?) -> Void
    ) {
        let networksetup = "/usr/sbin/networksetup"

        do {
            if enable {
                // Enable HTTP proxy
                try runNetworkSetup(["-setwebproxy", networkService, host, String(port)])
                try runNetworkSetup(["-setwebproxystate", networkService, "on"])

                // Enable HTTPS proxy
                try runNetworkSetup(["-setsecurewebproxy", networkService, host, String(port)])
                try runNetworkSetup(["-setsecurewebproxystate", networkService, "on"])
            } else {
                // Disable proxies
                try runNetworkSetup(["-setwebproxystate", networkService, "off"])
                try runNetworkSetup(["-setsecurewebproxystate", networkService, "off"])
            }

            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply(HelperConstants.version)
    }

    // MARK: - Private Methods

    private func stopCurrentProcess() {
        guard let process = currentProcess, process.isRunning else { return }
        process.terminate()
        currentProcess = nil
    }

    private func runNetworkSetup(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HelperError.networkSetupFailed(output)
        }
    }

    private func notifyClient(output: String) {
        guard let client = clientConnection?.remoteObjectProxy as? HelperClientProtocol else { return }
        client.processOutput(output)
    }

    private func notifyClient(error: String) {
        guard let client = clientConnection?.remoteObjectProxy as? HelperClientProtocol else { return }
        client.processError(error)
    }

    private func notifyClient(terminated exitCode: Int32) {
        guard let client = clientConnection?.remoteObjectProxy as? HelperClientProtocol else { return }
        client.processTerminated(exitCode: exitCode)
    }

    // MARK: - Client Connection

    func setClientConnection(_ connection: NSXPCConnection) {
        clientConnection = connection
    }
}

// MARK: - Errors

enum HelperError: LocalizedError {
    case networkSetupFailed(String)

    var errorDescription: String? {
        switch self {
        case .networkSetupFailed(let output):
            return "networksetup failed: \(output)"
        }
    }
}
