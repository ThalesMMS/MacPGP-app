import Foundation
import RNPKit

/// Verification orchestration service.
///
/// Responsibility boundary: signature verification for message/data/file inputs and mapping low-level
/// verification payloads back into app-level models (`VerificationResult`) via `KeyringService`.
///
/// Outcomes and signer attribution are derived from librnp's verified-signature
/// metadata (`RNP.inspect` → `MessageInspection.signatures`), not from
/// throw/no-throw, packet-declared Issuer Key IDs, or localized error text. The
/// signer is resolved from the key librnp actually used to validate the
/// signature, so spoofed/unhashed issuer metadata cannot override attribution.
/// See `VerificationModels` for the multi-signature policy.

private struct VerificationKeySnapshot: @unchecked Sendable {
    let rawKey: Key
    let shortKeyID: String
}

/// One verified signature, reduced to the typed fields the app needs.
nonisolated private struct SignatureSummary: Sendable {
    let fingerprint: String?
    let keyID: String?
    let creationDate: Date?
    let status: VerifiedSignature.Status
}

nonisolated private struct VerificationPayload: Sendable {
    let signatures: [SignatureSummary]
    /// Non-nil for operational failures (read/parse/backend), which are distinct
    /// from any cryptographic verdict.
    let operationalError: String?
    let originalMessage: String?
    /// Content librnp recovered from the message (e.g. the canonical text of a
    /// cleartext-signed message), if any.
    let recoveredMessage: String?

    init(
        signatures: [SignatureSummary],
        operationalError: String?,
        originalMessage: String?,
        recoveredMessage: String? = nil
    ) {
        self.signatures = signatures
        self.operationalError = operationalError
        self.originalMessage = originalMessage
        self.recoveredMessage = recoveredMessage
    }
}

internal final class VerificationService {
    private let keyringService: KeyringService

    init(keyringService: KeyringService) {
        self.keyringService = keyringService
    }

    private func verificationSnapshots() -> [VerificationKeySnapshot] {
        keyringService.keys.compactMap { keyModel in
            guard let rawKey = keyringService.rawKey(for: keyModel) else {
                return nil
            }

            return VerificationKeySnapshot(rawKey: rawKey, shortKeyID: keyModel.shortKeyID)
        }
    }

    /// Resolve a signer from the key librnp verified against, not the packet's
    /// declared issuer. Tries the full verified fingerprint first, then the
    /// verified key ID.
    private func resolveSigner(fingerprint: String?, keyID: String?) -> PGPKeyModel? {
        if let fingerprint, let key = keyringService.key(withFingerprint: fingerprint) {
            return key
        }
        if let keyID, let key = keyringService.key(withShortID: keyID) {
            return key
        }
        return nil
    }

    private func verificationResult(from payload: VerificationPayload) -> VerificationResult {
        if let operationalError = payload.operationalError {
            return .verificationError(reason: operationalError)
        }

        let signatures = payload.signatures
        guard !signatures.isEmpty else {
            return VerificationResult(
                outcome: .noSignatures,
                signerKey: nil,
                signatureDate: nil,
                message: Self.message(for: .noSignatures),
                originalMessage: payload.originalMessage
            )
        }

        let outcome = Self.classify(signatures)

        // Attribute to the signature librnp actually validated when possible.
        let attributable = signatures.first { $0.status == .valid }
            ?? signatures.first { $0.status == .expired }
            ?? signatures.first
        let resolvedSigner = attributable.flatMap { resolveSigner(fingerprint: $0.fingerprint, keyID: $0.keyID) }

        // Only attach a signer/date for outcomes where a signature actually
        // verified; never present attribution for an invalid/unknown result.
        switch outcome {
        case .valid, .expired, .mixed:
            return VerificationResult(
                outcome: outcome,
                signerKey: resolvedSigner,
                signatureDate: attributable?.creationDate,
                message: Self.message(for: outcome),
                originalMessage: payload.originalMessage
            )
        default:
            return VerificationResult(
                outcome: outcome,
                signerKey: nil,
                signatureDate: nil,
                message: Self.message(for: outcome),
                originalMessage: payload.originalMessage
            )
        }
    }

