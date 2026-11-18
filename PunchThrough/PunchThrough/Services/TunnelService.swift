import Foundation
import Network
import Darwin

// MARK: - Model

enum TunnelMode: String, CaseIterable, Identifiable {
    case off
    case selectedSites
    case allTraffic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return String(localized: "Off")
        case .selectedSites: return String(localized: "Selected sites only")
        case .allTraffic: return String(localized: "All browser traffic")
        }
    }

    var explanation: String {
        switch self {
        case .off:
            return String(localized: "The tunnel is not used.")
        case .selectedSites:
            return String(localized: "Only the sites below go through your server. Everything else stays on your normal connection.")
        case .allTraffic:
            return String(localized: "Browsers and other apps that follow the macOS proxy settings go through your server. Apps that ignore the system proxy are not covered.")
        }
    }
}

enum DomainUtil {
    /// Turn whatever the user pasted ("https://www.example.com/page", "*.example.com")
    /// into a bare domain. Returns nil when it is not a usable domain.
    static func normalize(_ input: String) -> String? {
        var d = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = d.range(of: "://") { d = String(d[scheme.upperBound...]) }
        if let end = d.firstIndex(where: { "/?#:".contains($0) }) { d = String(d[..<end]) }
        if d.hasPrefix("*.") { d.removeFirst(2) }
        if d.hasPrefix("www.") { d.removeFirst(4) }
        d = d.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let pattern = #"^[a-z0-9][a-z0-9-]*(\.[a-z0-9][a-z0-9-]*)+$"#
        return d.range(of: pattern, options: .regularExpression) != nil ? d : nil
    }
}

struct TunnelConfig: Sendable {
    var mode: TunnelMode
    var host: String
    var port: Int
    var user: String
    var keyPath: String
    var domains: [String]
    /// What the proxy script answers for everything that is NOT tunnelled.
    /// "DIRECT", or the local SpoofDPI proxy so the DPI bypass keeps working.
    var fallback: String = "DIRECT"

    var expandedKeyPath: String { (keyPath as NSString).expandingTildeInPath }

    /// Returns a user-facing problem description, or nil when the server details are usable.
    func validate() -> String? {
        // These values end up on the ssh command line, so anything that is not a plain
        // host / user name is rejected rather than quoted.
        if host.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:-]*$"#, options: .regularExpression) == nil {
            return String(localized: "Enter the server address (IP or host name)")
        }
        if !(1...65535).contains(port) {
            return String(localized: "Port must be between 1 and 65535")
        }
        if user.range(of: #"^[A-Za-z0-9_][A-Za-z0-9._-]*$"#, options: .regularExpression) == nil {
            return String(localized: "Enter the login user name (for example ubuntu or opc)")
        }

        let path = expandedKeyPath
        guard !keyPath.isEmpty, FileManager.default.isReadableFile(atPath: path),
              let handle = FileHandle(forReadingAtPath: path) else {
            return String(localized: "Choose your private key file")
        }
        defer { try? handle.close() }
        let head = String(data: handle.readData(ofLength: 64), encoding: .utf8) ?? ""
        if head.hasPrefix("PuTTY-User-Key-File") {
            return String(localized: "This is a PuTTY (.ppk) key. Convert it with PuTTYgen: Conversions > Export OpenSSH key")
        }
        if head.hasPrefix("ssh-") || head.hasPrefix("ecdsa-") {
            return String(localized: "This is the public key (.pub). Choose the private key file instead")
        }
        return nil
    }
}

enum TunnelCheck { case client, reach, login, exit }

enum TunnelError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

// MARK: - Service

