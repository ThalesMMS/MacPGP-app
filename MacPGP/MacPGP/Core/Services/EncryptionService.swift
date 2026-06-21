import Foundation
import RNPKit

private struct DecryptionKeySnapshot: @unchecked Sendable {
    let rawKey: Key
    let isSecret: Bool
}

private struct TryDecryptionKeySnapshot: @unchecked Sendable {
    let model: PGPKeyModel
    let rawKey: Key
}

private struct TryDecryptionResult: @unchecked Sendable {
    let decryptedData: Data
    let key: PGPKeyModel
}

private struct TryDecryptionFileResult: @unchecked Sendable {
    let outputURL: URL
    let key: PGPKeyModel
}

final class EncryptionService {
    private let keyringService: KeyringService
    private let trustService: TrustService
    private let clock: DateProviding

    init(keyringService: KeyringService, clock: DateProviding = SystemDateProvider()) {
        self.keyringService = keyringService
        self.clock = clock
        self.trustService = TrustService(keyringService: keyringService, clock: clock)
    }

    func encrypt(
        data: Data,
        for recipients: [PGPKeyModel],
        signedBy signer: PGPKeyModel? = nil,
        passphrase: String? = nil,
        armored: Bool = true
    ) throws -> Data {
        guard !recipients.isEmpty else {
            throw OperationError.recipientKeyMissing
        }

        let (recipientKeys, signerKey) = try encryptionKeys(for: recipients, signedBy: signer)

        return try Self.performEncryption(
            data: data,
            recipientKeys: recipientKeys,
            signerKey: signerKey,
            passphrase: passphrase,
            armored: armored
        )
    }

    private func encryptionKeys(for recipients: [PGPKeyModel], signedBy signer: PGPKeyModel?) throws -> ([Key], Key?) {
        let validatedRecipients = try validatedRecipientsForEncryption(recipients)
        let recipientKeys = validatedRecipients.compactMap { keyringService.rawKey(for: $0) }
        guard recipientKeys.count == recipients.count else {
            throw OperationError.keyNotFound(keyID: "recipient")
        }

        guard let signer else {
            return (recipientKeys, nil)
        }

        guard let signerKey = keyringService.rawKey(for: signer) else {
            throw OperationError.keyNotFound(keyID: signer.shortKeyID)
        }
        guard signerKey.isSecret else {
            throw OperationError.noSecretKey
        }

        return (recipientKeys, signerKey)
    }

    private func validatedRecipientsForEncryption(_ recipients: [PGPKeyModel]) throws -> [PGPKeyModel] {
        guard !recipients.isEmpty else {
            throw OperationError.recipientKeyMissing
        }

        return try recipients.map { recipient in
            let currentRecipient = keyringService.key(withFingerprint: recipient.fingerprint) ?? recipient
            guard trustService.isKeyValidForEncryption(currentRecipient) else {
                throw encryptionValidationError(for: currentRecipient)
            }
            return currentRecipient
        }
    }

    private func encryptionValidationError(for recipient: PGPKeyModel) -> OperationError {
        if recipient.isRevoked {
            return .keyRevoked
        }

        if recipient.isExpired(asOf: clock.now) {
            return .keyExpired
        }

        if recipient.trustLevel == .never {
            return .recipientKeyUntrusted(keyID: recipient.shortKeyID)
        }

        return .encryptionFailed(underlying: nil)
    }

    private func decryptionSnapshot(for key: PGPKeyModel) throws -> DecryptionKeySnapshot {
        guard let rawKey = keyringService.rawKey(for: key) else {
            throw OperationError.keyNotFound(keyID: key.shortKeyID)
        }

        return DecryptionKeySnapshot(
            rawKey: rawKey,
            isSecret: rawKey.isSecret
        )
    }

    private func tryDecryptionSnapshots() -> [TryDecryptionKeySnapshot] {
        keyringService.secretKeys().compactMap { keyModel in
            guard let rawKey = keyringService.rawKey(for: keyModel) else {
                return nil
            }

            return TryDecryptionKeySnapshot(model: keyModel, rawKey: rawKey)
        }
    }

