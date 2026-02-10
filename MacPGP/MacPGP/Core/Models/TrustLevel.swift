import Foundation

enum TrustLevel: String, Codable, CaseIterable, Identifiable {
    case unknown = "Unknown"
    case never = "Never"
    case marginal = "Marginal"
    case full = "Full"
    case ultimate = "Ultimate"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .never: return "Never"
        case .marginal: return "Marginal"
        case .full: return "Full"
        case .ultimate: return "Ultimate"
        }
    }

    var description: String {
        switch self {
        case .unknown: return "Trust level not yet determined"
        case .never: return "Never trust this key"
        case .marginal: return "Marginally trusted"
        case .full: return "Fully trusted"
        case .ultimate: return "Ultimate trust (own key)"
        }
    }

    var trustValue: Int {
        switch self {
        case .never: return 0
        case .unknown: return 1
        case .marginal: return 2
        case .full: return 3
        case .ultimate: return 4
        }
    }

    var canCertify: Bool {
        switch self {
        case .full, .ultimate: return true
        case .unknown, .never, .marginal: return false
        }
    }

    var requiresValidation: Bool {
        switch self {
        case .unknown, .marginal: return true
        case .never, .full, .ultimate: return false
        }
    }
}
