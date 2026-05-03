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
        .frame(width: 500, height: 350)
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

            Section {
                Picker(String(localized: "SpoofDPI Log Level"), selection: $state.logLevel) {
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
                        Text(String(localized: "Method"))
                        Spacer()
                        Text(appState.selectedMethod.displayName)
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

    var body: some View {
        @Bindable var state = appState

        Form {
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

                Text(String(localized: "System proxy will route traffic through SpoofDPI automatically."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "SpoofDPI Options"))
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

            Section {
                InstallationStatusView()
            } header: {
                Text(String(localized: "Installation Status"))
            }
        }
        .formStyle(.grouped)
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

// MARK: - Installation Status
struct InstallationStatusView: View {
    @State private var spoofDPIInstalled = false
    @State private var isChecking = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SpoofDPI")
                Spacer()
                if isChecking {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: spoofDPIInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(spoofDPIInstalled ? .green : .red)
                    Text(spoofDPIInstalled ? String(localized: "Installed") : String(localized: "Not Installed"))
                        .foregroundStyle(.secondary)
                }
            }

            if !spoofDPIInstalled && !isChecking {
                HStack {
                    Text("brew install spoofdpi")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install spoofdpi", forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            await checkInstallation()
        }
    }

    private func checkInstallation() async {
        isChecking = true
        spoofDPIInstalled = await BypassService.shared.checkSpoofDPIInstalled()
        isChecking = false
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
