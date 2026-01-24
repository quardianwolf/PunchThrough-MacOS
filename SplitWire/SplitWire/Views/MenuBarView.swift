import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            // Status Section
            statusSection

            Divider()

            // Toggle Button
            toggleButton

            Divider()

            // Method Selection
            methodSection

            Divider()

            // Actions
            actionsSection
        }
    }

    // MARK: - Status Section
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                StatusIndicator(status: appState.connectionStatus)
                Text(appState.statusText)
                    .font(.headline)
            }

            if case .connected = appState.connectionStatus {
                Text("\(appState.selectedMethod.displayName) • \(appState.effectiveDNS)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Toggle Button
    private var toggleButton: some View {
        Button {
            toggleConnection()
        } label: {
            HStack {
                Image(systemName: appState.connectionStatus.isActive ? "stop.fill" : "play.fill")
                Text(appState.connectionStatus.isActive ?
                     String(localized: "Disconnect") :
                     String(localized: "Connect"))
            }
        }
        .keyboardShortcut("t", modifiers: .command)
        .disabled(!appState.connectionStatus.canToggle)
    }

    // MARK: - Method Section
    private var methodSection: some View {
        Menu {
            ForEach(BypassMethod.allCases) { method in
                Button {
                    appState.selectedMethod = method
                } label: {
                    HStack {
                        Text(method.displayName)
                        if appState.selectedMethod == method {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(String(localized: "Method:"))
                Text(appState.selectedMethod.displayName)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions Section
    private var actionsSection: some View {
        Group {
            Button {
                openSettings()
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text(String(localized: "Settings..."))
                }
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text(String(localized: "Quit SplitWire"))
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - Methods
    private func toggleConnection() {
        Task {
            await BypassService.shared.toggle(appState: appState)
        }
    }
}

#Preview {
    MenuBarView()
        .environment(AppState())
        .frame(width: 280)
}
