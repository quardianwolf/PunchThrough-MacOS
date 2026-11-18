import SwiftUI
import AppKit

/// Guided setup for the SSH tunnel: every step shows what to do and whether it worked.
struct TunnelSettingsView: View {
    @Environment(AppState.self) private var appState

    // Edited locally; written to AppState on "Save & apply"
    @State private var host = ""
    @State private var port = "22"
    @State private var user = ""
    @State private var keyPath = ""
    @State private var mode: TunnelMode = .off
    @State private var domains: [String] = []
    @State private var newDomain = ""
    @State private var selectedDomain: String?

    @State private var testing = false
    @State private var applying = false
    @State private var checks: [TunnelCheckRow.Kind: TunnelCheckRow.State] = [:]
    @State private var status = ""
    @State private var statusIsError = false

    private static let guideURL = URL(string: "https://github.com/quardianwolf/PunchThrough-MacOS#tunnel-open-sites-that-block-your-country")!

    var body: some View {
        Form {
            Section {
                Text(String(localized: "Open sites that block your country by sending them through a server you control. Any Linux server with SSH access works (for example a free Oracle Cloud VM). Nothing has to be installed on the server."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link(String(localized: "Step-by-step guide: getting a server"), destination: Self.guideURL)
                    .font(.caption)
            }

            Section {
                TunnelCheckRow(
                    state: TunnelService.isClientInstalled ? .ok : .failed,
                    text: TunnelService.isClientInstalled
                        ? String(localized: "SSH client is installed")
                        : String(localized: "SSH client is not installed"))
            } header: {
                Text(String(localized: "1. SSH client"))
            }

            Section {
                HStack {
                    TextField(String(localized: "Address"), text: $host, prompt: Text(verbatim: "203.0.113.10"))
                        .autocorrectionDisabled()
                    TextField(String(localized: "Port"), text: $port)
                        .frame(width: 110)
                }
                TextField(String(localized: "User"), text: $user, prompt: Text(verbatim: "ubuntu"))
                    .autocorrectionDisabled()
                HStack {
                    TextField(String(localized: "Private key"), text: $keyPath, prompt: Text(verbatim: "~/Downloads/ssh-key.key"))
                        .autocorrectionDisabled()
                    Button(String(localized: "Choose...")) { chooseKey() }
                }
            } header: {
                Text(String(localized: "2. Your server"))
            }

            Section {
                HStack {
                    Button(testing ? String(localized: "Testing...") : String(localized: "Test connection")) {
                        runTest()
                    }
                    .disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                }
                TunnelCheckRow(state: checks[.reach] ?? .pending,
                               text: checks[.reach]?.text ?? String(localized: "Server reachable"))
                TunnelCheckRow(state: checks[.login] ?? .pending,
                               text: checks[.login]?.text ?? String(localized: "Login with your key"))
                TunnelCheckRow(state: checks[.exit] ?? .pending,
                               text: checks[.exit]?.text ?? String(localized: "Traffic exits from the server"))
            } header: {
                Text(String(localized: "3. Test the connection"))
            }

            Section {
                Picker(String(localized: "Mode"), selection: $mode) {
                    ForEach(TunnelMode.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Text(mode.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if mode == .selectedSites {
                    List(domains, id: \.self, selection: $selectedDomain) { domain in
                        Text(domain).font(.body.monospaced())
                    }
                    .frame(height: 96)

                    HStack {
                        TextField(String(localized: "Site"), text: $newDomain, prompt: Text(verbatim: "example.com"))
                            .autocorrectionDisabled()
                            .onSubmit { addDomain() }
                        Button("+") { addDomain() }
                        Button("−") { removeDomain() }
                            .disabled(selectedDomain == nil)
                    }

                    Text(String(localized: "Subdomains are included. If a page loads without images or styles, the site uses another domain for them — add that one too."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button(String(localized: "Save & apply")) { apply() }
                        .disabled(applying)
                    if applying { ProgressView().controlSize(.small) }
                }
                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(String(localized: "4. What goes through the tunnel"))
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    // MARK: - Form state

    private func load() {
        host = appState.tunnelHost
        port = String(appState.tunnelPort)
        user = appState.tunnelUser
        keyPath = appState.tunnelKeyPath
        mode = appState.tunnelMode
        domains = appState.tunnelDomains
    }

    /// The server details as currently typed (not necessarily saved yet).
    private var formConfig: TunnelConfig {
        var config = appState.tunnelConfig
        config.mode = mode
        config.host = host.trimmingCharacters(in: .whitespaces)
        config.port = Int(port.trimmingCharacters(in: .whitespaces)) ?? 0
        config.user = user.trimmingCharacters(in: .whitespaces)
        config.keyPath = keyPath.trimmingCharacters(in: .whitespaces)
        config.domains = domains
        return config
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true // keys usually live in ~/.ssh
        panel.message = String(localized: "Choose your private key file")
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if FileManager.default.fileExists(atPath: sshDir.path) { panel.directoryURL = sshDir }

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            keyPath = url.path
        }
    }

    private func setStatus(_ text: String, error: Bool = false) {
        status = text
        statusIsError = error
    }

    // MARK: - Sites

    private func addDomain() {
        guard !newDomain.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let domain = DomainUtil.normalize(newDomain) else {
            setStatus(String(localized: "That does not look like a domain (example: example.com)"), error: true)
            return
        }
        newDomain = ""
        setStatus("")
        if !domains.contains(domain) { domains.append(domain) }
    }

    private func removeDomain() {
        guard let selectedDomain else { return }
        domains.removeAll { $0 == selectedDomain }
        self.selectedDomain = nil
    }

    // MARK: - Actions

    private func runTest() {
        testing = true
        checks = [:]
        let config = formConfig
        Task {
            _ = await TunnelService.test(config: config) { check, ok, text in
                let state: TunnelCheckRow.State = ok ? .passed(text) : .failed(text)
                switch check {
                case .client: break // shown live in step 1
                case .reach: checks[.reach] = state
                case .login: checks[.login] = state
                case .exit: checks[.exit] = state
                }
            }
            testing = false
        }
    }

    private func apply() {
        addDomain() // a site still sitting in the input box is clearly meant to be included
        let config = formConfig

        if config.mode != .off {
            if let problem = config.validate() {
                setStatus(problem, error: true)
                return
            }
            if config.mode == .selectedSites && domains.isEmpty {
                setStatus(String(localized: "Add at least one site first"), error: true)
                return
            }
        }

        appState.tunnelHost = config.host
        appState.tunnelPort = (1...65535).contains(config.port) ? config.port : 22
        appState.tunnelUser = config.user
        appState.tunnelKeyPath = config.keyPath
        appState.tunnelDomains = domains
        appState.tunnelMode = config.mode

        guard case .connected = appState.connectionStatus else {
            setStatus(String(localized: "Saved. The tunnel starts when you connect."))
            return
        }

        applying = true
        setStatus(String(localized: "Saved. The tunnel is being applied."))
        Task {
            await BypassService.shared.restartTunnel(appState: appState)
            applying = false
            if config.mode == .off {
                setStatus(String(localized: "The tunnel is not used."))
            } else {
                setStatus(appState.tunnelStatusText, error: !appState.tunnelActive)
            }
        }
    }
}

/// One line of the checklist: a mark and what it means.
struct TunnelCheckRow: View {
    enum Kind: Hashable { case reach, login, exit }

    enum State {
        case pending
        case ok
        case passed(String)
        case failed(String)

        static var failed: State { .failed("") }

        var text: String? {
            switch self {
            case .passed(let text), .failed(let text): return text.isEmpty ? nil : text
            default: return nil
            }
        }
    }

    let state: State
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(.callout)
                .foregroundStyle(isPending ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var isPending: Bool {
        if case .pending = state { return true }
        return false
    }

    private var icon: String {
        switch state {
        case .pending: return "circle"
        case .ok, .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .pending: return .secondary
        case .ok, .passed: return .green
        case .failed: return .red
        }
    }
}