    nonisolated private static func performEncryption(
        data: Data,
        recipientKeys: [Key],
        signerKey: Key?,
        passphrase: String?,
        armored: Bool
    ) throws -> Data {
        do {
            var encryptedData: Data

            if let signerKey = signerKey, let passphrase = passphrase {
                var allKeys = recipientKeys
                allKeys.append(signerKey)
                encryptedData = try RNP.encrypt(
                    data,
                    addSignature: true,
                    using: allKeys,
                    passphraseForKey: { _ in passphrase }
                )
            } else {
                encryptedData = try RNP.encrypt(data, addSignature: false, using: recipientKeys)
            }

            if armored {
                let armoredString = try Armor.armored(encryptedData, as: .message)
                encryptedData = armoredString.data(using: .utf8) ?? encryptedData
            }

            return encryptedData
        } catch RNPError.invalidPassphrase {
            throw OperationError.invalidPassphrase
        } catch RNPError.missingSigningKey {
            throw OperationError.signerKeyMissing
        } catch {
            throw OperationError.encryptionFailed(underlying: error)
        }
    }

    nonisolated private static func performDecryption(
        data: Data,
        using snapshot: DecryptionKeySnapshot,
        passphrase: String
    ) throws -> Data {
        guard snapshot.isSecret else {
            throw OperationError.noSecretKey
        }

        return try PGPDecryption.decrypt(data: data, using: snapshot.rawKey, passphrase: passphrase)
    }

    /// Streams encryption directly between file paths via the backend, so neither the
    /// full plaintext nor the full ciphertext is buffered in memory. librnp produces
    /// armored output as it writes, so large armored output streams too.
    nonisolated private static func performStreamingEncryption(
        inputPath: String,
        outputPath: String,
        recipientKeys: [Key],
        signerKey: Key?,
        passphrase: String?,
        armored: Bool
    ) throws {
        do {
            if let signerKey, let passphrase {
                var allKeys = recipientKeys
                allKeys.append(signerKey)
                try RNP.encryptFile(
                    inputPath: inputPath,
                    outputPath: outputPath,
                    armored: armored,
                    addSignature: true,
                    using: allKeys,
                    passphraseForKey: { _ in passphrase }
                )
            } else {
                try RNP.encryptFile(
                    inputPath: inputPath,
                    outputPath: outputPath,
                    armored: armored,
                    addSignature: false,
                    using: recipientKeys
                )
            }
        } catch RNPError.invalidPassphrase {
            throw OperationError.invalidPassphrase
        } catch RNPError.missingSigningKey {
            throw OperationError.signerKeyMissing
        } catch let error as OperationError {
            throw error
        } catch {
            throw OperationError.encryptionFailed(underlying: error)
        }
    }

    /// Streams decryption directly between file paths via the backend.
    nonisolated private static func performStreamingDecryption(
        inputPath: String,
        outputPath: String,
        using snapshot: DecryptionKeySnapshot,
        passphrase: String
    ) throws {
        guard snapshot.isSecret else {
            throw OperationError.noSecretKey
        }
        do {
            try RNP.decryptFile(
                inputPath: inputPath,
                outputPath: outputPath,
                using: [snapshot.rawKey],
                passphraseForKey: { _ in passphrase }
            )
        } catch RNPError.invalidPassphrase {
            throw OperationError.invalidPassphrase
        } catch let error as OperationError {
            throw error
        } catch {
            throw OperationError.decryptionFailed(underlying: error)
        }
    }

    nonisolated private static func performTryDecryption(
        data: Data,
        using snapshots: [TryDecryptionKeySnapshot],
        passphrase: String
    ) throws -> TryDecryptionResult {
        let result = try PGPDecryption.decrypt(
            data: data,
            usingAnySecretKeyIn: snapshots.map(\.rawKey),
            passphrase: passphrase
        )

        guard let snapshot = snapshots.first(where: { $0.rawKey.fingerprint == result.key.fingerprint }) else {
            throw OperationError.keyNotFound(keyID: result.key.shortKeyID)
        }

        return TryDecryptionResult(decryptedData: result.decryptedData, key: snapshot.model)
    }

