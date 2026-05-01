import Foundation
import SwiftUI

@Observable
final class AppState {
    // MARK: - Connection State
    var connectionStatus: ConnectionStatus = .disconnected
    var isProcessing: Bool = false

    // MARK: - Configuration (persisted to UserDefaults)
    var selectedMethod: BypassMethod = .spoofDPI
    var dnsServer: DNSServer {
        didSet { UserDefaults.standard.set(dnsServer.rawValue, forKey: Keys.dnsServer) }
    }
    var customDNS: String {
        didSet { UserDefaults.standard.set(customDNS, forKey: Keys.customDNS) }
    }
    var spoofDPIPort: Int {
        didSet {
            // Clamp to valid user-port range (avoid privileged 0-1023 and out-of-range)
            let clamped = max(1024, min(65535, spoofDPIPort))
            if clamped != spoofDPIPort {
                spoofDPIPort = clamped
                return // didSet will fire again with the clamped value
            }
            UserDefaults.standard.set(spoofDPIPort, forKey: Keys.spoofDPIPort)
        }
    }
    var enableDoH: Bool {
        didSet { UserDefaults.standard.set(enableDoH, forKey: Keys.enableDoH) }
    }
    var enableSystemProxy: Bool {
        didSet { UserDefaults.standard.set(enableSystemProxy, forKey: Keys.enableSystemProxy) }
    }
    var autoConnect: Bool {
        didSet { UserDefaults.standard.set(autoConnect, forKey: Keys.autoConnect) }
    }
    var launchAtLogin: Bool = false
    var appLanguage: AppLanguage = AppLanguage.current()

    // MARK: - Logs
    var logs: [LogEntry] = []

    // MARK: - UserDefaults Keys
    private enum Keys {
        static let dnsServer = "dnsServer"
        static let customDNS = "customDNS"
        static let spoofDPIPort = "spoofDPIPort"
        static let enableDoH = "enableDoH"
        static let enableSystemProxy = "enableSystemProxy"
        static let autoConnect = "autoConnect"
    }

    // MARK: - Init (loads persisted settings)
    init() {
        let defaults = UserDefaults.standard

        // Default DNS to Quad9 if nothing saved (privacy-friendly default)
        if let saved = defaults.string(forKey: Keys.dnsServer),
           let server = DNSServer(rawValue: saved) {
            self.dnsServer = server
        } else {
            self.dnsServer = .quad9
        }

        self.customDNS = defaults.string(forKey: Keys.customDNS) ?? ""

        let savedPort = defaults.integer(forKey: Keys.spoofDPIPort)
        self.spoofDPIPort = savedPort > 0 ? savedPort : 8080

        self.enableDoH = defaults.object(forKey: Keys.enableDoH) as? Bool ?? true
        self.enableSystemProxy = defaults.object(forKey: Keys.enableSystemProxy) as? Bool ?? true

        // Default auto-connect to ON for new installs
        self.autoConnect = defaults.object(forKey: Keys.autoConnect) as? Bool ?? true
    }

    // MARK: - Computed Properties
    var statusIcon: String {
        switch connectionStatus {
        case .connected:
            return "network.badge.shield.half.filled"
        case .connecting, .disconnecting:
            return "network"
        case .disconnected:
            return "network.slash"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var statusColor: Color {
        switch connectionStatus {
        case .connected:
            return .green
        case .connecting, .disconnecting:
            return .orange
        case .disconnected:
            return .secondary
        case .error:
            return .red
        }
    }

    var statusText: String {
        switch connectionStatus {
        case .connected:
            return String(localized: "Connected")
        case .connecting:
            return String(localized: "Connecting...")
        case .disconnecting:
            return String(localized: "Disconnecting...")
        case .disconnected:
            return String(localized: "Disconnected")
        case .error(let message):
            return String(localized: "Error: \(message)")
        }
    }

    var effectiveDNS: String {
        switch dnsServer {
        case .google:
            return "8.8.8.8"
        case .cloudflare:
            return "1.1.1.1"
        case .quad9:
            return "9.9.9.9"
        case .custom:
            return customDNS.isEmpty ? "8.8.8.8" : customDNS
        }
    }

    // MARK: - Methods
    func addLog(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), message: message, level: level)
        logs.append(entry)

        // Keep only last 1000 entries
        if logs.count > 1000 {
            logs.removeFirst(logs.count - 1000)
        }
    }

    func clearLogs() {
        logs.removeAll()
    }
}

// MARK: - Log Entry
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let level: LogLevel
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case turkish = "tr"
    case french = "fr"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System Default")
        case .english: return "English"
        case .turkish: return "Türkçe"
        case .french: return "Français"
        }
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }

    static func current() -> AppLanguage {
        guard let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
              let first = languages.first else {
            return .system
        }
        return AppLanguage.allCases.first { $0.rawValue == first } ?? .system
    }
}

enum LogLevel {
    case info
    case warning
    case error
    case debug

    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .debug: return "ant"
        }
    }

    var color: Color {
        switch self {
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        case .debug: return .secondary
        }
    }
}
