import Foundation
import RNPKit

final class EncryptionService {
    private let keyringService: KeyringService

    init(keyringService: KeyringService) {
        self.keyringService = keyringService
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

        // Validate recipient keys are not expired or revoked
        for recipient in recipients {
            if recipient.isRevoked {
                throw OperationError.keyRevoked
            }
            if recipient.isExpired {
                throw OperationError.keyExpired
            }
        }

        let recipientKeys = recipients.compactMap { keyringService.rawKey(for: $0) }
        guard recipientKeys.count == recipients.count else {
            throw OperationError.keyNotFound(keyID: "recipient")
        }

        var signerKey: Key?
        if let signer = signer {
            guard let key = keyringService.rawKey(for: signer) else {
                throw OperationError.keyNotFound(keyID: signer.shortKeyID)
            }
            guard key.isSecret else {
                throw OperationError.noSecretKey
            }
            signerKey = key
        }

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
        } catch RNPError.missingSigningKey {
            throw OperationError.signerKeyMissing
        } catch {
            throw OperationError.encryptionFailed(underlying: error)
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

        let fileData = try SecureScopedFileAccess.readData(from: file)
        progressCallback?(0.3)

        let encryptedData = try encrypt(
            data: fileData,
            for: recipients,
            signedBy: signer,
            passphrase: passphrase,
            armored: armored
        )
        progressCallback?(0.7)

        let outputPath = resolvedEncryptedOutputURL(for: file, outputURL: outputURL, armored: armored)
        try writeData(encryptedData, to: outputPath, scopedBy: outputURL)

        progressCallback?(1.0)
        return outputPath
    }