    /// Streams auto-detect decryption from `inputPath` to `outputPath`, trying all
    /// available secret keys, and returns the key that librnp used. Neither the
    /// ciphertext nor the plaintext is materialized in memory — this is the
    /// file-mode counterpart of `performTryDecryption`, which stays Data-based for
    /// small/text inputs.
    nonisolated private static func performStreamingTryDecryption(
        inputPath: String,
        outputPath: String,
        using snapshots: [TryDecryptionKeySnapshot],
        passphrase: String
    ) throws -> PGPKeyModel {
        guard !snapshots.isEmpty else {
            throw OperationError.noSecretKey
        }

        do {
            let usedFingerprint = try RNP.decryptFileTryingKeys(
                inputPath: inputPath,
                outputPath: outputPath,
                using: snapshots.map(\.rawKey),
                passphraseForKey: { _ in passphrase }
            )

            // Attribute the streamed decryption to a key. librnp reports the
            // primary fingerprint of the recipient it used; match it. When the
            // recipient cannot be attributed (e.g. a hidden/wildcard recipient)
            // decryption still succeeded, so fall back rather than fail: the sole
            // secret key when there is one, otherwise the first candidate.
            if let usedFingerprint,
               let match = snapshots.first(where: {
                   $0.rawKey.fingerprint.caseInsensitiveCompare(usedFingerprint) == .orderedSame
               }) {
                return match.model
            }
            return snapshots[0].model
        } catch RNPError.invalidPassphrase {
            throw OperationError.invalidPassphrase
        } catch let error as OperationError {
            throw error
        } catch {
            throw OperationError.decryptionFailed(underlying: error)
        }
    }

    func encrypt(
        message: String,
        for recipients: [PGPKeyModel],
        signedBy signer: PGPKeyModel? = nil,
        passphrase: String? = nil,
        armored: Bool = true
    ) throws -> String {
        guard let messageData = message.data(using: .utf8) else {
            throw OperationError.encryptionFailed(underlying: nil)
        }

        let encryptedData = try encrypt(
            data: messageData,
            for: recipients,
            signedBy: signer,
            passphrase: passphrase,
            armored: armored
        )

        if armored {
            return String(data: encryptedData, encoding: .utf8) ?? ""
        } else {
            return encryptedData.base64EncodedString()
        }
    }

    func encryptAsync(
        message: String,
        for recipients: [PGPKeyModel],
        signedBy signer: PGPKeyModel? = nil,
        passphrase: String? = nil,
        armored: Bool = true
    ) async throws -> String {
        guard let messageData = message.data(using: .utf8) else {
            throw OperationError.encryptionFailed(underlying: nil)
        }

        let (recipientKeys, signerKey) = try encryptionKeys(for: recipients, signedBy: signer)
        let encryptedData = try await Task.detached {
            try Self.performEncryption(
                data: messageData,
                recipientKeys: recipientKeys,
                signerKey: signerKey,
                passphrase: passphrase,
                armored: armored
            )
        }.value

        if armored {
            return String(data: encryptedData, encoding: .utf8) ?? ""
        } else {
            return encryptedData.base64EncodedString()
        }
    }

