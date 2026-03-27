import Foundation

/// Manages external process lifecycle
actor ProcessManager {
    static let shared = ProcessManager()

    private var runningProcesses: [String: Process] = [:]

    private init() {}

    // MARK: - Process Management

    /// Start a process with the given command and arguments
    func startProcess(
        identifier: String,
        command: String,
        arguments: [String],
        onOutput: (@Sendable (String) -> Void)? = nil,
        onError: (@Sendable (String) -> Void)? = nil
    ) async throws {
        // Terminate existing process if running
        if let existingProcess = runningProcesses[identifier], existingProcess.isRunning {
            existingProcess.terminate()
            runningProcesses.removeValue(forKey: identifier)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        // Set up stdout pipe
        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        // Set up stderr pipe
        let errorPipe = Pipe()
        process.standardError = errorPipe

        // Handle stdout
        if let onOutput = onOutput {
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                    onOutput(output.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        // Handle stderr
        if let onError = onError {
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                    onError(output.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        do {
            try process.run()
            runningProcesses[identifier] = process
        } catch {
            throw ProcessError.launchFailed(error.localizedDescription)
        }
    }

    /// Stop a running process
    func stopProcess(identifier: String) async throws {
        guard let process = runningProcesses[identifier] else {
            return // Already stopped
        }

        if process.isRunning {
            // Try graceful termination first
            process.terminate()

            // Wait briefly for graceful shutdown
            try await Task.sleep(for: .milliseconds(500))

            // Force kill if still running
            if process.isRunning {
                process.interrupt()
            }
        }

        runningProcesses.removeValue(forKey: identifier)
    }

    /// Check if a process is running
    func isProcessRunning(identifier: String) -> Bool {
        guard let process = runningProcesses[identifier] else {
            return false
        }
        return process.isRunning
    }

    /// Common paths where Homebrew and other tools are installed
    private let commonPaths = [
        "/opt/homebrew/bin",      // Apple Silicon Homebrew
        "/usr/local/bin",         // Intel Homebrew
        "/usr/bin",
        "/bin"
    ]

    /// Check if a command is available
    func isCommandAvailable(_ command: String) async -> Bool {
        await findCommandPath(command) != nil
    }

    /// Find the full path of a command
    func findCommandPath(_ command: String) async -> String? {
        // First check common paths directly (works even without shell PATH)
        for basePath in commonPaths {
            let fullPath = "\(basePath)/\(command)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        // Fallback to which with extended PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", command]
        process.environment = [
            "PATH": commonPaths.joined(separator: ":") + ":/usr/sbin:/sbin"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {}

        return nil
    }

    /// Run a command and return its output
    func runCommand(_ command: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Stop all running processes
    func stopAllProcesses() async {
        for (identifier, process) in runningProcesses {
            if process.isRunning {
                process.terminate()
            }
            runningProcesses.removeValue(forKey: identifier)
        }
    }
}

// MARK: - Errors

enum ProcessError: LocalizedError {
    case notFound(String)
    case launchFailed(String)
    case terminationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let command):
            return "Command not found: \(command)"
        case .launchFailed(let reason):
            return "Failed to launch process: \(reason)"
        case .terminationFailed(let reason):
            return "Failed to terminate process: \(reason)"
        }
    }
}
