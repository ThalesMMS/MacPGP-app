import Foundation
import RNPKit

/// Lightweight service provider for the Share Extension
/// Provides access to encryption functionality without the full app's service layer
final class ExtensionServices {

    // MARK: - Singleton

    static let shared = ExtensionServices()

    // MARK: - Services

    let keyringService: ExtensionKeyringService
    let encryptionService: ExtensionEncryptionService

    // MARK: - Initialization

    private init() {
        // Initialize keyring service with extension-specific configuration
        self.keyringService = ExtensionKeyringService()

        // Initialize encryption service with the keyring
        self.encryptionService = ExtensionEncryptionService(keyringService: keyringService)
    }

    // MARK: - Helper Methods

    /// Reloads keys from persistent storage
    /// Call this when the extension launches to ensure keys are up to date
    func reloadKeys() {
        keyringService.loadKeys()
    }
}

// MARK: - Extension Keyring Service

@Observable
final class ExtensionKeyringService {
    private(set) var keys: [PGPKeyModel] = []
    private(set) var keyAvailabilityMessage: String?
    private var rawKeys: [Key] = []

    init() {
        loadKeys()
    }

    func loadKeys() {
        do {
            rawKeys = try SharedKeyringLoader.loadKeys()
            guard !rawKeys.isEmpty else {
                clearKeys(message: "Open MacPGP to sync your keyring, then try sharing again.")
                return
            }
            keys = rawKeys.map { PGPKeyModel(from: $0) }
            keyAvailabilityMessage = nil
            NSLog("ExtensionKeyringService: Loaded \(keys.count) keys")
        } catch {
            NSLog("ExtensionKeyringService: Failed to load keys: \(error.localizedDescription)")
            clearKeys(message: "Open MacPGP to refresh your keys, then try sharing again.")
        }
    }

    private func clearKeys(message: String) {
        keys = []
        rawKeys = []
        keyAvailabilityMessage = message
    }

    func rawKey(for model: PGPKeyModel) -> Key? {
        rawKeys.first { $0.fingerprint == model.fingerprint }
    }

    func secretKeys() -> [PGPKeyModel] {
        keys.filter { $0.isSecretKey }
    }

    func publicKeys() -> [PGPKeyModel] {
        keys.filter(\.isUsableForEncryption)
    }
}

// MARK: - Extension Encryption Service

final class ExtensionEncryptionService {
    private let keyringService: ExtensionKeyringService

    init(keyringService: ExtensionKeyringService) {
        self.keyringService = keyringService
    }

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

        guard !recipients.isEmpty else {
            throw OperationError.recipientKeyMissing
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

        progressCallback?(0.2)

        let outputExtension = PGPFileExtensions.encryptedOutputExtension(armored: armored)
        let output = outputURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(file.lastPathComponent).\(outputExtension)")

        // Stream encryption directly between paths (issue #142): a large shared
        // file is never loaded into a Data, and the encrypted output is never
        // buffered. Write to a sibling temp file, then atomically promote it so a
        // failure/cancellation never leaves a partial encrypted output behind.
        let tempOutput = output.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).part")

        func discardPartial() {
            try? FileManager.default.removeItem(at: tempOutput)
        }

        do {
            if let signerKey, let passphrase {
                var allKeys = recipientKeys
                allKeys.append(signerKey)
                try RNP.encryptFile(
                    inputPath: file.path,
                    outputPath: tempOutput.path,
                    armored: armored,
                    addSignature: true,
                    using: allKeys,
                    passphraseForKey: { _ in passphrase }
                )
            } else {
                try RNP.encryptFile(
                    inputPath: file.path,
                    outputPath: tempOutput.path,
                    armored: armored,
                    addSignature: false,
                    using: recipientKeys
                )
            }
            progressCallback?(0.8)
        } catch RNPError.missingSigningKey {
            discardPartial()
            throw OperationError.signerKeyMissing
        } catch {
            discardPartial()
            throw OperationError.encryptionFailed(underlying: error)
        }

        do {
            if FileManager.default.fileExists(atPath: output.path) {
                _ = try FileManager.default.replaceItemAt(output, withItemAt: tempOutput)
            } else {
                try FileManager.default.moveItem(at: tempOutput, to: output)
            }
        } catch {
            discardPartial()
            throw OperationError.fileAccessError(path: output.path)
        }
        progressCallback?(1.0)

        return output
    }

    func encryptAsync(
        file: URL,
        for recipients: [PGPKeyModel],
        signedBy signer: PGPKeyModel? = nil,
        passphrase: String? = nil,
        outputURL: URL? = nil,
        armored: Bool = false,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let result = try encrypt(
                    file: file,
                    for: recipients,
                    signedBy: signer,
                    passphrase: passphrase,
                    outputURL: outputURL,
                    armored: armored,
                    progressCallback: { progress in
                        progressCallback?(progress)
                    }
                )
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
