import Foundation

/// Protocol defining XPC communication between main app and helper tool
@objc protocol HelperProtocol {
    /// Start bypass with specified method and parameters
    func startBypass(
        method: String,
        binaryPath: String,
        arguments: [String],
        withReply reply: @escaping (Bool, String?) -> Void
    )

    /// Stop the currently running bypass
    func stopBypass(withReply reply: @escaping (Bool, String?) -> Void)

    /// Get current bypass status
    func getStatus(withReply reply: @escaping (Bool, String, Int32) -> Void)

    /// Configure system proxy settings
    func configureSystemProxy(
        enable: Bool,
        host: String,
        port: Int,
        networkService: String,
        withReply reply: @escaping (Bool, String?) -> Void
    )

    /// Get helper version
    func getVersion(withReply reply: @escaping (String) -> Void)
}

/// Protocol for main app callbacks
@objc protocol HelperClientProtocol {
    /// Called when bypass process outputs data
    func processOutput(_ output: String)

    /// Called when bypass process outputs error
    func processError(_ error: String)

    /// Called when bypass process terminates
    func processTerminated(exitCode: Int32)
}

// MARK: - Constants

struct HelperConstants {
    static let machServiceName = "com.splitwire.helper"
    static let version = "1.0.0"
}