/// A lightweight "VPN" built from things every Mac already has: the OpenSSH client opens
/// a SOCKS proxy through the user's own server (ssh -D), and a proxy auto-config script
/// tells browsers which sites should use it. Nothing needs to be installed on the server.
actor TunnelService {
    static let sshPath = "/usr/bin/ssh"

    private var ssh: Process?
    private var pacServer: PACServer?
    private var config: TunnelConfig?
    private var keyCopy = ""
    private var socksPort = 0
    /// Bumped on every start/stop so a late callback from an old ssh is ignored.
    private var generation = 0

    private var onLog: (@Sendable (String, LogLevel) -> Void)?
    private var onLost: (@Sendable (String) -> Void)?

    func setHandlers(onLog: @escaping @Sendable (String, LogLevel) -> Void,
                     onLost: @escaping @Sendable (String) -> Void) {
        self.onLog = onLog
        self.onLost = onLost
    }

    static var isClientInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: sshPath)
    }

    // MARK: Lifecycle

    /// Open the tunnel and point the system proxy script at it. Throws with a readable message.
    func start(config: TunnelConfig) async throws {
        await stop()

        if let problem = config.validate() { throw TunnelError.message(problem) }
        guard Self.isClientInstalled else {
            throw TunnelError.message(String(localized: "SSH client is not installed"))
        }

        let key = try Self.prepareKey(config.expandedKeyPath, name: "id_tunnel")
        let port = Self.freePort()
        let process = try await Self.launch(config: config, keyPath: key, socksPort: port)

        generation += 1
        self.config = config
        self.keyCopy = key
        self.socksPort = port
        adopt(process)

        do {
            let server = try PACServer(pac: Self.buildPAC(config: config, socksPort: port))
            pacServer = server
            // The query string defeats PAC caching when the site list changed
            try AutoProxy.set(url: "http://127.0.0.1:\(server.port)/proxy.pac?v=\(Int(Date().timeIntervalSince1970))")
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        generation += 1
        config = nil
        if let ssh {
            ssh.terminationHandler = nil
            if ssh.isRunning { ssh.terminate() }
        }
        ssh = nil
        TunnelRuntime.shared.pid = 0
        pacServer?.stop()
        pacServer = nil
        AutoProxy.restore()
    }

    var isRunning: Bool { ssh?.isRunning ?? false }

    /// Public IP and country the tunnel exits from.
    func queryExit() async throws -> (ip: String, country: String) {
        try await Self.queryExit(socksPort: socksPort)
    }

    private func adopt(_ process: Process) {
        ssh = process
        TunnelRuntime.shared.pid = process.processIdentifier
        let current = generation
        process.terminationHandler = { [weak self] _ in
            Task { await self?.handleExit(generation: current) }
        }
        // ssh may have died between the readiness check and installing the handler
        if !process.isRunning {
            Task { await self.handleExit(generation: current) }
        }
    }

    /// Restart ssh when it dies (server reboot, Wi-Fi change, sleep/wake).
    private func handleExit(generation exited: Int) async {
        guard exited == generation, let config, ssh?.isRunning != true else { return }
        onLog?("Tunnel connection dropped — reconnecting...", .warning)

        var lastError = ""
        for attempt in 1...6 {
            try? await Task.sleep(for: .seconds(min(3 * attempt, 15)))
            guard exited == generation else { return }
            do {
                let process = try await Self.launch(config: config, keyPath: keyCopy, socksPort: socksPort)
                guard exited == generation else {
                    process.terminate()
                    return
                }
                adopt(process)
                onLog?("Tunnel reconnected", .info)
                return
            } catch {
                lastError = error.localizedDescription
            }
        }

        // Take the proxy script away, otherwise the selected sites (or everything,
        // in all-traffic mode) would keep pointing at a dead local port.
        guard exited == generation else { return }
        await stop()
        onLost?(lastError)
    }

    // MARK: Guided connection test

    /// Walk through the checks in order and report each outcome, stopping at the first failure.
    /// Uses its own temporary tunnel, so it never disturbs a running one.
    static func test(config: TunnelConfig,
                     report: @escaping @MainActor (TunnelCheck, Bool, String) -> Void) async -> Bool {
        guard isClientInstalled else {
            await report(.client, false, String(localized: "SSH client is not installed"))
            return false
        }
        await report(.client, true, String(localized: "SSH client is installed"))

        if let problem = config.validate() {
            await report(.reach, false, problem)
            return false
        }

        let target = "\(config.host):\(config.port)"
        guard await canReach(host: config.host, port: config.port) else {
            await report(.reach, false, String(localized: "Cannot reach \(target). Check the address, and that the SSH port is open in the server firewall / cloud security rules"))
            return false
        }
        await report(.reach, true, String(localized: "Server \(target) is reachable"))

        let port = freePort()
        let process: Process
        do {
            let key = try prepareKey(config.expandedKeyPath, name: "id_test")
            process = try await launch(config: config, keyPath: key, socksPort: port)
        } catch {
            await report(.login, false, String(localized: "Login failed: \(error.localizedDescription)"))
            return false
        }
        defer { process.terminate() }
        await report(.login, true, String(localized: "Logged in as \(config.user)"))

        do {
            let exit = try await queryExit(socksPort: port)
            await report(.exit, true, String(localized: "Traffic exits from \(exit.ip) (\(exit.country))"))
            return true
        } catch {
            await report(.exit, false, String(localized: "Logged in, but the server could not forward traffic (\(error.localizedDescription)). Check AllowTcpForwarding in sshd_config and the server's outbound internet access"))
            return false
        }
    }

    // MARK: ssh process

    private static func launch(config: TunnelConfig, keyPath: String, socksPort: Int) async throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = [
            "-N", "-T",
            "-D", "127.0.0.1:\(socksPort)",
            "-p", String(config.port),
            "-i", keyPath,
            "-o", "BatchMode=yes",                    // never wait for a password prompt nobody can see
            "-o", "IdentitiesOnly=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StrictHostKeyChecking=accept-new", // trust on first use, refuse if the key later changes
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=20",
            "-o", "ServerAliveCountMax=3",
            "\(config.user)@\(config.host)"
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice

        let errors = ErrorBuffer()
        let pipe = Pipe()
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else if let text = String(data: data, encoding: .utf8) {
                errors.append(text)
            }
        }

        do {
            try process.run()
        } catch {
            throw TunnelError.message(error.localizedDescription)
        }

        // ssh opens the local SOCKS port only after it has authenticated,
        // so "the port accepts connections" means "we are logged in".
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if !process.isRunning {
                try? await Task.sleep(for: .milliseconds(200)) // let the last stderr lines arrive
                let message = errors.summary
                throw TunnelError.message(message.isEmpty
                    ? String(localized: "ssh exited with code \(String(process.terminationStatus))")
                    : message)
            }
            if canConnectLocal(port: socksPort) { return process }
            try? await Task.sleep(for: .milliseconds(300))
        }

        process.terminate()
        throw TunnelError.message(String(localized: "Timed out while logging in to the server"))
    }

    /// ssh refuses private keys that other accounts can read — the usual state of a key
    /// sitting in Downloads. Work on a private 0600 copy instead of asking the user to
    /// fix file permissions in Terminal. The original file is never modified.
    private static func prepareKey(_ source: String, name: String) throws -> String {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PunchThrough/tunnel", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let dest = dir.appendingPathComponent(name)
        try? fm.removeItem(at: dest)
        try fm.copyItem(atPath: source, toPath: dest.path)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
        return dest.path
    }

    // MARK: Proxy auto-config

    static func buildPAC(config: TunnelConfig, socksPort: Int) -> String {
        let proxy = "SOCKS5 127.0.0.1:\(socksPort); SOCKS 127.0.0.1:\(socksPort)"
        var lines = [
            "function FindProxyForURL(url, host) {",
            "  host = host.toLowerCase();",
            "  if (isPlainHostName(host) || host === 'localhost' || shExpMatch(host, '127.*') ||",
            "      shExpMatch(host, '10.*') || shExpMatch(host, '192.168.*') || shExpMatch(host, '169.254.*'))",
            "    return 'DIRECT';"
        ]

        if config.mode == .allTraffic {
            lines.append("  return '\(proxy)';")
        } else {
            var seen = Set<String>()
            let sites = config.domains.compactMap(DomainUtil.normalize).filter { seen.insert($0).inserted }
            lines += [
                "  var sites = [\(sites.map { "'\($0)'" }.joined(separator: ", "))];",
                "  for (var i = 0; i < sites.length; i++) {",
                "    if (host === sites[i] || dnsDomainIs(host, '.' + sites[i]))",
                "      return '\(proxy)';",
                "  }",
                "  return '\(config.fallback)';"
            ]
        }

        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Network helpers

    private static func queryExit(socksPort: Int) async throws -> (ip: String, country: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            "SOCKSEnable": 1,
            "SOCKSProxy": "127.0.0.1",
            "SOCKSPort": socksPort
        ]
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, _) = try await session.data(from: URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!)
        let text = String(data: data, encoding: .utf8) ?? ""

        func field(_ name: String) -> String {
            text.split(separator: "\n")
                .first { $0.hasPrefix(name + "=") }
                .map { String($0.dropFirst(name.count + 1)) } ?? "?"
        }
        return (field("ip"), field("loc"))
    }

    private static func canReach(host: String, port: Int) async -> Bool {
        await Task.detached {
            Shell.run("/usr/bin/nc", ["-z", "-G", "8", host, String(port)]).status == 0
        }.value
    }

    private static func canConnectLocal(port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    static func freePort() -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return 21080 }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)

        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, length) == 0 }
        }
        guard bound else { return 21080 }

        _ = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &length) }
        }
        return Int(in_port_t(bigEndian: addr.sin_port))
    }
}

