import SwiftUI

struct StatusIndicator: View {
    let status: ConnectionStatus
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
            .overlay {
                if shouldAnimate {
                    Circle()
                        .stroke(statusColor.opacity(0.5), lineWidth: 2)
                        .scaleEffect(isAnimating ? 2 : 1)
                        .opacity(isAnimating ? 0 : 1)
                }
            }
            .onChange(of: status) { _, newStatus in
                updateAnimation(for: newStatus)
            }
            .onAppear {
                updateAnimation(for: status)
            }
    }

    private var statusColor: Color {
        switch status {
        case .connected:
            return .green
        case .connecting, .disconnecting:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }

    private var shouldAnimate: Bool {
        switch status {
        case .connecting, .disconnecting:
            return true
        default:
            return false
        }
    }

    private func updateAnimation(for status: ConnectionStatus) {
        if shouldAnimate {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        } else {
            isAnimating = false
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack {
            StatusIndicator(status: .connected)
            Text("Connected")
        }
        HStack {
            StatusIndicator(status: .connecting)
            Text("Connecting")
        }
        HStack {
            StatusIndicator(status: .disconnected)
            Text("Disconnected")
        }
        HStack {
            StatusIndicator(status: .error("Test"))
            Text("Error")
        }
    }
    .padding()
}
