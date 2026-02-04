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
            keys = rawKeys.map { PGPKeyModel(from: $0) }
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

        keys = rawKeys.map { PGPKeyModel(from: $0) }

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
        keys = rawKeys.map { PGPKeyModel(from: $0) }

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
        keys.filter { !$0.isExpired }
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
}