// MARK: - Supporting pieces

/// The ssh pid, reachable synchronously so it can be stopped while the app is terminating.
final class TunnelRuntime: @unchecked Sendable {
    static let shared = TunnelRuntime()
    private let lock = NSLock()
    private var _pid: Int32 = 0

    var pid: Int32 {
        get { lock.lock(); defer { lock.unlock() }; return _pid }
        set { lock.lock(); _pid = newValue; lock.unlock() }
    }

    /// Blocking cleanup for applicationWillTerminate: no orphaned ssh, no dangling proxy script.
    static func emergencyCleanup() {
        let pid = shared.pid
        if pid > 0 { kill(pid, SIGTERM) }
        shared.pid = 0
        AutoProxy.restore()
    }
}

private final class ErrorBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("Warning: Permanently added") { continue }
            lines.append(trimmed)
        }
        if lines.count > 10 { lines.removeFirst(lines.count - 10) }
    }

    var summary: String {
        lock.lock(); defer { lock.unlock() }
        return lines.suffix(2).joined(separator: " ")
    }
}

enum Shell {
    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

/// Sets the macOS "Automatic Proxy Configuration" URL on every enabled network service and
/// restores the previous values afterwards. The previous values are persisted first, so a
/// crash never leaves browsers pointing at a dead local address.
enum AutoProxy {
    private static let backupKey = "tunnelAutoProxyBackup"
    private static let tool = "/usr/sbin/networksetup"

