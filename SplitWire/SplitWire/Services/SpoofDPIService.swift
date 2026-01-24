import Foundation

/// Service for managing SpoofDPI process
actor SpoofDPIService {
    private var currentProcess: Process?

    // Log file on desktop
    private let logFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/splitwire_debug.log")

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
        appState: AppState
    ) async throws {
        log("=== START ATTEMPT ===")

        // Find SpoofDPI binary
        let possiblePaths = [
            "/opt/homebrew/bin/spoofdpi",
            "/usr/local/bin/spoofdpi",
        ]

        log("Checking paths: \(possiblePaths)")

        var spoofDPIPath: String?
        for path in possiblePaths {
            let exists = FileManager.default.fileExists(atPath: path)
            let executable = FileManager.default.isExecutableFile(atPath: path)
            log("Path \(path): exists=\(exists), executable=\(executable)")
            if executable {
                spoofDPIPath = path
                break
            }
        }

        guard let binaryPath = spoofDPIPath else {
            log("ERROR: SpoofDPI not found!")
            throw SpoofDPIError.notInstalled
        }

        log("Found spoofdpi at: \(binaryPath)")

        // Stop existing process and kill all spoofdpi instances (but don't disable proxy yet)
        await stop(appState: appState, disableProxy: false)

        // Extra aggressive cleanup
        await killAllSpoofDPI()

        // Check if port is in use
        if isPortInUse(port) {
            log("ERROR: Port \(port) is still in use after cleanup!")
            throw SpoofDPIError.portInUse(port)
        }

        // Build arguments - Turkish ISP bypass settings
        var arguments: [String] = [
            "--listen-addr", "127.0.0.1:\(port)",
            "--dns-addr", "\(dnsAddress):53",
            "--https-disorder",
            "--https-chunk-size", "1"
        ]

        if enableDoH {
            arguments.append(contentsOf: ["--dns-mode", "https"])
        }

        let fullCommand = "\(binaryPath) \(arguments.joined(separator: " "))"
        log("Full command: \(fullCommand)")

        // Method 1: Try direct execution
        log("Trying direct Process execution...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments

        // Redirect output to files for debugging
        let stdoutFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/spoofdpi_stdout.log")
        let stderrFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/spoofdpi_stderr.log")

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
        } catch let error {
            log("process.run() FAILED: \(error.localizedDescription)")
            log("Error details: \(error)")
            throw SpoofDPIError.failedToStart
        }

        // Wait for process to initialize
        log("Waiting 1 second for process to initialize...")
        try await Task.sleep(for: .seconds(1))

        // Check if still running
        let isRunning = process.isRunning
        log("After 1 second - isRunning: \(isRunning)")

        if !isRunning {
            let exitCode = process.terminationStatus
            log("Process exited with code: \(exitCode)")

            // Read stderr for error details
            if let stderrContent = try? String(contentsOf: stderrFile, encoding: .utf8) {
                log("STDERR content: \(stderrContent)")
            }
            if let stdoutContent = try? String(contentsOf: stdoutFile, encoding: .utf8) {
                log("STDOUT content: \(stdoutContent)")
            }

            throw SpoofDPIError.failedToStart
        }

        log("SUCCESS! SpoofDPI is running on port \(port)")

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
