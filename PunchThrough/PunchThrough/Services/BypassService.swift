import Foundation

/// Main service that orchestrates bypass operations
@MainActor
final class BypassService {
    static let shared = BypassService()

    private let spoofDPI = SpoofDPIService()

    private init() {}

    // MARK: - Public Methods

    func toggle(appState: AppState) async {
        switch appState.connectionStatus {
        case .connected:
            await disconnect(appState: appState)
        case .disconnected, .error:
            await connect(appState: appState)
        default:
            break
        }
    }

    func connect(appState: AppState) async {
        guard appState.connectionStatus.canToggle else { return }

        appState.connectionStatus = .connecting
        appState.addLog("Starting SpoofDPI...")

        // Try up to 2 times - first attempt sometimes fails during cold start
        for attempt in 1...2 {
            do {
                try await spoofDPI.start(
                    port: appState.spoofDPIPort,
                    dnsAddress: appState.effectiveDNS,
                    enableDoH: appState.enableDoH,
                    enableSystemProxy: appState.enableSystemProxy,
                    logLevel: appState.logLevel.rawValue,
                    appState: appState
                )

                appState.connectionStatus = .connected
                appState.addLog("Successfully connected via SpoofDPI")
                return

            } catch {
                if attempt == 1 {
                    appState.addLog("First attempt failed, retrying...", level: .warning)
                    try? await Task.sleep(for: .seconds(1))
                } else {
                    appState.connectionStatus = .error(error.localizedDescription)
                    appState.addLog("Connection failed: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    func disconnect(appState: AppState) async {
        guard appState.connectionStatus.canToggle else { return }

        appState.connectionStatus = .disconnecting
        appState.addLog("Stopping bypass...")

        await spoofDPI.stop(appState: appState)

        appState.connectionStatus = .disconnected
        appState.addLog("Disconnected successfully")
    }

    // MARK: - Installation Checks

    func checkSpoofDPIInstalled() async -> Bool {
        // Bundled binary always available, but keep fallback check for sanity
        if Bundle.main.path(forResource: "spoofdpi", ofType: nil) != nil {
            return true
        }
        let paths = [
            "/opt/homebrew/bin/spoofdpi",
            "/usr/local/bin/spoofdpi"
        ]
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
