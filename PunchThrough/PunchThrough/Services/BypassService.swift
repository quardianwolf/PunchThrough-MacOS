import Foundation

/// Main service that orchestrates bypass operations.
/// Dispatches to the engine selected in AppState (SpoofDPI or tpws/zapret).
@MainActor
final class BypassService {
    static let shared = BypassService()

    private let spoofDPI = SpoofDPIService()
    let tpws = TpwsService()
    private let tunnel = TunnelService()
    private weak var tunnelAppState: AppState?

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

        switch appState.bypassEngine {
        case .spoofDPI:
            await connectSpoofDPI(appState: appState)
        case .tpws:
            await connectTpws(appState: appState)
        }

        // The tunnel is an extra: its failure is reported but does not take the bypass down
        if case .connected = appState.connectionStatus {
            await startTunnel(appState: appState)
        }
    }

    func disconnect(appState: AppState) async {
        guard appState.connectionStatus.canToggle else { return }

        appState.connectionStatus = .disconnecting
        appState.addLog("Stopping bypass...")

        await tunnel.stop()
        appState.tunnelActive = false
        appState.tunnelStatusText = ""

        // Stop whichever engine could be running. Cheap to call both.
        await spoofDPI.stop(appState: appState)
        if await tpws.isInstalled() {
            await tpws.stop(appState: appState)
        }

        appState.connectionStatus = .disconnected
        appState.addLog("Disconnected successfully")
    }

    // MARK: - SSH tunnel

    /// Apply changed tunnel settings without restarting the DPI bypass.
    func restartTunnel(appState: AppState) async {
        guard case .connected = appState.connectionStatus else { return }
        await startTunnel(appState: appState)
    }

    private func startTunnel(appState: AppState) async {
        guard appState.tunnelMode != .off else {
            await tunnel.stop()
            appState.tunnelActive = false
            appState.tunnelStatusText = ""
            return
        }

        tunnelAppState = appState
        await tunnel.setHandlers(
            onLog: { [weak self] message, level in
                Task { @MainActor in self?.tunnelAppState?.addLog(message, level: level) }
            },
            onLost: { [weak self] reason in
                Task { @MainActor in
                    guard let state = self?.tunnelAppState else { return }
                    state.tunnelActive = false
                    state.tunnelStatusText = String(localized: "Failed: \(reason)")
                    state.addLog("Tunnel lost and could not reconnect: \(reason)", level: .error)
                }
            })

        appState.tunnelActive = false
        appState.tunnelStatusText = String(localized: "Connecting...")
        appState.addLog("Opening tunnel to \(appState.tunnelHost)...")

        do {
            try await tunnel.start(config: appState.tunnelConfig)

            var summary = appState.tunnelMode.displayName
            if let exit = try? await tunnel.queryExit() {
                summary += " — \(exit.ip) (\(exit.country))"
            }
            appState.tunnelActive = true
            appState.tunnelStatusText = summary
            appState.addLog("Tunnel active — \(summary)")
        } catch {
            appState.tunnelActive = false
            appState.tunnelStatusText = String(localized: "Failed: \(error.localizedDescription)")
            appState.addLog("Tunnel failed: \(error.localizedDescription)", level: .error)
        }
    }

    // MARK: - SpoofDPI engine

    private func connectSpoofDPI(appState: AppState) async {
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
                    bypassMode: appState.bypassMode.rawValue,
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

    // MARK: - tpws (zapret) engine

    private func connectTpws(appState: AppState) async {
        // tpws uses PF redirect, not system proxy. Make sure SpoofDPI's proxy state
        // isn't lingering from a previous SpoofDPI session.
        appState.connectionStatus = .connecting
        appState.addLog("Starting Zapret (tpws)...")

        if !(await tpws.isInstalled()) {
            appState.connectionStatus = .error("Zapret service not installed")
            appState.addLog("Zapret service is not installed. Go to Settings → Bypass → Install Zapret Service.", level: .error)
            return
        }

        do {
            try await tpws.start(appState: appState)
            appState.connectionStatus = .connected
            appState.addLog("Successfully connected via Zapret")
        } catch {
            appState.connectionStatus = .error(error.localizedDescription)
            appState.addLog("Zapret start failed: \(error.localizedDescription)", level: .error)
        }
    }

    // MARK: - Installation Checks

    func checkSpoofDPIInstalled() async -> Bool {
        if Bundle.main.path(forResource: "spoofdpi", ofType: nil) != nil {
            return true
        }
        let paths = [
            "/opt/homebrew/bin/spoofdpi",
            "/usr/local/bin/spoofdpi"
        ]
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func checkTpwsInstalled() async -> Bool {
        await tpws.isInstalled()
    }
}
