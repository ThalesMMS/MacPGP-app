import Foundation
import ObjectivePGP

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
    private var rawKeys: [Key] = []

    private let keysURL: URL = {
        let appGroupID = "group.com.macpgp.shared"
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            // Fallback to documents directory if app group is not available
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("keys.pgp")
        }
        return containerURL.appendingPathComponent("keys.pgp")
    }()

    init() {
        loadKeys()
    }

    func loadKeys() {
        do {
            guard FileManager.default.fileExists(atPath: keysURL.path) else {
                NSLog("ExtensionKeyringService: Keys file not found at \(keysURL.path)")
                keys = []
                rawKeys = []
                return
            }

            let keysData = try Data(contentsOf: keysURL)
            guard !keysData.isEmpty else {
                keys = []
                rawKeys = []
                return
            }

            rawKeys = try ObjectivePGP.readKeys(from: keysData)
            keys = rawKeys.map { PGPKeyModel(from: $0) }
            NSLog("ExtensionKeyringService: Loaded \(keys.count) keys")
        } catch {
            NSLog("ExtensionKeyringService: Failed to load keys: \(error.localizedDescription)")
            keys = []
            rawKeys = []
        }
    }

    func rawKey(for model: PGPKeyModel) -> Key? {
        rawKeys.first { $0.publicKey?.fingerprint.description() == model.fingerprint }
    }

    func secretKeys() -> [PGPKeyModel] {
        keys.filter { $0.isSecretKey }
    }

    func publicKeys() -> [PGPKeyModel] {
        keys.filter { !$0.isExpired }
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

        // Read file data
        let fileData = try Data(contentsOf: file)
        progressCallback?(0.4)

        // Encrypt the data
        var encryptedData: Data
        do {
            if let signerKey = signerKey, let passphrase = passphrase {
                var allKeys = recipientKeys
                allKeys.append(signerKey)
                encryptedData = try ObjectivePGP.encrypt(
                    fileData,
                    addSignature: true,
                    using: allKeys,
                    passphraseForKey: { _ in passphrase }
                )
            } else {
                encryptedData = try ObjectivePGP.encrypt(fileData, addSignature: false, using: recipientKeys)
            }
            progressCallback?(0.8)
        } catch {
            throw OperationError.encryptionFailed(underlying: error)
        }

        // Determine output URL
        let output = outputURL ?? file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".gpg")

        // Write encrypted data
        try encryptedData.write(to: output)
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