    /// Multi-signature policy (documented in `VerificationModels`).
    nonisolated private static func classify(_ signatures: [SignatureSummary]) -> VerificationOutcome {
        let hasValid = signatures.contains { $0.status == .valid }
        let hasFailing = signatures.contains { $0.status != .valid }

        if hasValid && hasFailing { return .mixed }
        if hasValid { return .valid }

        // No fully-valid signature: the worst remaining status wins.
        if signatures.contains(where: { $0.status == .invalid }) { return .invalidSignature }
        if signatures.contains(where: { $0.status == .unknown }) { return .unknownStatus }
        if signatures.contains(where: { $0.status == .keyNotFound }) { return .missingKey }
        if signatures.contains(where: { $0.status == .expired }) { return .expired }
        return .unknownStatus
    }

    nonisolated private static func message(for outcome: VerificationOutcome) -> String {
        switch outcome {
        case .valid:
            return "Signature is valid"
        case .expired:
            return "The signature is valid but has expired."
        case .mixed:
            return "Some signatures are valid and others are not."
        case .invalidSignature:
            return "The signature is not valid."
        case .missingKey:
            return "The signer's public key is not available, so the signature could not be verified."
        case .noSignatures:
            return "No signatures were found in the input."
        case .unknownStatus:
            return "The signature status could not be determined."
        case .error:
            return "Verification failed."
        }
    }

    nonisolated private static func verifyPayload(
        data: Data,
        signature: Data? = nil,
        using snapshots: [VerificationKeySnapshot],
        originalMessage: String? = nil
    ) -> VerificationPayload {
        let allKeys = snapshots.map(\.rawKey)

        guard !allKeys.isEmpty else {
            return VerificationPayload(
                signatures: [],
                operationalError: "No keys available for verification",
                originalMessage: originalMessage
            )
        }

        do {
            let inspection = try RNP.inspect(data, withSignature: signature, using: allKeys)
            let summaries = inspection.signatures.map {
                SignatureSummary(
                    fingerprint: $0.fingerprint,
                    keyID: $0.keyID,
                    creationDate: $0.creationDate,
                    status: $0.status
                )
            }
            let recovered = inspection.outputData.flatMap { String(data: $0, encoding: .utf8) }
            return VerificationPayload(
                signatures: summaries,
                operationalError: nil,
                originalMessage: originalMessage,
                recoveredMessage: recovered
            )
        } catch {
            return VerificationPayload(
                signatures: [],
                operationalError: error.localizedDescription,
                originalMessage: originalMessage
            )
        }
    }

    /// Verifies a cleartext-signed message through librnp's native cleartext path
    /// (no manual section slicing or trailing-newline trimming). librnp parses the
    /// cleartext framework, applies the canonical dash-unescaping/line-ending
    /// rules, and reports the recovered content, which becomes the displayed
    /// original message so verification never silently rewrites user content.
    nonisolated private static func verifyCleartextPayload(
        _ signedMessage: String,
        using snapshots: [VerificationKeySnapshot]
    ) -> VerificationPayload {
        guard let messageData = signedMessage.data(using: .utf8) else {
            return VerificationPayload(signatures: [], operationalError: "Failed to parse message", originalMessage: nil)
        }

        let payload = verifyPayload(data: messageData, signature: nil, using: snapshots)
        // For cleartext, the displayed original is librnp's recovered content.
        return VerificationPayload(
            signatures: payload.signatures,
            operationalError: payload.operationalError,
            originalMessage: payload.recoveredMessage,
            recoveredMessage: payload.recoveredMessage
        )
    }

    nonisolated private static func parseSignatureData(from signature: String?) -> Data? {
        guard let signature else {
            return nil
        }

        if signature.hasPrefix("-----BEGIN PGP SIGNATURE-----") {
            return signature.data(using: .utf8)
        }

        return Data(base64Encoded: signature)
    }

    func verify(data: Data, signature: Data? = nil) throws -> VerificationResult {
        let payload = Self.verifyPayload(
            data: data,
            signature: signature,
            using: verificationSnapshots()
        )
        return verificationResult(from: payload)
    }

    func verifyAsync(data: Data) async throws -> VerificationResult {
        try await verifyAsync(data: data, signature: nil)
    }

    func verifyAsync(data: Data, signature: Data?) async throws -> VerificationResult {
        let snapshots = verificationSnapshots()
        let payload = await Task.detached(priority: .userInitiated) {
            Self.verifyPayload(data: data, signature: signature, using: snapshots)
        }.value
        return verificationResult(from: payload)
    }