    /// Encrypts the file at the given URL for the specified recipients, optionally signs it and writes the encrypted data to disk.
    /// - Parameters:
    ///   - file: The URL of the input file to encrypt.
    ///   - recipients: Recipient public key models used to encrypt the file; must not be empty.
    ///   - signer: Optional key model used to sign the encrypted output.
    ///   - passphrase: Optional passphrase used when signing with an encrypted secret key.
    ///   - outputURL: Optional destination URL or directory for the encrypted file. If `nil` a default filename and extension (`.asc` for armored, `.gpg` otherwise) is used. If a directory is provided the original filename plus extension is appended.
    ///   - armored: When `true` produce ASCII-armored output (`.asc`), otherwise produce binary OpenPGP output (`.gpg`).
    ///   - progressCallback: Optional callback invoked with progress states: `0.0` (start), `0.3` (after read), `0.7` (after encrypt), and `1.0` (after write).
    /// - Returns: The file URL where the encrypted output was written.
    func encrypt(
        file: URL,
        for recipients: [PGPKeyModel],
        signedBy signer: PGPKeyModel? = nil,
        passphrase: String? = nil,
        outputURL: URL? = nil,
        armored: Bool = false,
        progressCallback: ((Double) -> Void)? = nil
    ) throws -> URL {
        progressCallback?(0.0)

        let (recipientKeys, signerKey) = try encryptionKeys(for: recipients, signedBy: signer)
        let outputPath = Self.resolvedEncryptedOutputURL(for: file, outputURL: outputURL, armored: armored)
        progressCallback?(0.3)

        try SecureScopedFileAccess.withSecurityScopedAccess(to: file) { inputScoped in
            try SecureScopedFileAccess.writeFileWithoutOverwriting(finalOutput: outputPath, scopedBy: outputURL, afterWrite: { progressCallback?(0.7) }) { tempPath in
                try Self.performStreamingEncryption(
                    inputPath: inputScoped.path,
                    outputPath: tempPath,
                    recipientKeys: recipientKeys,
                    signerKey: signerKey,
                    passphrase: passphrase,
                    armored: armored
                )
            }
        }

        progressCallback?(1.0)
        return outputPath
    }

    func decrypt(
        data: Data,
        using key: PGPKeyModel,
        passphrase: String
    ) throws -> Data {
        let snapshot = try decryptionSnapshot(for: key)
        return try Self.performDecryption(data: data, using: snapshot, passphrase: passphrase)
    }

    func decrypt(
        message: String,
        using key: PGPKeyModel,
        passphrase: String
    ) throws -> String {
        guard let messageData = message.data(using: .utf8) else {
            throw OperationError.decryptionFailed(underlying: nil)
        }

        let decryptedData = try decrypt(data: messageData, using: key, passphrase: passphrase)

        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw OperationError.decryptionFailed(underlying: nil)
        }

