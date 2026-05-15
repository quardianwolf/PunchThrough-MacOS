import Foundation

enum DNSServer: String, CaseIterable, Identifiable {
    case google = "Google"
    case cloudflare = "Cloudflare"
    case quad9 = "Quad9"
    case custom = "Custom"

    var id: String { rawValue }

    var address: String {
        switch self {
        case .google:
            return "8.8.8.8"
        case .cloudflare:
            return "1.1.1.1"
        case .quad9:
            return "9.9.9.9"
        case .custom:
            return ""
        }
    }

    var displayName: String {
        switch self {
        case .google:
            return "Google (8.8.8.8)"
        case .cloudflare:
            return "Cloudflare (1.1.1.1)"
        case .quad9:
            return "Quad9 (9.9.9.9)"
        case .custom:
            return String(localized: "Custom")
        }
    }
}
