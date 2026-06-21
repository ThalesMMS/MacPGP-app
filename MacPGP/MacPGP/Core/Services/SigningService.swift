import Foundation
import RNPKit

/// Signing orchestration service.
///
/// Responsibility boundary: signing-only operations (cleartext/attached/detached), plus a small
/// backward-compatible facade that forwards verification entry points to `VerificationService`.

private struct SigningKeySnapshot: @unchecked Sendable {
    let rawKey: Key
    let shortKeyID: String
    let isSecret: Bool
    let isRevoked: Bool
    let isExpired: Bool
}

internal final class SigningService {
    private let verificationService: VerificationService
    private let keyringService: KeyringService
    private let clock: DateProviding

    init(keyringService: KeyringService, clock: DateProviding = SystemDateProvider()) {
        self.keyringService = keyringService
        self.clock = clock
        self.verificationService = VerificationService(keyringService: keyringService)
    }

    private func signingSnapshot(for key: PGPKeyModel) throws -> SigningKeySnapshot {
        guard let rawKey = keyringService.rawKey(for: key) else {
            throw OperationError.keyNotFound(keyID: key.shortKeyID)
        }

        // Capture expiration against the current time at operation start, not the
        // value cached when the model was built.
        return SigningKeySnapshot(
            rawKey: rawKey,
            shortKeyID: key.shortKeyID,
            isSecret: rawKey.isSecret,
            isRevoked: key.isRevoked,
            isExpired: key.isExpired(asOf: clock.now)
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
            // Use librnp's native cleartext signing so dash-escaping and
            // line-ending normalization follow the OpenPGP canonical rules
            // instead of being assembled by hand.
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
                let signed = try RNP.signCleartext(
                    messageData,
                    using: [snapshot.rawKey],
                    passphraseForKey: { _ in passphrase }
                )
                return String(data: signed, encoding: .utf8) ?? ""
            } catch RNPError.invalidPassphrase {
                throw OperationError.invalidPassphrase
            } catch let error as OperationError {
                throw error
            } catch {
                throw OperationError.signingFailed(underlying: error)
            }
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

    /// Streams signing directly between file paths via the backend, so the file is
    /// not buffered in memory. librnp produces armored output as it writes.
    nonisolated private static func performStreamingSigning(
        inputPath: String,
        outputPath: String,
        using snapshot: SigningKeySnapshot,
        passphrase: String,
        detached: Bool,
        armored: Bool
    ) throws {
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
            try RNP.signFile(
                inputPath: inputPath,
                outputPath: outputPath,
                detached: detached,
                armored: armored,
                using: [snapshot.rawKey],
                passphraseForKey: { _ in passphrase }
            )
        } catch RNPError.invalidPassphrase {
            throw OperationError.invalidPassphrase
        } catch let error as OperationError {
            throw error
        } catch {
            throw OperationError.signingFailed(underlying: error)
        }
    }

    nonisolated private static func signFile(
        _ file: URL,
        using snapshot: SigningKeySnapshot,
        passphrase: String,
        detached: Bool,
        outputURL: URL?,
        armored: Bool,
        commitGate: FileCommitGate? = nil
    ) throws -> URL {
        let outputPath: URL
        if let output = outputURL {
            outputPath = output
        } else {
            let outputExtension = PGPFileExtensions.signedOutputExtension(detached: detached, armored: armored)
            outputPath = file.appendingPathExtension(outputExtension)
        }

        try SecureScopedFileAccess.withSecurityScopedAccess(to: file) { inputScoped in
            try SecureScopedFileAccess.writeFileWithoutOverwriting(
                finalOutput: outputPath,
                scopedBy: outputURL,
                overwrite: true,
                canCommit: { commitGate?.isAuthorized ?? true }
            ) { tempPath in
                try performStreamingSigning(
                    inputPath: inputScoped.path,
                    outputPath: tempPath,
                    using: snapshot,
                    passphrase: passphrase,
                    detached: detached,
                    armored: armored
                )
            }
        }
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
        armored: Bool = true,
        commitGate: FileCommitGate? = nil
    ) async throws -> URL {
        let snapshot = try signingSnapshot(for: key)

        return try await Task.detached(priority: .userInitiated) {
            try Self.signFile(
                file,
                using: snapshot,
                passphrase: passphrase,
                detached: detached,
                outputURL: outputURL,
                armored: armored,
                commitGate: commitGate
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
