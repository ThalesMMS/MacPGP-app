import SwiftUI

extension TrustLevel {
    var accessibilityToken: String {
        switch self {
        case .unknown: return "Unknown"
        case .never: return "Never"
        case .marginal: return "Marginal"
        case .full: return "Full"
        case .ultimate: return "Ultimate"
        }
    }

    var iconName: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .never: return "xmark.shield"
        case .marginal: return "shield.lefthalf.filled"
        case .full: return "shield"
        case .ultimate: return "crown.fill"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return .gray
        case .never: return .red
        case .marginal: return .orange
        case .full: return .green
        case .ultimate: return .purple
        }
    }
}
