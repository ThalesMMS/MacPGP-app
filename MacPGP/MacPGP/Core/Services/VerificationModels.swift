import Foundation

/// Verification result models.
///
/// Responsibility boundary: shared types used to represent verification outcomes across the app UI
/// and services. Kept separate so `VerificationService` and the `SigningService` facade can share the
/// same models without cross-importing implementation details.
///
/// ## Multi-signature policy
///
/// Outcomes are derived from librnp's typed per-signature status (see
/// `VerifiedSignature.Status`), never from throw/no-throw or localized error
/// text, using the following precedence over the set of signatures present:
///
/// - **no signatures** → `.noSignatures`
/// - **≥1 valid and none failing** → `.valid`
/// - **≥1 valid and ≥1 failing** (invalid/expired/missing-key/unknown) → `.mixed`
/// - **no valid signature**, then the worst remaining status wins:
///   `.invalidSignature` > `.unknownStatus` > `.missingKey` > `.expired`
///
/// `.error` is reserved for *operational* failures (read/parse/backend), which
/// are distinct from any cryptographic verdict so the UI can tell them apart.

nonisolated internal enum VerificationOutcome: Sendable, Equatable {
    /// Every signature present verified successfully and is current.
    case valid
    /// A signature verified but the signature or its key has expired.
    case expired
    /// At least one valid signature and at least one that is not.
    case mixed
    /// A signature failed cryptographic verification.
    case invalidSignature
    /// A signer's key was not available, so the signature could not be verified.
    case missingKey
    /// The input contains no signatures.
    case noSignatures
    /// librnp reported an unrecognized status; treated as not valid (fail closed).
    case unknownStatus
    /// Operational failure (read/parse/backend), not a cryptographic verdict.
    case error
}

nonisolated internal struct VerificationResult {
    let outcome: VerificationOutcome
    let signerKey: PGPKeyModel?
    let signatureDate: Date?
    let message: String
    let originalMessage: String?

    var isValid: Bool {
        outcome == .valid
    }

    /// Operational failure (read/parse/backend), as opposed to a cryptographic
    /// verdict on the signature.
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
        case .expired:
            return "Signature Expired"
        case .mixed:
            return "Mixed Signatures"
        case .invalidSignature:
            return "Signature Invalid"
        case .missingKey:
            return "Signer Key Missing"
        case .noSignatures:
            return "No Signature Found"
        case .unknownStatus:
            return "Signature Status Unknown"
        case .error:
            return "Verification Error"
        }
    }

    var symbolName: String {
        switch outcome {
        case .valid:
            return "checkmark.seal.fill"
        case .expired:
            return "clock.badge.exclamationmark.fill"
        case .mixed, .unknownStatus, .error:
            return "exclamationmark.triangle.fill"
        case .invalidSignature, .noSignatures:
            return "xmark.seal.fill"
        case .missingKey:
            return "questionmark.seal.fill"
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