    func verify(message: String, signature: String? = nil) throws -> VerificationResult {
        if message.hasPrefix("-----BEGIN PGP SIGNED MESSAGE-----") {
            let payload = Self.verifyCleartextPayload(message, using: verificationSnapshots())
            return verificationResult(from: payload)
        }

        guard let messageData = message.data(using: .utf8) else {
            return .verificationError(reason: "Failed to parse message or signature")
        }

        let signatureData = Self.parseSignatureData(from: signature)

        let payload = Self.verifyPayload(
            data: messageData,
            signature: signatureData,
            using: verificationSnapshots()
        )
        return verificationResult(from: payload)
    }

    func verifyAsync(message: String, signature: String? = nil) async throws -> VerificationResult {
        let snapshots = verificationSnapshots()

        if message.hasPrefix("-----BEGIN PGP SIGNED MESSAGE-----") {
            let payload = await Task.detached(priority: .userInitiated) {
                Self.verifyCleartextPayload(message, using: snapshots)
            }.value
            return verificationResult(from: payload)
        }

        guard let messageData = message.data(using: .utf8) else {
            return .verificationError(reason: "Failed to parse message or signature")
        }

        let signatureData = Self.parseSignatureData(from: signature)

        let payload = await Task.detached(priority: .userInitiated) {
            Self.verifyPayload(data: messageData, signature: signatureData, using: snapshots)
        }.value
        return verificationResult(from: payload)
    }

    /// Verifies a file's signature using librnp's path-based verification: the
    /// signed content streams from `inputPath` and a detached signature streams
    /// from `signaturePath`, so neither the original file nor the signature is
    /// read into memory. Inline-signed content is recovered to a null sink (not
    /// buffered). Files do not display recovered content, so no `recoveredMessage`
    /// is produced here (that is a cleartext-message concern).
    nonisolated private static func verifyFilePayload(
        inputPath: String,
        signaturePath: String?,
        using snapshots: [VerificationKeySnapshot]
    ) -> VerificationPayload {
        let allKeys = snapshots.map(\.rawKey)

        guard !allKeys.isEmpty else {
            return VerificationPayload(
                signatures: [],
                operationalError: "No keys available for verification",
                originalMessage: nil
            )
        }

        do {
            let verified = try RNP.verifyFile(
                inputPath: inputPath,
                signaturePath: signaturePath,
                using: allKeys
            )
            let summaries = verified.map {
                SignatureSummary(
                    fingerprint: $0.fingerprint,
                    keyID: $0.keyID,
                    creationDate: $0.creationDate,
                    status: $0.status
                )
            }
            return VerificationPayload(
                signatures: summaries,
                operationalError: nil,
                originalMessage: nil
            )
        } catch {
            return VerificationPayload(
                signatures: [],
                operationalError: error.localizedDescription,
                originalMessage: nil
            )
        }
    }

    func verify(file: URL, signatureFile: URL? = nil) throws -> VerificationResult {
        let snapshots = verificationSnapshots()
        let payload = try Self.verifyFileUnderScope(
            file: file,
            signatureFile: signatureFile,
            using: snapshots
        )
        return verificationResult(from: payload)
    }

    func verifyAsync(file: URL, signatureFile: URL? = nil) async throws -> VerificationResult {
        let snapshots = verificationSnapshots()
        let payload = try await Task.detached(priority: .userInitiated) {
            try Self.verifyFileUnderScope(
                file: file,
                signatureFile: signatureFile,
                using: snapshots
            )
        }.value
        return verificationResult(from: payload)
    }

    /// Resolves security-scoped paths for the input (and optional detached
    /// signature) and runs path-based verification. Throws only if scoped access
    /// cannot be established; verification verdicts are carried in the payload.
    nonisolated private static func verifyFileUnderScope(
        file: URL,
        signatureFile: URL?,
        using snapshots: [VerificationKeySnapshot]
    ) throws -> VerificationPayload {
        try SecureScopedFileAccess.withSecurityScopedAccess(to: file) { inputScoped in
            if let signatureFile {
                return try SecureScopedFileAccess.withSecurityScopedAccess(to: signatureFile) { signatureScoped in
                    Self.verifyFilePayload(
                        inputPath: inputScoped.path,
                        signaturePath: signatureScoped.path,
                        using: snapshots
                    )
                }
            }
            return Self.verifyFilePayload(
                inputPath: inputScoped.path,
                signaturePath: nil,
                using: snapshots
            )
        }
    }
}