    static func services() -> [String] {
        Shell.run(tool, ["-listallnetworkservices"]).output
            .components(separatedBy: "\n")
            .dropFirst() // header line
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") } // "*" marks a disabled service
    }

    static func current(_ service: String) -> (url: String, enabled: Bool) {
        var url = ""
        var enabled = false
        for line in Shell.run(tool, ["-getautoproxyurl", service]).output.components(separatedBy: "\n") {
            if line.hasPrefix("URL: ") {
                let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                url = value == "(null)" ? "" : value
            } else if line.hasPrefix("Enabled: ") {
                enabled = line.contains("Yes")
            }
        }
        return (url, enabled)
    }

    static func set(url: String) throws {
        let all = services()
        guard !all.isEmpty else {
            throw TunnelError.message(String(localized: "No active network service found"))
        }

        var backup = UserDefaults.standard.dictionary(forKey: backupKey) as? [String: [String: String]] ?? [:]
        for service in all where backup[service] == nil { // keep the true original
            let state = current(service)
            backup[service] = ["url": state.url, "enabled": state.enabled ? "1" : "0"]
        }
        UserDefaults.standard.set(backup, forKey: backupKey)

        var applied = 0
        var failure = ""
        for service in all {
            let result = Shell.run(tool, ["-setautoproxyurl", service, url])
            if result.status == 0 && !result.output.contains("Error") {
                applied += 1
            } else {
                failure = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if applied == 0 {
            restore()
            throw TunnelError.message(String(localized: "Could not change the macOS proxy settings: \(failure)"))
        }
    }

    static func restore() {
        guard let backup = UserDefaults.standard.dictionary(forKey: backupKey) as? [String: [String: String]] else {
            return
        }
        for (service, state) in backup {
            let url = state["url"] ?? ""
            if state["enabled"] == "1", !url.isEmpty {
                Shell.run(tool, ["-setautoproxyurl", service, url])
            } else {
                // networksetup has no "clear" — a blank URL plus "off" is the untouched state
                Shell.run(tool, ["-setautoproxyurl", service, url.isEmpty ? " " : url])
                Shell.run(tool, ["-setautoproxystate", service, "off"])
            }
        }
        UserDefaults.standard.removeObject(forKey: backupKey)
    }

    /// Repair proxy settings left behind by a crashed run. True when a repair happened.
    @discardableResult
    static func recoverIfNeeded() -> Bool {
        guard UserDefaults.standard.object(forKey: backupKey) != nil else { return false }
        restore()
        return true
    }
}

/// Serves the proxy script on a loopback-only port. Browsers will not load a PAC from file://.
final class PACServer: @unchecked Sendable {
    let port: Int
    private let listener: NWListener
    private let queue = DispatchQueue(label: "punchthrough.pac")

    init(pac: String) throws {
        port = TunnelService.freePort()

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!)
        listener = try NWListener(using: parameters)

        let body = Data(pac.utf8)
        let response = Data(("HTTP/1.1 200 OK\r\n" +
            "Content-Type: application/x-ns-proxy-autoconfig\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Cache-Control: no-store\r\n" +
            "Connection: close\r\n\r\n").utf8) + body

        let queue = self.queue
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, _ in
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        listener.start(queue: queue)
    }

    func stop() { listener.cancel() }
}
