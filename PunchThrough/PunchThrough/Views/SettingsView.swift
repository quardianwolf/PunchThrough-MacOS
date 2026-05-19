import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label(String(localized: "General"), systemImage: "gear")
                }

            BypassSettingsView()
                .tabItem {
                    Label(String(localized: "Bypass"), systemImage: "network.badge.shield.half.filled")
                }

            LogsView()
                .tabItem {
                    Label(String(localized: "Logs"), systemImage: "doc.text")
                }
        }
        .environment(appState)
        .frame(minWidth: 600, minHeight: 420)
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var launchAtLogin = false

    var body: some View {
        @Bindable var state = appState

        Form {
            Section {
                Toggle(String(localized: "Launch at Login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                Toggle(String(localized: "Auto-connect on launch"), isOn: $state.autoConnect)
            } header: {
                Text(String(localized: "Startup"))
            }

            Section {
                Picker(String(localized: "Language"), selection: $state.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .onChange(of: appState.appLanguage) { _, newValue in
                    newValue.apply()
                    appState.addLog("Language changed. Restart app to apply.", level: .info)
                }

                Text(String(localized: "Restart the app to apply language changes."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Language"))
            }

            if appState.bypassEngine == .spoofDPI {
                Section {
                    Picker(String(localized: "Log Level"), selection: $state.logLevel) {
                        ForEach(LogLevelOption.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    Text(String(localized: "Use Debug to troubleshoot connection issues."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(String(localized: "Logging"))
                }
            }

            Section {
                HStack {
                    Text(String(localized: "Status"))
                    Spacer()
                    StatusIndicator(status: appState.connectionStatus)
                    Text(appState.statusText)
                        .foregroundStyle(.secondary)
                }

                if case .connected = appState.connectionStatus {
                    HStack {
                        Text(String(localized: "Engine"))
                        Spacer()
                        Text(appState.bypassEngine.displayName)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text(String(localized: "DNS"))
                        Spacer()
                        Text(appState.effectiveDNS)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(String(localized: "Connection"))
            }

            Section {
                HStack {
                    Text("PunchThrough for macOS")
                    Spacer()
                    Text("v1.0.0")
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://github.com/quardianwolf/PunchThrough-MacOS")!) {
                    HStack {
                        Text(String(localized: "GitHub Repository"))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(String(localized: "About"))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            appState.launchAtLogin = enabled
        } catch {
            appState.addLog("Failed to set launch at login: \(error.localizedDescription)", level: .error)
        }
    }
}

// MARK: - Bypass Settings
struct BypassSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var portReconnectTask: Task<Void, Never>?
    @State private var tpwsInstalled: Bool = false
    @State private var tpwsBusy: Bool = false

    var body: some View {
        @Bindable var state = appState

        Form {
            // MARK: Engine
            Section {
                Picker(String(localized: "Engine"), selection: $state.bypassEngine) {
                    ForEach(BypassEngineOption.allCases) { eng in
                        Text(eng.displayName).tag(eng)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appState.bypassEngine) { _, _ in
                    scheduleReconnectIfNeeded()
                }

                Text(engineDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if appState.bypassEngine == .tpws {
                    HStack {
                        Image(systemName: tpwsInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(tpwsInstalled ? .green : .orange)
                        Text(tpwsInstalled
                             ? String(localized: "Zapret service installed")
                             : String(localized: "Zapret service not installed"))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Spacer()
                        if tpwsBusy {
                            ProgressView().scaleEffect(0.6)
                        } else if !tpwsInstalled {
                            Button(String(localized: "Install Service")) {
                                installZapret()
                            }
                            .controlSize(.small)
                        } else {
                            Button(String(localized: "Uninstall")) {
                                uninstallZapret()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text(String(localized: "Bypass Engine"))
            }

            // MARK: Mode (SpoofDPI only)
            if appState.bypassEngine == .spoofDPI {
                Section {
                    Picker(String(localized: "Mode"), selection: $state.bypassMode) {
                        ForEach(BypassModeOption.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appState.bypassMode) { _, _ in
                        scheduleReconnectIfNeeded()
                    }

                    Text(modeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(String(localized: "Bypass Mode"))
                }
            }

            Section {
                Picker(String(localized: "DNS Server"), selection: $state.dnsServer) {
                    ForEach(DNSServer.allCases) { server in
                        Text(server.displayName).tag(server)
                    }
                }

                if appState.dnsServer == .custom {
                    TextField(String(localized: "Custom DNS"), text: $state.customDNS)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle(String(localized: "Use DNS over HTTPS (DoH)"), isOn: $state.enableDoH)
            } header: {
                Text(String(localized: "DNS"))
            }

            if appState.bypassEngine == .spoofDPI {
                Section {
                    HStack {
                        Text(String(localized: "Port"))
                        Spacer()
                        TextField("", value: $state.spoofDPIPort, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: appState.spoofDPIPort) { _, _ in
                                scheduleReconnectIfNeeded()
                            }
                    }

                    Text(String(localized: "Valid range: 1024–65535"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(String(localized: "Configure System Proxy"), isOn: $state.enableSystemProxy)

                    Text(String(localized: "System proxy will route traffic through the bypass engine automatically."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(String(localized: "Proxy Options"))
                }

                Section {
                    Button {
                        openSpoofDPIConfigFolder()
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text(String(localized: "Open SpoofDPI Config Folder"))
                        }
                    }
                    Text(String(localized: "For advanced users. Edit ~/.config/spoofdpi/spoofdpi.toml to customize SpoofDPI behavior. CLI flags from this app override TOML values."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(String(localized: "Advanced"))
                }
            }

        }
        .formStyle(.grouped)
        .task { refreshTpwsStatus() }
    }

    /// Open ~/.config/spoofdpi/ in Finder. Creates the folder + sample TOML if missing.
    private func openSpoofDPIConfigFolder() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/spoofdpi", isDirectory: true)
        let configFile = configDir.appendingPathComponent("spoofdpi.toml")

        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: configFile.path) {
                let sample = """
                # SpoofDPI advanced configuration
                # See: https://spoofdpi.xvzc.dev
                # NOTE: CLI flags from PunchThrough override values set here.

                # log-level = "info"  # debug | info | warn | error

                # [https]
                # disorder = true
                # chunk-size = 35
                # fake-count = 0
                # split-mode = "sni"  # sni | random | chunk | custom | none
                """
                try sample.write(to: configFile, atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.open(configDir)
        } catch {
            appState.addLog("Failed to open config folder: \(error.localizedDescription)", level: .error)
        }
    }

    /// Localized helper text for the currently selected engine.
    private var engineDescription: String {
        switch appState.bypassEngine {
        case .spoofDPI:
            return String(localized: "Userspace HTTP proxy. No admin needed. May break apps with strict TLS (e.g. Discord desktop updater).")
        case .tpws:
            return String(localized: "Transparent TCP proxy via Zapret. Needs one-time admin install. Better app compatibility (Discord updater works).")
        }
    }

    private func refreshTpwsStatus() {
        Task {
            tpwsInstalled = await BypassService.shared.checkTpwsInstalled()
        }
    }

    private func installZapret() {
        tpwsBusy = true
        Task {
            defer { tpwsBusy = false }
            do {
                try await BypassService.shared.tpws.install()
                appState.addLog("Zapret service installed.", level: .info)
            } catch {
                appState.addLog("Install failed: \(error.localizedDescription)", level: .error)
            }
            refreshTpwsStatus()
        }
    }

    private func uninstallZapret() {
        tpwsBusy = true
        Task {
            defer { tpwsBusy = false }
            do {
                try await BypassService.shared.tpws.uninstall()
                appState.addLog("Zapret service uninstalled.", level: .info)
            } catch {
                appState.addLog("Uninstall failed: \(error.localizedDescription)", level: .error)
            }
            refreshTpwsStatus()
        }
    }

    /// Localized helper text for the currently selected bypass mode.
    private var modeDescription: String {
        switch appState.bypassMode {
        case .aggressive:
            return String(localized: "Maximum bypass strength. Required for strict DPI (Turkey). May break some apps' built-in updaters.")
        case .compatible:
            return String(localized: "Lighter fragmentation using SpoofDPI defaults. Better app compatibility (e.g. Discord updater) but may fail against strict DPI.")
        }
    }

    /// Debounced reconnect: wait 1.5s after the last edit, then reconnect if currently active.
    private func scheduleReconnectIfNeeded() {
        portReconnectTask?.cancel()
        portReconnectTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            if case .connected = appState.connectionStatus {
                appState.addLog("Port changed, reconnecting...", level: .info)
                await BypassService.shared.disconnect(appState: appState)
                await BypassService.shared.connect(appState: appState)
            }
        }
    }
}


// MARK: - Logs View
struct LogsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            if appState.logs.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Logs"), systemImage: "doc.text")
                } description: {
                    Text(String(localized: "Connection logs will appear here."))
                }
            } else {
                List(appState.logs.reversed()) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: entry.level.icon)
                            .foregroundStyle(entry.level.color)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message)
                                .font(.caption.monospaced())

                            Text(entry.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                Text("\(appState.logs.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(String(localized: "Clear Logs")) {
                    appState.clearLogs()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
