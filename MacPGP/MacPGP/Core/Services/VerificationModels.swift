import Foundation

/// Verification result models.
///
/// Responsibility boundary: shared types used to represent verification outcomes across the app UI
/// and services. Kept separate so `VerificationService` and the `SigningService` facade can share the
/// same models without cross-importing implementation details.

internal enum VerificationOutcome: Sendable, Equatable {
    case valid
    case invalidSignature
    case error
}

internal struct VerificationResult {
    let outcome: VerificationOutcome
    let signerKey: PGPKeyModel?
    let signatureDate: Date?
    let message: String
    let originalMessage: String?

    var isValid: Bool {
        outcome == .valid
    }

    var isError: Bool {
        outcome == .error
    }

    var signerKeyID: String? {
        signerKey?.shortKeyID
    }

    var title: String {
        switch outcome {
        case .valid:
            return "Signature Valid"
        case .invalidSignature:
            return "Signature Invalid"
        case .error:
            return "Verification Error"
        }
    }

    var symbolName: String {
        switch outcome {
        case .valid:
            return "checkmark.seal.fill"
        case .invalidSignature:
            return "xmark.seal.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    static func valid(signer: PGPKeyModel?, date: Date?, originalMessage: String? = nil) -> VerificationResult {
        VerificationResult(
            outcome: .valid,
            signerKey: signer,
            signatureDate: date,
            message: "Signature is valid",
            originalMessage: originalMessage
        )
    }

    static func invalid(reason: String) -> VerificationResult {
        VerificationResult(
            outcome: .invalidSignature,
            signerKey: nil,
            signatureDate: nil,
            message: reason,
            originalMessage: nil
        )
    }

    static func verificationError(reason: String) -> VerificationResult {
        VerificationResult(
            outcome: .error,
            signerKey: nil,
            signatureDate: nil,
            message: reason,
            originalMessage: nil
        )
    }
}