        return decryptedString
    }

    func decryptAsync(
        message: String,
        using key: PGPKeyModel,
        passphrase: String
    ) async throws -> String {
        guard let messageData = message.data(using: .utf8) else {
            throw OperationError.decryptionFailed(underlying: nil)
        }

        let snapshot = try decryptionSnapshot(for: key)
        let decryptedData = try await Task.detached {
            try Self.performDecryption(data: messageData, using: snapshot, passphrase: passphrase)
        }.value

        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw OperationError.decryptionFailed(underlying: nil)
        }

        return decryptedString
    }

    /// Decrypts a file using the specified PGP key and writes the decrypted bytes to disk.
    /// - Parameters:
    ///   - file: The URL of the encrypted input file to read.
    ///   - using: The `PGPKeyModel` whose secret material will be used to decrypt the file.
    ///   - passphrase: The passphrase to unlock the secret key when required.
    ///   - outputURL: Optional destination URL. If `nil` or a directory, the output filename is derived from the input file (removing `.asc`/`.gpg` if present, otherwise appending `.decrypted`). If a file URL is provided, it is used as-is.
    ///   - progressCallback: Optional callback invoked with progress updates: `0.0`, `0.3`, `0.7`, and `1.0`.
    /// - Returns: The URL where the decrypted file was written.
    /// - Throws: An error if reading the input file, decrypting the data, or writing the output file fails.
    func decrypt(
        file: URL,
        using key: PGPKeyModel,
        passphrase: String,
        outputURL: URL? = nil,
        progressCallback: ((Double) -> Void)? = nil
    ) throws -> URL {
        progressCallback?(0.0)

        let snapshot = try decryptionSnapshot(for: key)
        let outputPath = Self.resolvedDecryptedOutputURL(for: file, outputURL: outputURL)
        progressCallback?(0.3)

        try SecureScopedFileAccess.withSecurityScopedAccess(to: file) { inputScoped in
            try SecureScopedFileAccess.writeFileWithoutOverwriting(finalOutput: outputPath, scopedBy: outputURL, afterWrite: { progressCallback?(0.7) }) { tempPath in
                try Self.performStreamingDecryption(
                    inputPath: inputScoped.path,
                    outputPath: tempPath,
                    using: snapshot,
                    passphrase: passphrase
                )
            }
        }
        progressCallback?(1.0)
        return outputPath
    }

    /// Encrypts the file at `file` for the specified `recipients`, optionally signs it, and writes the encrypted result to disk.
    /// - Parameters:
    ///   - file: The file URL to read and encrypt.
    ///   - recipients: The recipient key models to encrypt for; must not be empty.
    ///   - signer: Optional key model used to sign the encrypted output.
    ///   - passphrase: Optional passphrase used for signing key operations when a signer is provided.
    ///   - outputURL: Optional destination URL or directory for the encrypted file. If `nil` or a directory, the final output path is resolved via `resolvedEncryptedOutputURL(for:outputURL:armored:)`.
    ///   - armored: When `true`, produce ASCII-armored output (uses `.asc` extension); when `false`, produce binary output (uses `.gpg` extension).
    ///   - progressCallback: Optional callback invoked with progress updates at 0.0, 0.3, 0.7, and 1.0.
    /// - Returns: The file URL where the encrypted data was written.
    func encryptAsync(
        file: URL,
        for recipients: [PGPKeyModel],
        signedBy signer: PGPKeyModel? = nil,
        passphrase: String? = nil,
        outputURL: URL? = nil,
        armored: Bool = false,
        commitGate: FileCommitGate? = nil,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        progressCallback?(0.0)
        let (recipientKeys, signerKey) = try encryptionKeys(for: recipients, signedBy: signer)
        let outputPath = Self.resolvedEncryptedOutputURL(for: file, outputURL: outputURL, armored: armored)

        return try await Task.detached {
            await MainActor.run { progressCallback?(0.3) }

            try SecureScopedFileAccess.withSecurityScopedAccess(to: file) { inputScoped in
                try SecureScopedFileAccess.writeFileWithoutOverwriting(finalOutput: outputPath, scopedBy: outputURL, afterWrite: { progressCallback?(0.7) }, canCommit: { commitGate?.isAuthorized ?? true }) { tempPath in
                    try Self.performStreamingEncryption(
                        inputPath: inputScoped.path,
                        outputPath: tempPath,
                        recipientKeys: recipientKeys,
                        signerKey: signerKey,
                        passphrase: passphrase,
                        armored: armored
                    )
                }
            }

            await MainActor.run { progressCallback?(1.0) }
            return outputPath
        }.value
    }

    /// Decrypts a file with the provided key and passphrase, writes the decrypted bytes to disk, and returns the file URL of the written output.
    /// - Parameters:
    ///   - file: The URL of the encrypted input file to decrypt.
    ///   - key: The PGP key model whose secret material will be used to decrypt the file.
    ///   - passphrase: The passphrase to unlock the secret key, if required.
    ///   - outputURL: An optional destination URL or directory for the decrypted file; if `nil` a default location is used.
    ///   - progressCallback: An optional callback invoked on the main actor with progress updates (`0.0`, `0.3`, `0.7`, `1.0`).
    /// - Returns: The URL where the decrypted file was written.
    func decryptAsync(
        file: URL,
        using key: PGPKeyModel,
        passphrase: String,
        outputURL: URL? = nil,
        commitGate: FileCommitGate? = nil,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        progressCallback?(0.0)
        let snapshot = try decryptionSnapshot(for: key)
        let outputPath = Self.resolvedDecryptedOutputURL(for: file, outputURL: outputURL)

        return try await Task.detached {
            await MainActor.run { progressCallback?(0.3) }

            try SecureScopedFileAccess.withSecurityScopedAccess(to: file) { inputScoped in
                try SecureScopedFileAccess.writeFileWithoutOverwriting(finalOutput: outputPath, scopedBy: outputURL, afterWrite: { progressCallback?(0.7) }, canCommit: { commitGate?.isAuthorized ?? true }) { tempPath in
                    try Self.performStreamingDecryption(
                        inputPath: inputScoped.path,
                        outputPath: tempPath,
                        using: snapshot,
                        passphrase: passphrase
                    )
                }
            }

            await MainActor.run { progressCallback?(1.0) }
            return outputPath
        }.value
    }

    /// Attempts to decrypt the given data by trying each secret key in the keyring with the provided passphrase.
    /// - Parameters:
    ///   - data: Encrypted input bytes to attempt decryption on.
    ///   - passphrase: Passphrase to use when unlocking secret keys.
    /// - Returns: A tuple `(Data, PGPKeyModel)` where `Data` is the decrypted bytes and `PGPKeyModel` is the secret key that successfully decrypted the data.
    /// - Throws: `OperationError.invalidPassphrase` when matching keys reject the passphrase, otherwise `OperationError.decryptionFailed` if none of the secret keys can decrypt the data.
    func tryDecrypt(data: Data, passphrase: String) throws -> (Data, PGPKeyModel) {
        let result = try Self.performTryDecryption(
            data: data,
            using: tryDecryptionSnapshots(),
            passphrase: passphrase
        )

        return (result.decryptedData, result.key)
    }

    func tryDecryptAsync(data: Data, passphrase: String) async throws -> (Data, PGPKeyModel) {
        let snapshots = tryDecryptionSnapshots()
        let result = try await Task.detached {
            try Self.performTryDecryption(data: data, using: snapshots, passphrase: passphrase)
        }.value

        return (result.decryptedData, result.key)
    }

    /// Attempts decryption of the file by trying available secret keys and writes the decrypted bytes to disk.
    /// - Parameters:
    ///   - file: The URL of the encrypted file to read and decrypt.
    ///   - passphrase: The passphrase used when attempting to unlock secret keys during decryption.
    ///   - outputURL: Optional destination URL or directory for the decrypted output; if `nil` a default output URL is used. If a directory is provided, the original filename with the default decrypted name is appended.
    ///   - progressCallback: Optional callback invoked with progress values (0.0, 0.3, 0.7, 1.0) during read, decrypt, and write stages.
    /// - Returns: A tuple containing the resolved output `URL` where the decrypted file was written and the `PGPKeyModel` that successfully decrypted the data.
    /// - Throws: If reading the source file, decrypting the data, or writing the decrypted output fails.
    func tryDecrypt(
        file: URL,
        passphrase: String,
        outputURL: URL? = nil,
        progressCallback: ((Double) -> Void)? = nil
    ) throws -> (URL, PGPKeyModel) {
        progressCallback?(0.0)

        let snapshots = tryDecryptionSnapshots()
        let resolvedOutputURL = Self.resolvedDecryptedOutputURL(for: file, outputURL: outputURL)
        progressCallback?(0.3)

        let key: PGPKeyModel = try SecureScopedFileAccess.withSecurityScopedAccess(to: file) { inputScoped in
            var attributed: PGPKeyModel?
            try SecureScopedFileAccess.writeFileWithoutOverwriting(
                finalOutput: resolvedOutputURL,
                scopedBy: outputURL,
                afterWrite: { progressCallback?(0.7) }
            ) { tempPath in
                attributed = try Self.performStreamingTryDecryption(
                    inputPath: inputScoped.path,
                    outputPath: tempPath,
                    using: snapshots,
                    passphrase: passphrase
                )
            }
            guard let attributed else {
                throw OperationError.decryptionFailed(underlying: nil)
            }
            return attributed
        }

        progressCallback?(1.0)
        return (resolvedOutputURL, key)
    }

    /// Attempts to decrypt the file at `file` by trying secret keys from the keyring, writes the decrypted bytes to disk, and returns the file URL and key that succeeded.
    /// - Parameters:
    ///   - file: The URL of the encrypted file to read and decrypt.
    ///   - passphrase: The passphrase to use when attempting secret-key decryption.
    ///   - outputURL: The destination file URL or directory. If `nil`, a default decrypted output path is used; if a directory, the input filename (with decrypted extension rules applied) is appended.
    ///   - progressCallback: Optional callback invoked on the main actor with progress values 0.0, 0.3, 0.7, and 1.0 to indicate stages of the operation.
    /// - Returns: A tuple containing the resolved output `URL` where the decrypted file was written and the `PGPKeyModel` that successfully decrypted the file.
    /// - Throws: An error if reading the input file, performing decryption, or writing the output file fails.
    func tryDecryptAsync(
        file: URL,
        passphrase: String,
        outputURL: URL? = nil,
        commitGate: FileCommitGate? = nil,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> (URL, PGPKeyModel) {
        progressCallback?(0.0)
        let snapshots = tryDecryptionSnapshots()
        let resolvedOutputURL = Self.resolvedDecryptedOutputURL(for: file, outputURL: outputURL)
        let result = try await Task.detached {
            await MainActor.run { progressCallback?(0.3) }

            // Stream directly between paths so neither the ciphertext nor the
            // plaintext is buffered. The commit gate still ensures no decrypted
            // file is promoted after a cancel or Lock MacPGP mid-operation.
            let key: PGPKeyModel = try SecureScopedFileAccess.withSecurityScopedAccess(to: file) { inputScoped in
                var attributed: PGPKeyModel?
                try SecureScopedFileAccess.writeFileWithoutOverwriting(
                    finalOutput: resolvedOutputURL,
                    scopedBy: outputURL,
                    afterWrite: { progressCallback?(0.7) },
                    canCommit: { commitGate?.isAuthorized ?? true }
                ) { tempPath in
                    attributed = try Self.performStreamingTryDecryption(
                        inputPath: inputScoped.path,
                        outputPath: tempPath,
                        using: snapshots,
                        passphrase: passphrase
                    )
                }
                guard let attributed else {
                    throw OperationError.decryptionFailed(underlying: nil)
                }
                return attributed
            }

            await MainActor.run { progressCallback?(1.0) }
            return TryDecryptionFileResult(outputURL: resolvedOutputURL, key: key)
        }.value

        return (result.outputURL, result.key)
    }

    /// Resolves the destination URL for an encrypted output file.
    /// - Parameters:
    ///   - file: The original input file URL to be encrypted.
    ///   - outputURL: Optional user-provided output URL; if `nil` a default is derived from `file`.
    ///   - armored: If `true` use the `.asc` extension; otherwise use `.gpg`.
    /// - Returns: The final output `URL` to write the encrypted data to. If `outputURL` is `nil` returns `file` with the chosen extension; if `outputURL` is a directory appends `file`'s basename and the chosen extension; otherwise returns `outputURL` as-is.
    private static func resolvedEncryptedOutputURL(for file: URL, outputURL: URL?, armored: Bool) -> URL {
        let outputExtension = PGPFileExtensions.encryptedOutputExtension(armored: armored)
        let defaultOutputURL = file.appendingPathExtension(outputExtension)

        guard let outputURL else {
            return defaultOutputURL
        }

        guard isDirectoryURL(outputURL) else {
            return outputURL
        }

        return outputURL
            .appendingPathComponent(file.lastPathComponent)
            .appendingPathExtension(outputExtension)
    }

    /// Determine the filesystem URL where a decrypted version of `file` should be written.
    /// - Parameters:
    ///   - file: The original file URL being decrypted; used to derive a default output filename when none is provided or when `outputURL` is a directory.
    ///   - outputURL: An optional desired output location. If `nil`, the default decrypted output URL is returned. If `outputURL` is a directory, the default filename for the decrypted file is appended; otherwise `outputURL` is returned as-is.
    /// - Returns: The resolved destination URL for the decrypted file.
    private static func resolvedDecryptedOutputURL(for file: URL, outputURL: URL?) -> URL {
        let defaultOutputURL = defaultDecryptedOutputURL(for: file)

        guard let outputURL else {
            return defaultOutputURL
        }

        guard isDirectoryURL(outputURL) else {
            return outputURL
        }

        return outputURL.appendingPathComponent(defaultOutputURL.lastPathComponent)
    }

    /// Produces the default output URL for a decrypted file.
    /// - Parameter file: The original encrypted file URL.
    /// - Returns: The URL with a supported PGP extension removed if present; otherwise the URL with the `.decrypted` extension appended.
    private static func defaultDecryptedOutputURL(for file: URL) -> URL {
        PGPFileExtensions.defaultDecryptedOutputURL(for: file)
    }

    /// Determines whether the given URL refers to a directory on disk.
    /// - Returns: `true` if the URL is a directory, `false` otherwise.
    private static func isDirectoryURL(_ url: URL) -> Bool {
        if url.hasDirectoryPath {
            return true
        }

        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues?.isDirectory == true
    }
}
