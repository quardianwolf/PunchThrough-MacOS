import Foundation
import ServiceManagement

/// Manages XPC connection to the privileged helper tool
@MainActor
final class HelperConnection: NSObject, @unchecked Sendable {
    static let shared = HelperConnection()

    private var connection: NSXPCConnection?
    private var helperProxy: HelperProtocol?
    private weak var appState: AppState?

    private override init() {
        super.init()
    }

    // MARK: - Connection Management

    func connect(appState: AppState) async throws {
        self.appState = appState

        // Check if helper is installed
        if !isHelperInstalled() {
            try await installHelper()
        }

        // Create XPC connection
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)

        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: HelperClientProtocol.self)
        connection.exportedObject = self

        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.helperProxy = nil
                self?.appState?.addLog("Helper connection invalidated", level: .warning)
            }
        }

        connection.resume()
        self.connection = connection

        // Get proxy
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            Task { @MainActor in
                self?.appState?.addLog("Helper proxy error: \(error.localizedDescription)", level: .error)
            }
        }) as? HelperProtocol else {
            throw HelperConnectionError.connectionFailed
        }

        self.helperProxy = proxy

        // Verify connection
        try await verifyConnection()
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
        helperProxy = nil
    }

    // MARK: - Helper Operations

    func startBypass(
        method: String,
        binaryPath: String,
        arguments: [String]
    ) async throws {
        guard let proxy = helperProxy else {
            throw HelperConnectionError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.startBypass(method: method, binaryPath: binaryPath, arguments: arguments) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HelperConnectionError.operationFailed(error ?? "Unknown error"))
                }
            }
        }
    }

    func stopBypass() async throws {
        guard let proxy = helperProxy else {
            throw HelperConnectionError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.stopBypass { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HelperConnectionError.operationFailed(error ?? "Unknown error"))
                }
            }
        }
    }

    func getStatus() async throws -> (isRunning: Bool, status: String, exitCode: Int32) {
        guard let proxy = helperProxy else {
            throw HelperConnectionError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.getStatus { isRunning, status, exitCode in
                continuation.resume(returning: (isRunning, status, exitCode))
            }
        }
    }

    func configureSystemProxy(
        enable: Bool,
        host: String = "127.0.0.1",
        port: Int = 8080,
        networkService: String = "Wi-Fi"
    ) async throws {
        guard let proxy = helperProxy else {
            throw HelperConnectionError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.configureSystemProxy(
                enable: enable,
                host: host,
                port: port,
                networkService: networkService
            ) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HelperConnectionError.operationFailed(error ?? "Unknown error"))
                }
            }
        }
    }

    // MARK: - Helper Installation

    private func isHelperInstalled() -> Bool {
        let helperPath = "/Library/PrivilegedHelperTools/\(HelperConstants.machServiceName)"
        return FileManager.default.fileExists(atPath: helperPath)
    }

    private func installHelper() async throws {
        // Use SMAppService for modern helper installation (macOS 13+)
        let service = SMAppService.daemon(plistName: "\(HelperConstants.machServiceName).plist")

        do {
            try service.register()
            appState?.addLog("Helper tool registered successfully")
        } catch {
            appState?.addLog("Failed to register helper: \(error.localizedDescription)", level: .error)
            throw HelperConnectionError.installationFailed(error.localizedDescription)
        }
    }

    private func verifyConnection() async throws {
        guard let proxy = helperProxy else {
            throw HelperConnectionError.notConnected
        }

        let version: String = await withCheckedContinuation { continuation in
            proxy.getVersion { version in
                continuation.resume(returning: version)
            }
        }

        appState?.addLog("Connected to helper v\(version)", level: .debug)
    }
}

// MARK: - HelperClientProtocol

extension HelperConnection: HelperClientProtocol {
    nonisolated func processOutput(_ output: String) {
        Task { @MainActor in
            self.appState?.addLog("[Helper] \(output)", level: .info)
        }
    }

    nonisolated func processError(_ error: String) {
        Task { @MainActor in
            self.appState?.addLog("[Helper] \(error)", level: .warning)
        }
    }

    nonisolated func processTerminated(exitCode: Int32) {
        Task { @MainActor in
            if exitCode == 0 {
                self.appState?.addLog("Process terminated normally", level: .info)
            } else {
                self.appState?.addLog("Process terminated with code: \(exitCode)", level: .warning)
            }
        }
    }
}

// MARK: - Errors

enum HelperConnectionError: LocalizedError {
    case notConnected
    case connectionFailed
    case installationFailed(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to helper"
        case .connectionFailed:
            return "Failed to connect to helper"
        case .installationFailed(let reason):
            return "Failed to install helper: \(reason)"
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        }
    }
}
