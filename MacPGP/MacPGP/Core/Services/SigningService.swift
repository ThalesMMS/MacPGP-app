import Foundation
import RNPKit

/// Signing orchestration service.
///
/// Responsibility boundary: signing-only operations (cleartext/attached/detached), plus a small
/// backward-compatible facade that forwards verification entry points to `VerificationService`.

private struct SigningKeySnapshot: @unchecked Sendable {
    nonisolated(unsafe) let rawKey: Key
    let shortKeyID: String
    let isSecret: Bool
    let isRevoked: Bool
    let isExpired: Bool
}

internal final class SigningService {
    private let verificationService: VerificationService
    private let keyringService: KeyringService

    init(keyringService: KeyringService) {
        self.keyringService = keyringService
        self.verificationService = VerificationService(keyringService: keyringService)
    }

    private func signingSnapshot(for key: PGPKeyModel) throws -> SigningKeySnapshot {
        guard let rawKey = keyringService.rawKey(for: key) else {
            throw OperationError.keyNotFound(keyID: key.shortKeyID)
        }

        return SigningKeySnapshot(
            rawKey: rawKey,
            shortKeyID: key.shortKeyID,
            isSecret: rawKey.isSecret,
            isRevoked: key.isRevoked,
            isExpired: key.isExpired
        )
    }

    nonisolated private static func signData(
        _ data: Data,
        using snapshot: SigningKeySnapshot,
        passphrase: String,
        detached: Bool,
        armored: Bool
    ) throws -> Data {
        guard snapshot.isSecret else {
            throw OperationError.noSecretKey
        }

        if snapshot.isRevoked {
            throw OperationError.keyRevoked
        }
        if snapshot.isExpired {
            throw OperationError.keyExpired
        }

        do {
            var signedData = try RNP.sign(
                data,
                detached: detached,
                using: [snapshot.rawKey],
                passphraseForKey: { _ in passphrase }
            )

            if armored {
                let armorType: PGPArmorType = detached ? .signature : .message
                let armoredString = try Armor.armored(signedData, as: armorType)
                signedData = armoredString.data(using: .utf8) ?? signedData
            }

            return signedData
        } catch RNPError.invalidPassphrase {
            throw OperationError.invalidPassphrase
        } catch {
            throw OperationError.signingFailed(underlying: error)
        }
    }

    nonisolated private static func signMessage(
        _ message: String,
        using snapshot: SigningKeySnapshot,
        passphrase: String,
        cleartext: Bool,
        detached: Bool,
        armored: Bool
    ) throws -> String {
        guard let messageData = message.data(using: .utf8) else {
            throw OperationError.signingFailed(underlying: nil)
        }

        if cleartext && !detached && armored {
            let signatureData = try signData(
                messageData,
                using: snapshot,
                passphrase: passphrase,
                detached: true,
                armored: false
            )

            let armoredSignature = try Armor.armored(signatureData, as: .signature)

            var result = "-----BEGIN PGP SIGNED MESSAGE-----\n"
            result += "Hash: SHA256\n"
            result += "\n"
            result += message
            if !message.hasSuffix("\n") {
                result += "\n"
            }
            result += armoredSignature

            return result
        }

        let signedData = try signData(
            messageData,
            using: snapshot,
            passphrase: passphrase,
            detached: detached,
            armored: armored
        )

        if armored {
            return String(data: signedData, encoding: .utf8) ?? ""
        } else {
            return signedData.base64EncodedString()
        }
    }

    nonisolated private static func signFile(
        _ file: URL,
        using snapshot: SigningKeySnapshot,
        passphrase: String,
        detached: Bool,
        outputURL: URL?,
        armored: Bool
    ) throws -> URL {
        let fileData = try SecureScopedFileAccess.readData(from: file)
        let signedData = try signData(
            fileData,
            using: snapshot,
            passphrase: passphrase,
            detached: detached,
            armored: armored
        )

        let outputPath: URL
        if let output = outputURL {
            outputPath = output
        } else if detached {
            outputPath = file.appendingPathExtension(armored ? "asc" : "sig")
        } else {
            outputPath = file.appendingPathExtension(armored ? "asc" : "gpg")
        }

        try SecureScopedFileAccess.writeData(signedData, to: outputPath)
        return outputPath
    }

