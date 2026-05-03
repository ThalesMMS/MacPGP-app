import Foundation

/// Shared UI state types for Encrypt/Decrypt screens.
///
/// Keep these minimal: they should model workflow state, not SwiftUI presentation details.

enum CryptoOperationStatus: Equatable {
    case idle
    case running
    case succeeded
    case failed(message: String)
    case cancelled
}

enum CryptoInputMode: Equatable {
    case text
    case files
}
