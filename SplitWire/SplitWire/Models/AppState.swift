import Foundation
import SwiftUI

@Observable
final class AppState {
    // MARK: - Connection State
    var connectionStatus: ConnectionStatus = .disconnected
    var isProcessing: Bool = false

    // MARK: - Configuration
    var selectedMethod: BypassMethod = .spoofDPI
    var dnsServer: DNSServer = .google
    var customDNS: String = ""
    var spoofDPIPort: Int = 8080
    var enableDoH: Bool = true
    var enableSystemProxy: Bool = true
    var launchAtLogin: Bool = false

    // MARK: - Logs
    var logs: [LogEntry] = []

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
