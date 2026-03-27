import Foundation

enum ConnectionStatus: Equatable {
    case connected
    case connecting
    case disconnecting
    case disconnected
    case error(String)

    var isActive: Bool {
        switch self {
        case .connected, .connecting:
            return true
        default:
            return false
        }
    }

    var canToggle: Bool {
        switch self {
        case .connected, .disconnected, .error:
            return true
        case .connecting, .disconnecting:
            return false
        }
    }
}