    func decrypt(
        data: Data,
        using key: PGPKeyModel,
        passphrase: String
    ) throws -> Data {
        guard let rawKey = keyringService.rawKey(for: key) else {
            throw OperationError.keyNotFound(keyID: key.shortKeyID)
        }

        guard rawKey.isSecret else {
            throw OperationError.noSecretKey
        }

        do {
            let decryptedData = try RNP.decrypt(
                data,
                andVerifySignature: false,
                using: [rawKey],
                passphraseForKey: { _ in passphrase }
            )
            return decryptedData
        } catch RNPError.invalidPassphrase {
            throw OperationError.invalidPassphrase
        } catch {
            throw OperationError.decryptionFailed(underlying: error)
        }
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
        try await Task.detached {
            try self.decrypt(message: message, using: key, passphrase: passphrase)
        }.value
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

        let fileData = try SecureScopedFileAccess.readData(from: file)
        progressCallback?(0.3)

        let decryptedData = try decrypt(data: fileData, using: key, passphrase: passphrase)
        progressCallback?(0.7)

        let outputPath = resolvedDecryptedOutputURL(for: file, outputURL: outputURL)

        try writeData(decryptedData, to: outputPath, scopedBy: outputURL)
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
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await Task.detached {
            await MainActor.run { progressCallback?(0.0) }

            let fileData = try SecureScopedFileAccess.readData(from: file)
            await MainActor.run { progressCallback?(0.3) }

            let encryptedData = try self.encrypt(
                data: fileData,
                for: recipients,
                signedBy: signer,
                passphrase: passphrase,
                armored: armored
            )
            await MainActor.run { progressCallback?(0.7) }

            let outputPath = self.resolvedEncryptedOutputURL(for: file, outputURL: outputURL, armored: armored)
            try self.writeData(encryptedData, to: outputPath, scopedBy: outputURL)

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
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await Task.detached {
            await MainActor.run { progressCallback?(0.0) }

            let fileData = try SecureScopedFileAccess.readData(from: file)
            await MainActor.run { progressCallback?(0.3) }

            let decryptedData = try self.decrypt(data: fileData, using: key, passphrase: passphrase)
            await MainActor.run { progressCallback?(0.7) }

            let outputPath = self.resolvedDecryptedOutputURL(for: file, outputURL: outputURL)

            try self.writeData(decryptedData, to: outputPath, scopedBy: outputURL)
            await MainActor.run { progressCallback?(1.0) }
            return outputPath
        }.value
    }

    /// Attempts to decrypt the given data by trying each secret key in the keyring with the provided passphrase.
    /// - Parameters:
    ///   - data: Encrypted input bytes to attempt decryption on.
    ///   - passphrase: Passphrase to use when unlocking secret keys.
    /// - Returns: A tuple `(Data, PGPKeyModel)` where `Data` is the decrypted bytes and `PGPKeyModel` is the secret key that successfully decrypted the data.
    /// - Throws: `OperationError.decryptionFailed(underlying: nil)` if none of the secret keys can decrypt the data.
    func tryDecrypt(data: Data, passphrase: String) throws -> (Data, PGPKeyModel) {
        let secretKeys = keyringService.secretKeys()

        for keyModel in secretKeys {
            do {
                let decrypted = try decrypt(data: data, using: keyModel, passphrase: passphrase)
                return (decrypted, keyModel)
            } catch OperationError.invalidPassphrase {
                continue
            } catch {
                continue
            }
        }

        throw OperationError.decryptionFailed(underlying: nil)
    }

    func tryDecryptAsync(data: Data, passphrase: String) async throws -> (Data, PGPKeyModel) {
        try await Task.detached {
            try self.tryDecrypt(data: data, passphrase: passphrase)
        }.value
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

        let fileData = try SecureScopedFileAccess.readData(from: file)
        progressCallback?(0.3)

        let (decryptedData, key) = try tryDecrypt(data: fileData, passphrase: passphrase)
        progressCallback?(0.7)

        let resolvedOutputURL = resolvedDecryptedOutputURL(for: file, outputURL: outputURL)
        try writeData(decryptedData, to: resolvedOutputURL, scopedBy: outputURL)

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
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> (URL, PGPKeyModel) {
        try await Task.detached {
            await MainActor.run { progressCallback?(0.0) }

            let fileData = try SecureScopedFileAccess.readData(from: file)
            await MainActor.run { progressCallback?(0.3) }

            let (decryptedData, key) = try self.tryDecrypt(data: fileData, passphrase: passphrase)
            await MainActor.run { progressCallback?(0.7) }

            let resolvedOutputURL = self.resolvedDecryptedOutputURL(for: file, outputURL: outputURL)
            try self.writeData(decryptedData, to: resolvedOutputURL, scopedBy: outputURL)

            await MainActor.run { progressCallback?(1.0) }
            return (resolvedOutputURL, key)
        }.value
    }

    /// Resolves the destination URL for an encrypted output file.
    /// - Parameters:
    ///   - file: The original input file URL to be encrypted.
    ///   - outputURL: Optional user-provided output URL; if `nil` a default is derived from `file`.
    ///   - armored: If `true` use the `"asc"` extension; otherwise use `"gpg"`.
    /// - Returns: The final output `URL` to write the encrypted data to. If `outputURL` is `nil` returns `file` with the chosen extension; if `outputURL` is a directory appends `file`'s basename and the chosen extension; otherwise returns `outputURL` as-is.
    private func resolvedEncryptedOutputURL(for file: URL, outputURL: URL?, armored: Bool) -> URL {
        let defaultOutputURL = file.appendingPathExtension(armored ? "asc" : "gpg")

        guard let outputURL else {
            return defaultOutputURL
        }

        guard isDirectoryURL(outputURL) else {
            return outputURL
        }

        return outputURL
            .appendingPathComponent(file.lastPathComponent)
            .appendingPathExtension(armored ? "asc" : "gpg")
    }

    /// Determine the filesystem URL where a decrypted version of `file` should be written.
    /// - Parameters:
    ///   - file: The original file URL being decrypted; used to derive a default output filename when none is provided or when `outputURL` is a directory.
    ///   - outputURL: An optional desired output location. If `nil`, the default decrypted output URL is returned. If `outputURL` is a directory, the default filename for the decrypted file is appended; otherwise `outputURL` is returned as-is.
    /// - Returns: The resolved destination URL for the decrypted file.
    private func resolvedDecryptedOutputURL(for file: URL, outputURL: URL?) -> URL {
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
    /// - Returns: The URL with the `.asc`, `.gpg`, or `.pgp` extension removed if present; otherwise the URL with the `.decrypted` extension appended.
    private func defaultDecryptedOutputURL(for file: URL) -> URL {
        if ["asc", "gpg", "pgp"].contains(file.pathExtension.lowercased()) {
            return file.deletingPathExtension()
        }

        return file.appendingPathExtension("decrypted")
    }

    /// Determines whether the given URL refers to a directory on disk.
    /// - Returns: `true` if the URL is a directory, `false` otherwise.
    private func isDirectoryURL(_ url: URL) -> Bool {
        if url.hasDirectoryPath {
            return true
        }

        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues?.isDirectory == true
    }

    private func writeData(_ data: Data, to outputPath: URL, scopedBy outputURL: URL?) throws {
        let scopedURL = outputURL ?? outputPath

        try SecureScopedFileAccess.withSecurityScopedAccess(to: scopedURL) { _ in
            try SecureScopedFileAccess.writeData(data, to: outputPath)
        }
    }
}
