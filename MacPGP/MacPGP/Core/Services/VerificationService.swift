import Foundation
import RNPKit

/// Verification orchestration service.
///
/// Responsibility boundary: signature verification for message/data/file inputs and mapping low-level
/// verification payloads back into app-level models (`VerificationResult`) via `KeyringService`.

private struct VerificationKeySnapshot: @unchecked Sendable {
    nonisolated(unsafe) let rawKey: Key
    let shortKeyID: String
}

private struct DetachedVerificationPayload: Sendable {
    let outcome: String
    let signerShortID: String?
    let message: String
    let originalMessage: String?
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

    private func verificationResult(from payload: DetachedVerificationPayload) -> VerificationResult {
        let signerKey = payload.signerShortID.flatMap { keyringService.key(withShortID: $0) }

        switch payload.outcome {
        case "valid":
            return .valid(signer: signerKey, date: nil, originalMessage: payload.originalMessage)
        case "invalidSignature":
            return .invalid(reason: payload.message)
        default:
            return .verificationError(reason: payload.message)
        }
    }

    nonisolated private static func verifyPayload(
        data: Data,
        signature: Data? = nil,
        using snapshots: [VerificationKeySnapshot],
        originalMessage: String? = nil
    ) -> DetachedVerificationPayload {
        let allKeys = snapshots.map(\.rawKey)

        guard !allKeys.isEmpty else {
            return DetachedVerificationPayload(
                outcome: "error",
                signerShortID: nil,
                message: "No keys available for verification",
                originalMessage: originalMessage
            )
        }

        do {
            try RNP.verify(data, withSignature: signature, using: allKeys)

            let signerShortID = OpenPGPPacketParser.extractIssuerKeyID(from: signature ?? data).flatMap { issuerKeyID in
                snapshots.first {
                    issuerKeyID.hasSuffix($0.shortKeyID)
                }?.shortKeyID
            }

            return DetachedVerificationPayload(
                outcome: "valid",
                signerShortID: signerShortID,
                message: "Signature is valid",
                originalMessage: originalMessage
            )
        } catch {
            let invalidSignature = isInvalidSignatureError(error)
            return DetachedVerificationPayload(
                outcome: invalidSignature ? "invalidSignature" : "error",
                signerShortID: nil,
                message: error.localizedDescription,
                originalMessage: originalMessage
            )
        }
    }

    nonisolated private static func isInvalidSignatureError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()

        if let rnpError = error as? RNPError {
            switch rnpError {
            case .missingPublicKey, .missingSecretKey, .missingDecryptedOutput, .missingSigningKey, .invalidPassphrase:
                return false
            }
        }

        let nsError = error as NSError
        if nsError.domain == RNPError.errorDomain {
            if let code = rnpErrorCode(from: nsError) {
                return isInvalidSignatureRNPCode(code)
            }

            return message.contains("signature") || message.contains("verification")
        }

        return message.contains("signature")
    }

    nonisolated private static func rnpErrorCode(from error: NSError) -> Int? {
        if let code = error.userInfo["RNPErrorCode"] as? Int {
            return code
        }

        if let code = error.userInfo["RNPErrorCode"] as? UInt32 {
            return Int(code)
        }

        if let code = error.userInfo["RNPErrorCode"] as? NSNumber {
            return code.intValue
        }

        return error.code
    }

    nonisolated private static func isInvalidSignatureRNPCode(_ code: Int) -> Bool {
        switch code {
        case 0x12000002, // RNP_ERROR_SIGNATURE_INVALID
             0x1200000B, // RNP_ERROR_NO_SIGNATURES_FOUND
             0x1200000C, // RNP_ERROR_SIGNATURE_EXPIRED
             0x1200000D, // RNP_ERROR_VERIFICATION_FAILED
             0x1200000E: // RNP_ERROR_SIGNATURE_UNKNOWN
            return true
        case 0x14000000...0x140000FF:
            return true
        default:
            return false
        }
    }

    nonisolated private static func verifyCleartextPayload(
        _ signedMessage: String,
        using snapshots: [VerificationKeySnapshot]
    ) -> DetachedVerificationPayload {
        guard let signatureStart = signedMessage.range(of: "-----BEGIN PGP SIGNATURE-----") else {
            return DetachedVerificationPayload(
                outcome: "error",
                signerShortID: nil,
                message: "Invalid cleartext signed message format",
                originalMessage: nil
            )
        }

        let headerEnd = signedMessage.range(of: "\n\n", range: signedMessage.startIndex..<signatureStart.lowerBound)
        guard let headerEndRange = headerEnd else {
            return DetachedVerificationPayload(
                outcome: "error",
                signerShortID: nil,
                message: "Invalid cleartext signed message header",
                originalMessage: nil
            )
        }

        var messageBody = String(signedMessage[headerEndRange.upperBound..<signatureStart.lowerBound])
        if messageBody.hasSuffix("\n") {
            messageBody.removeLast()
        }

        let signatureString = String(signedMessage[signatureStart.lowerBound...])
        guard let messageData = messageBody.data(using: .utf8),
              let signatureData = signatureString.data(using: .utf8) else {
            return DetachedVerificationPayload(
                outcome: "error",
                signerShortID: nil,
                message: "Failed to parse message or signature",
                originalMessage: nil
            )
        }

        return verifyPayload(
            data: messageData,
            signature: signatureData,
            using: snapshots,
            originalMessage: messageBody
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
        // Ensure API surface also supports the legacy explicit-signature overload.
        // (Using an optional keeps the implementation shared.)
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

    func verify(file: URL, signatureFile: URL? = nil) throws -> VerificationResult {
        let fileData = try SecureScopedFileAccess.readData(from: file)

        var signatureData: Data?
        if let sigFile = signatureFile {
            signatureData = try SecureScopedFileAccess.readData(from: sigFile)
        }

        return try verify(data: fileData, signature: signatureData)
    }

    func verifyAsync(file: URL, signatureFile: URL? = nil) async throws -> VerificationResult {
        let snapshots = verificationSnapshots()
        let payload = try await Task.detached(priority: .userInitiated) {
            let fileData = try SecureScopedFileAccess.readData(from: file)

            var signatureData: Data?
            if let signatureFile = signatureFile {
                signatureData = try SecureScopedFileAccess.readData(from: signatureFile)
            }

            return Self.verifyPayload(data: fileData, signature: signatureData, using: snapshots)
        }.value
        return verificationResult(from: payload)
    }
}
