import Foundation
import ObjectivePGP

@Observable
final class KeyringService {
    private(set) var keys: [PGPKeyModel] = []
    private(set) var isLoading = false
    private(set) var lastError: OperationError?

    private let persistence = KeyringPersistence()
    private var rawKeys: [Key] = []

    init() {
        loadKeys()
    }

    func loadKeys() {
        isLoading = true
        lastError = nil

        do {
            rawKeys = try persistence.loadKeys()
            reloadKeysWithVerificationStatus()
        } catch {
            lastError = .persistenceError(underlying: error)
            keys = []
        }

        isLoading = false
    }

    func saveKeys() throws {
        try persistence.saveKeys(rawKeys)
    }

    func addKey(_ key: Key) throws {
        if let existingIndex = rawKeys.firstIndex(where: {
            $0.publicKey?.fingerprint == key.publicKey?.fingerprint
        }) {
            if key.isSecret && !rawKeys[existingIndex].isSecret {
                rawKeys[existingIndex] = key
            }
        } else {
            rawKeys.append(key)
        }

        reloadKeysWithVerificationStatus()

        if PreferencesManager.shared.autoSaveKeyring {
            try saveKeys()
        }
    }

    func importKey(from url: URL) throws -> [PGPKeyModel] {
        let importedKeys = try persistence.importKey(from: url)
        var addedModels: [PGPKeyModel] = []

        for key in importedKeys {
            try addKey(key)
            if let model = keys.first(where: { $0.fingerprint == key.publicKey?.fingerprint.description() }) {
                addedModels.append(model)
            }
        }

        return addedModels
    }

    func importKey(from data: Data) throws -> [PGPKeyModel] {
        let importedKeys = try persistence.importKey(from: data)
        var addedModels: [PGPKeyModel] = []

        for key in importedKeys {
            try addKey(key)
            if let model = keys.first(where: { $0.fingerprint == key.publicKey?.fingerprint.description() }) {
                addedModels.append(model)
            }
        }

        return addedModels
    }

    func importKey(fromArmored string: String) throws -> [PGPKeyModel] {
        let importedKeys = try persistence.importKey(fromArmored: string)
        var addedModels: [PGPKeyModel] = []

        for key in importedKeys {
            try addKey(key)
            if let model = keys.first(where: { $0.fingerprint == key.publicKey?.fingerprint.description() }) {
                addedModels.append(model)
            }
        }

        return addedModels
    }

    func exportKey(_ keyModel: PGPKeyModel, includeSecretKey: Bool = false, armored: Bool = true) throws -> Data {
        guard let key = rawKey(for: keyModel) else {
            throw OperationError.keyNotFound(keyID: keyModel.shortKeyID)
        }

        if includeSecretKey && key.isSecret {
            return try persistence.exportKey(key, armored: armored)
        } else {
            return try persistence.exportPublicKey(key, armored: armored)
        }
    }

    func deleteKey(_ keyModel: PGPKeyModel) throws {
        persistence.deleteKey(withFingerprint: keyModel.fingerprint, from: &rawKeys)

        // Remove verification status
        try? persistence.removeVerificationStatus(forFingerprint: keyModel.fingerprint)

        // Remove trust level
        try? persistence.removeTrustLevel(forFingerprint: keyModel.fingerprint)

        reloadKeysWithVerificationStatus()

        try KeychainManager.shared.deletePassphrase(forKeyID: keyModel.fingerprint)

        if PreferencesManager.shared.autoSaveKeyring {
            try saveKeys()
        }
    }

    func key(withFingerprint fingerprint: String) -> PGPKeyModel? {
        keys.first { $0.fingerprint == fingerprint }
    }

    func key(withShortID shortID: String) -> PGPKeyModel? {
        keys.first { $0.shortKeyID.hasSuffix(shortID) || shortID.hasSuffix($0.shortKeyID) }
    }

    func rawKey(for model: PGPKeyModel) -> Key? {
        rawKeys.first { $0.publicKey?.fingerprint.description() == model.fingerprint }
    }

    func secretKeys() -> [PGPKeyModel] {
        keys.filter { $0.isSecretKey }
    }

    func publicKeys() -> [PGPKeyModel] {
        keys.filter { !$0.isExpired && !$0.isRevoked }
    }

    func validKeysForEncryption() -> [PGPKeyModel] {
        keys.filter { !$0.isExpired && !$0.isRevoked }
    }

    func search(_ query: String) -> [PGPKeyModel] {
        guard !query.isEmpty else { return keys }

        let lowercasedQuery = query.lowercased()
        return keys.filter { key in
            key.displayName.lowercased().contains(lowercasedQuery) ||
            key.email?.lowercased().contains(lowercasedQuery) == true ||
            key.shortKeyID.lowercased().contains(lowercasedQuery) ||
            key.fingerprint.lowercased().contains(lowercasedQuery)
        }
    }

    // MARK: - Verification Status

    func markKeyAsVerified(_ keyModel: PGPKeyModel, method: FingerprintVerificationMethod) throws {
        try persistence.updateVerificationStatus(
            forFingerprint: keyModel.fingerprint,
            isVerified: true,
            verificationDate: Date(),
            verificationMethod: method.rawValue
        )

        reloadKeysWithVerificationStatus()
    }

    func clearVerificationStatus(_ keyModel: PGPKeyModel) throws {
        try persistence.removeVerificationStatus(forFingerprint: keyModel.fingerprint)
        reloadKeysWithVerificationStatus()
    }

    // MARK: - Trust Level

    func updateTrustLevel(_ keyModel: PGPKeyModel, trustLevel: TrustLevel, notes: String? = nil) throws {
        try persistence.updateTrustLevel(
            forFingerprint: keyModel.fingerprint,
            trustLevel: trustLevel,
            notes: notes
        )

        reloadKeysWithVerificationStatus()
    }

    func clearTrustLevel(_ keyModel: PGPKeyModel) throws {
        try persistence.removeTrustLevel(forFingerprint: keyModel.fingerprint)
        reloadKeysWithVerificationStatus()
    }

    private func reloadKeysWithVerificationStatus() {
        let metadata = persistence.loadMetadata()

        keys = rawKeys.map { key in
            let fingerprint = key.publicKey?.fingerprint.description() ?? ""

            // Load verification status
            let verification = metadata.verifications[fingerprint]
            let isVerified = verification?.isVerified ?? false
            let verificationDate = verification?.verificationDate
            let verificationMethod = verification?.verificationMethod.flatMap {
                FingerprintVerificationMethod(rawValue: $0)
            }

            // Load trust level
            let trustLevel = metadata.trusts[fingerprint]?.trustLevel ?? .unknown

            return PGPKeyModel(
                from: key,
                isVerified: isVerified,
                verificationDate: verificationDate,
                verificationMethod: verificationMethod,
                trustLevel: trustLevel
            )
        }
    }
}
