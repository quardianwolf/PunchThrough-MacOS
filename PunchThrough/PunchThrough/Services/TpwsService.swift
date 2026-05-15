import Foundation

/// Manages the tpws (zapret) DPI bypass engine.
/// Unlike SpoofDPI, tpws needs a one-time admin install:
/// - copies /opt/punchthrough-zapret/
/// - writes /etc/sudoers.d/punchthrough-zapret (passwordless control)
/// - writes /Library/LaunchDaemons/com.punchthrough.zapret.plist
/// After install, start/stop happen via `sudo` without password prompts.
actor TpwsService {
    private let targetDir = "/opt/punchthrough-zapret"
    private let sudoersPath = "/etc/sudoers.d/punchthrough-zapret"
    private let launchDaemonPath = "/Library/LaunchDaemons/com.punchthrough.zapret.plist"

    private let logFile: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/PunchThrough", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tpws_debug.log")
    }()

    private func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path),
               let h = try? FileHandle(forWritingTo: logFile) {
                h.seekToEndOfFile(); h.write(data); h.closeFile()
            } else {
                try? data.write(to: logFile)
            }
        }
        print(line)
    }

    // MARK: - Install state

    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: targetDir + "/init.d/macos/zapret") &&
        FileManager.default.fileExists(atPath: sudoersPath)
    }

    /// Path to the bundled installer script inside the .app
    private func bundledInstallerPath() -> String? {
        Bundle.main.path(forResource: "install_punchthrough", ofType: "sh",
                         inDirectory: "zapret/scripts")
    }

    private func bundledUninstallerPath() -> String? {
        Bundle.main.path(forResource: "uninstall_punchthrough", ofType: "sh",
                         inDirectory: "zapret/scripts")
    }

    /// Run a shell script with admin privileges via AppleScript's `with administrator privileges`.
    /// This pops the standard macOS auth dialog. One-time per install.
    private func runWithAdmin(scriptPath: String) async throws {
        // Escape double quotes for AppleScript embedding
        let escaped = scriptPath.replacingOccurrences(of: "\"", with: "\\\"")
        let osascript = """
        do shell script "/bin/bash \\"\(escaped)\\"" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", osascript]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        log("Admin script exit: \(process.terminationStatus), output: \(output)")

        if process.terminationStatus != 0 {
            throw TpwsError.installFailed(output.isEmpty ? "User cancelled or script failed" : output)
        }
    }

    func install() async throws {
        guard let script = bundledInstallerPath() else {
            throw TpwsError.bundleMissing
        }
        log("Installing tpws via \(script)")
        try await runWithAdmin(scriptPath: script)
        log("Install complete")
    }

    func uninstall() async throws {
        guard let script = bundledUninstallerPath() else {
            throw TpwsError.bundleMissing
        }
        log("Uninstalling tpws via \(script)")
        try await runWithAdmin(scriptPath: script)
        log("Uninstall complete")
    }

    // MARK: - Service control (no admin prompt, uses sudoers NOPASSWD rule)

    private func runSudoControl(_ verb: String) async throws -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "\(targetDir)/init.d/macos/zapret", verb]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    func start(appState: AppState) async throws {
        guard isInstalled() else {
            throw TpwsError.notInstalled
        }
        log("Starting tpws service...")

        let result = try await runSudoControl("start")
        log("Start exit: \(result.code), output: \(result.output)")

        if result.code != 0 {
            throw TpwsError.startFailed(result.output)
        }

        // Give tpws a moment to bind and the firewall rules to settle
        try await Task.sleep(for: .milliseconds(800))

        // Quick sanity check — is the tpws process running?
        let running = await isRunning()
        if !running {
            log("WARN: control script returned 0 but no tpws process found")
        }

        await MainActor.run {
            appState.addLog("tpws service started", level: .info)
        }
    }

    func stop(appState: AppState) async {
        log("Stopping tpws service...")
        do {
            let result = try await runSudoControl("stop")
            log("Stop exit: \(result.code), output: \(result.output)")
        } catch {
            log("Stop error: \(error.localizedDescription)")
        }

        await MainActor.run {
            appState.addLog("tpws service stopped", level: .info)
        }
    }

    func isRunning() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "tpws"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

enum TpwsError: LocalizedError {
    case notInstalled
    case bundleMissing
    case installFailed(String)
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Zapret service is not installed. Use Settings → Bypass → Install Zapret Service."
        case .bundleMissing:
            return "Bundled installer not found inside the app."
        case .installFailed(let msg):
            return "Install failed: \(msg)"
        case .startFailed(let msg):
            return "Failed to start zapret: \(msg)"
        }
    }
}