    func sign(
        data: Data,
        using key: PGPKeyModel,
        passphrase: String,
        detached: Bool = false,
        armored: Bool = true
    ) throws -> Data {
        let snapshot = try signingSnapshot(for: key)
        return try Self.signData(
            data,
            using: snapshot,
            passphrase: passphrase,
            detached: detached,
            armored: armored
        )
    }

    func sign(
        message: String,
        using key: PGPKeyModel,
        passphrase: String,
        cleartext: Bool = true,
        detached: Bool = false,
        armored: Bool = true
    ) throws -> String {
        let snapshot = try signingSnapshot(for: key)
        return try Self.signMessage(
            message,
            using: snapshot,
            passphrase: passphrase,
            cleartext: cleartext,
            detached: detached,
            armored: armored
        )
    }

    func signAsync(
        message: String,
        using key: PGPKeyModel,
        passphrase: String,
        cleartext: Bool = true,
        detached: Bool = false,
        armored: Bool = true
    ) async throws -> String {
        let snapshot = try signingSnapshot(for: key)

        return try await Task.detached(priority: .userInitiated) {
            try Self.signMessage(
                message,
                using: snapshot,
                passphrase: passphrase,
                cleartext: cleartext,
                detached: detached,
                armored: armored
            )
        }.value
    }

    func sign(
        file: URL,
        using key: PGPKeyModel,
        passphrase: String,
        detached: Bool = true,
        outputURL: URL? = nil,
        armored: Bool = true
    ) throws -> URL {
        let snapshot = try signingSnapshot(for: key)
        return try Self.signFile(
            file,
            using: snapshot,
            passphrase: passphrase,
            detached: detached,
            outputURL: outputURL,
            armored: armored
        )
    }

    func signAsync(
        file: URL,
        using key: PGPKeyModel,
        passphrase: String,
        detached: Bool = true,
        outputURL: URL? = nil,
        armored: Bool = true
    ) async throws -> URL {
        let snapshot = try signingSnapshot(for: key)

        return try await Task.detached(priority: .userInitiated) {
            try Self.signFile(
                file,
                using: snapshot,
                passphrase: passphrase,
                detached: detached,
                outputURL: outputURL,
                armored: armored
            )
        }.value
    }


    // MARK: - Verification facade

    func verify(message: String) throws -> VerificationResult {
        try verificationService.verify(message: message)
    }

    func verify(message: String, signature: String) throws -> VerificationResult {
        try verificationService.verify(message: message, signature: signature)
    }

    func verifyAsync(message: String, signature: String) async throws -> VerificationResult {
        try await verificationService.verifyAsync(message: message, signature: signature)
    }

    func verifyAsync(message: String) async throws -> VerificationResult {
        try await verificationService.verifyAsync(message: message)
    }

    func verify(data: Data) throws -> VerificationResult {
        try verificationService.verify(data: data)
    }

    func verify(data: Data, signature: Data) throws -> VerificationResult {
        try verificationService.verify(data: data, signature: signature)
    }

    func verifyAsync(data: Data) async throws -> VerificationResult {
        try await verificationService.verifyAsync(data: data)
    }

    func verifyAsync(data: Data, signature: Data) async throws -> VerificationResult {
        try await verificationService.verifyAsync(data: data, signature: signature)
    }

    func verify(file: URL) throws -> VerificationResult {
        try verificationService.verify(file: file)
    }

    func verify(file: URL, signatureFile: URL?) throws -> VerificationResult {
        try verificationService.verify(file: file, signatureFile: signatureFile)
    }

    func verifyAsync(file: URL) async throws -> VerificationResult {
        try await verificationService.verifyAsync(file: file)
    }

    func verifyAsync(file: URL, signatureFile: URL?) async throws -> VerificationResult {
        try await verificationService.verifyAsync(file: file, signatureFile: signatureFile)
    }

    // OpenPGPPacket parsing helpers were extracted into OpenPGPPacketParser.
    nonisolated static func extractIssuerKeyID(from signatureData: Data) -> String? {
        OpenPGPPacketParser.extractIssuerKeyID(from: signatureData)
    }
}
