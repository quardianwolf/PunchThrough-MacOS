import SwiftUI

@main
struct PunchThroughApp: App {
    @State private var appState = AppState()
    @State private var showSettings = false

    init() {
        // Auto-connect on launch if enabled (default ON for new installs)
        let state = AppState()
        if state.autoConnect {
            Task { @MainActor in
                // Slight delay to let the menu bar UI initialize before attempting connection
                try? await Task.sleep(for: .milliseconds(500))
                await BypassService.shared.connect(appState: state)
            }
        }
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(appState: appState, showSettings: $showSettings)
        } label: {
            Image(systemName: appState.statusIcon)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.menu)

        Window("PunchThrough Settings", id: "settings") {
            SettingsView()
                .environment(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 640, height: 480)
        .windowResizability(.contentMinSize)
    }
}

struct MenuBarContent: View {
    let appState: AppState
    @Binding var showSettings: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status Section
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(appState.statusColor)
                    .frame(width: 8, height: 8)
                Text(appState.statusText)
            }
            if case .connected = appState.connectionStatus {
                Text("\(appState.bypassEngine.displayName) • \(appState.effectiveDNS)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)

        Divider()

        // Connect/Disconnect Button
        Button {
            Task {
                await BypassService.shared.toggle(appState: appState)
            }
        } label: {
            if appState.connectionStatus.isActive {
                Label("Disconnect", systemImage: "stop.fill")
            } else {
                Label("Connect", systemImage: "play.fill")
            }
        }
        .disabled(!appState.connectionStatus.canToggle)

        Divider()

        // Settings Button
        Button {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Settings...", systemImage: "gear")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        // Quit Button
        Button("Quit PunchThrough") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
