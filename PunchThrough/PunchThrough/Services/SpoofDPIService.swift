import Foundation
import Darwin

/// Service for managing SpoofDPI process
actor SpoofDPIService {
    private var currentProcess: Process?

    // Log file in standard macOS location: ~/Library/Logs/PunchThrough/
    private let logFile: URL = {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/PunchThrough", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("punchthrough_debug.log")
    }()

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"

        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
        print(logLine) // Also print to console
    }

    func start(
        port: Int,
        dnsAddress: String,
        enableDoH: Bool,
        enableSystemProxy: Bool,
        logLevel: String = "info",
        appState: AppState
    ) async throws {
        log("=== START ATTEMPT ===")

        // Prefer bundled SpoofDPI v1.3.0 (avoids breakage from brew upgrades)
        // Fall back to system paths only if bundle resource is missing
        var spoofDPIPath: String?

        if let bundled = Bundle.main.path(forResource: "spoofdpi", ofType: nil) {
            log("Found bundled spoofdpi at: \(bundled)")
            spoofDPIPath = bundled
        } else {
            let fallbackPaths = [
                "/opt/homebrew/bin/spoofdpi",
                "/usr/local/bin/spoofdpi",
            ]
            log("Bundled binary not found, checking fallback paths: \(fallbackPaths)")
            for path in fallbackPaths {
                let executable = FileManager.default.isExecutableFile(atPath: path)
                log("Path \(path): executable=\(executable)")
                if executable {
                    spoofDPIPath = path
                    break
                }
            }
        }

        guard let binaryPath = spoofDPIPath else {
            log("ERROR: SpoofDPI not found!")
            throw SpoofDPIError.notInstalled
        }

        log("Using spoofdpi at: \(binaryPath)")

        // Stop existing process and kill all spoofdpi instances (but don't disable proxy yet)
        await stop(appState: appState, disableProxy: false)

        // Extra aggressive cleanup
        await killAllSpoofDPI()

        // Check if port is in use
        if isPortInUse(port) {
            log("ERROR: Port \(port) is still in use after cleanup!")
            throw SpoofDPIError.portInUse(port)
        }

        // If user has a custom TOML config, pass it explicitly via --config.
        // CLI flags below still override values set in the TOML.
        let userConfigPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/spoofdpi/spoofdpi.toml").path
        var configArgs: [String] = []
        if FileManager.default.fileExists(atPath: userConfigPath) {
            configArgs = ["--config", userConfigPath]
            log("Using user TOML config: \(userConfigPath)")
        }

        // Build argument sets - try enhanced flags first, fall back to basic
        var enhancedArgs: [String] = configArgs + [
            "--listen-addr", "127.0.0.1:\(port)",
            "--dns-addr", "\(dnsAddress):53",
            "--log-level", logLevel,
            "--https-disorder",
            "--https-chunk-size", "1",
            "--https-split-mode", "random",
            "--policy-auto"
        ]
        if enableDoH {
            enhancedArgs.append(contentsOf: ["--dns-mode", "https"])
        }

        var basicArgs: [String] = configArgs + [
            "--listen-addr", "127.0.0.1:\(port)",
            "--dns-addr", "\(dnsAddress):53",
            "--log-level", logLevel,
            "--https-disorder",
            "--https-chunk-size", "1",
            "--https-split-mode", "random"
        ]
        if enableDoH {
            basicArgs.append(contentsOf: ["--dns-mode", "https"])
        }

        let argSets = [enhancedArgs, basicArgs]

        var started = false
        for (index, arguments) in argSets.enumerated() {
            let label = index == 0 ? "enhanced" : "basic"
            let fullCommand = "\(binaryPath) \(arguments.joined(separator: " "))"
            log("Trying \(label) flags: \(fullCommand)")

            let result = try await launchProcess(binaryPath: binaryPath, arguments: arguments, port: port)

            switch result {
            case .success:
                log("SUCCESS! SpoofDPI is running and listening on port \(port) (\(label) flags)")
                started = true
            case .unsupportedFlags:
                log("Unsupported flags detected, falling back to \(index == 0 ? "basic" : "no more") flags...")
                continue
            case .failed:
                throw SpoofDPIError.failedToStart
            }

            if started { break }
        }

        guard started else {
            throw SpoofDPIError.failedToStart
        }

        // Set system proxy automatically
        if enableSystemProxy {
            await setSystemProxy(enabled: true, port: port)
            log("System proxy enabled on port \(port)")
        }

        await MainActor.run {
            appState.addLog("SpoofDPI started on port \(port)", level: .info)
        }
    }

    private func setSystemProxy(enabled: Bool, port: Int) async {
        let networkServices = getActiveNetworkServices()

        for service in networkServices {
            if enabled {
                // Enable HTTP proxy
                let httpProxy = Process()
                httpProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                httpProxy.arguments = ["-setwebproxy", service, "127.0.0.1", String(port)]
                try? httpProxy.run()
                httpProxy.waitUntilExit()

                let httpOn = Process()
                httpOn.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                httpOn.arguments = ["-setwebproxystate", service, "on"]
                try? httpOn.run()
                httpOn.waitUntilExit()

                // Enable HTTPS proxy
                let httpsProxy = Process()
                httpsProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                httpsProxy.arguments = ["-setsecurewebproxy", service, "127.0.0.1", String(port)]
                try? httpsProxy.run()
                httpsProxy.waitUntilExit()

                let httpsOn = Process()
                httpsOn.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                httpsOn.arguments = ["-setsecurewebproxystate", service, "on"]
                try? httpsOn.run()
                httpsOn.waitUntilExit()

                log("Proxy enabled for \(service)")
            } else {
                // Disable HTTP proxy
                let httpOff = Process()
                httpOff.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                httpOff.arguments = ["-setwebproxystate", service, "off"]
                try? httpOff.run()
                httpOff.waitUntilExit()

                // Disable HTTPS proxy
                let httpsOff = Process()
                httpsOff.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                httpsOff.arguments = ["-setsecurewebproxystate", service, "off"]
                try? httpsOff.run()
                httpsOff.waitUntilExit()

                log("Proxy disabled for \(service)")
            }
        }
    }

    private enum LaunchResult {
        case success
        case unsupportedFlags
        case failed
    }

    private func launchProcess(binaryPath: String, arguments: [String], port: Int) async throws -> LaunchResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments

        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/PunchThrough", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let stdoutFile = logsDir.appendingPathComponent("spoofdpi_stdout.log")
        let stderrFile = logsDir.appendingPathComponent("spoofdpi_stderr.log")

        FileManager.default.createFile(atPath: stdoutFile.path, contents: nil)
        FileManager.default.createFile(atPath: stderrFile.path, contents: nil)

        if let stdoutHandle = try? FileHandle(forWritingTo: stdoutFile),
           let stderrHandle = try? FileHandle(forWritingTo: stderrFile) {
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle
        }

        do {
            log("Calling process.run()...")
            try process.run()
            log("process.run() succeeded! PID: \(process.processIdentifier)")
            currentProcess = process
        } catch {
            log("process.run() FAILED: \(error.localizedDescription)")
            return .failed
        }

        log("Waiting for SpoofDPI to start listening on port \(port)...")

        let maxAttempts = 10
        for attempt in 1...maxAttempts {
            if !process.isRunning {
                let exitCode = process.terminationStatus
                log("Process exited early with code: \(exitCode)")

                let stderrContent = (try? String(contentsOf: stderrFile, encoding: .utf8)) ?? ""
                log("STDERR content: \(stderrContent)")

                if let stdoutContent = try? String(contentsOf: stdoutFile, encoding: .utf8) {
                    log("STDOUT content: \(stdoutContent)")
                }

                if stderrContent.contains("flag provided but not defined") {
                    currentProcess = nil
                    return .unsupportedFlags
                }

                currentProcess = nil
                return .failed
            }

            if isPortInUse(port) {
                log("Port \(port) is listening after attempt \(attempt)")

                let connectionVerified = await verifyProxyConnection(port: port)
                if !connectionVerified {
                    log("WARNING: Port is listening but proxy connection test failed, proceeding anyway")
                } else {
                    log("Proxy connection verified successfully")
                }

                return .success
            }

            log("Attempt \(attempt)/\(maxAttempts) - port not ready yet, waiting 500ms...")
            try await Task.sleep(for: .milliseconds(500))
        }

        log("ERROR: SpoofDPI process is running but not listening on port \(port) after \(maxAttempts) attempts")
        process.terminate()
        currentProcess = nil
        return .failed
    }

    private func getActiveNetworkServices() -> [String] {
        // Get list of network services
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listallnetworkservices"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Parse services, skip first line (header) and asterisk-prefixed disabled services
        let services = output.components(separatedBy: "\n")
            .dropFirst()
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // Return common active services
        let priorityServices = ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN"]
        return services.filter { priorityServices.contains($0) }
    }

    func stop(appState: AppState, disableProxy: Bool = true) async {
        log("Stopping SpoofDPI...")

        if let process = currentProcess, process.isRunning {
            process.terminate()
            log("Sent terminate signal")
        }

        // Kill all spoofdpi processes aggressively
        await killAllSpoofDPI()

        // Disable system proxy
        if disableProxy {
            await setSystemProxy(enabled: false, port: 8080)
            log("System proxy disabled")
        }

        currentProcess = nil

        await MainActor.run {
            appState.addLog("SpoofDPI stopped", level: .info)
        }
    }

    private func killAllSpoofDPI() async {
        // Try pkill first
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-9", "spoofdpi"]
        try? pkill.run()
        pkill.waitUntilExit()
        log("pkill -9 spoofdpi exit code: \(pkill.terminationStatus)")

        // Also try killall
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["-9", "spoofdpi"]
        try? killall.run()
        killall.waitUntilExit()
        log("killall -9 spoofdpi exit code: \(killall.terminationStatus)")

        // Wait for port to be released
        try? await Task.sleep(for: .milliseconds(500))
    }

    private func isPortInUse(_ port: Int) -> Bool {
        let checkProcess = Process()
        checkProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        checkProcess.arguments = ["-i", ":\(port)", "-sTCP:LISTEN"]

        let pipe = Pipe()
        checkProcess.standardOutput = pipe
        checkProcess.standardError = FileHandle.nullDevice

        try? checkProcess.run()
        checkProcess.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        let inUse = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        log("Port \(port) in use: \(inUse)")
        return inUse
    }

    private func verifyProxyConnection(port: Int) async -> Bool {
        // Try a TCP connection to the proxy to verify it's accepting connections
        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        let queue = DispatchQueue(label: "proxy-verify")
        queue.async {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(port).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let sock = socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else {
                semaphore.signal()
                return
            }
            defer { close(sock) }

            // Set a short timeout
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            let result = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            success = (result == 0)
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 3)
        log("Proxy connection verification: \(success ? "OK" : "FAILED")")
        return success
    }

    func isRunning() -> Bool {
        currentProcess?.isRunning ?? false
    }
}

enum SpoofDPIError: LocalizedError {
    case notInstalled
    case failedToStart
    case failedToStop
    case portInUse(Int)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "SpoofDPI not installed. Run: brew install spoofdpi"
        case .failedToStart:
            return "Failed to start SpoofDPI"
        case .failedToStop:
            return "Failed to stop SpoofDPI"
        case .portInUse(let port):
            return "Port \(port) is already in use. Close other applications using this port."
        }
    }
}
