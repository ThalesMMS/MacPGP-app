import Foundation
import ObjectivePGP

struct KeyVerificationMetadata: Codable {
    let fingerprint: String
    let isVerified: Bool
    let verificationDate: Date?
    let verificationMethod: String?
}

struct KeyTrustMetadata: Codable {
    let fingerprint: String
    let trustLevel: TrustLevel
    let lastModified: Date
    let notes: String?
}

struct KeyringMetadata: Codable {
    var verifications: [String: KeyVerificationMetadata] = [:]
    var trusts: [String: KeyTrustMetadata] = [:]
}

final class KeyringPersistence {
    private let fileManager = FileManager.default

    var keyringDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let keyringDir = appSupport.appendingPathComponent("MacPGP/Keyring", isDirectory: true)
        return keyringDir
    }

    var publicKeyringPath: URL {
        keyringDirectory.appendingPathComponent("pubring.gpg")
    }

    var secretKeyringPath: URL {
        keyringDirectory.appendingPathComponent("secring.gpg")
    }

    var metadataPath: URL {
        keyringDirectory.appendingPathComponent("metadata.json")
    }

    init() {
        ensureDirectoryExists()
    }

    private func ensureDirectoryExists() {
        do {
            try fileManager.createDirectory(at: keyringDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create keyring directory: \(error)")
        }
    }

    func loadKeys() throws -> [Key] {
        var keys: [Key] = []

        if fileManager.fileExists(atPath: publicKeyringPath.path) {
            let publicKeys = try ObjectivePGP.readKeys(fromPath: publicKeyringPath.path)
            keys.append(contentsOf: publicKeys)
        }

        if fileManager.fileExists(atPath: secretKeyringPath.path) {
            let secretKeys = try ObjectivePGP.readKeys(fromPath: secretKeyringPath.path)
            for secretKey in secretKeys {
                if let index = keys.firstIndex(where: { $0.publicKey?.fingerprint == secretKey.publicKey?.fingerprint }) {
                    keys[index] = secretKey
                } else {
                    keys.append(secretKey)
                }
            }
        }

        return keys
    }

    func saveKeys(_ keys: [Key]) throws {
        var publicData = Data()
        var secretData = Data()

        for key in keys {
            let keyData = try key.export()
            if key.isSecret {
                secretData.append(keyData)
            }
            publicData.append(keyData)
        }

        // Only write keyring files if there's data, otherwise delete them
        if !publicData.isEmpty {
            try publicData.write(to: publicKeyringPath)
        } else {
            // Delete public keyring file if it exists and we have no keys
            if fileManager.fileExists(atPath: publicKeyringPath.path) {
                try fileManager.removeItem(at: publicKeyringPath)
            }
        }

        if !secretData.isEmpty {
            try secretData.write(to: secretKeyringPath)
        } else {
            // Delete secret keyring file if it exists and we have no secret keys
            if fileManager.fileExists(atPath: secretKeyringPath.path) {
                try fileManager.removeItem(at: secretKeyringPath)
            }
        }
    }

    func importKey(from url: URL) throws -> [Key] {
        let keys = try ObjectivePGP.readKeys(fromPath: url.path)
        return keys
    }

    func importKey(from data: Data) throws -> [Key] {
        let keys = try ObjectivePGP.readKeys(from: data)
        if keys.isEmpty {
            throw OperationError.invalidKeyData
        }
        return keys
    }

    func importKey(fromArmored string: String) throws -> [Key] {
        guard let data = string.data(using: .utf8) else {
            throw OperationError.invalidKeyData
        }
        return try ObjectivePGP.readKeys(from: data)
    }

    func exportKey(_ key: Key, armored: Bool = true) throws -> Data {
        let keyData = try key.export()
        if armored {
            let armoredString = Armor.armored(keyData, as: key.isSecret ? .secretKey : .publicKey)
            return armoredString.data(using: .utf8) ?? keyData
        } else {
            return keyData
        }
    }

    func exportPublicKey(_ key: Key, armored: Bool = true) throws -> Data {
        guard key.publicKey != nil else {
            throw OperationError.noPublicKey
        }

        let keyData = try key.export()
        if armored {
            let armoredString = Armor.armored(keyData, as: .publicKey)
            return armoredString.data(using: .utf8) ?? keyData
        } else {
            return keyData
        }
    }

    func deleteKey(withFingerprint fingerprint: String, from keys: inout [Key]) {
        keys.removeAll { key in
            key.publicKey?.fingerprint.description() == fingerprint
        }
    }

    func backupKeyring(to url: URL) throws {
        try fileManager.copyItem(at: keyringDirectory, to: url)
    }

    func restoreKeyring(from url: URL) throws {
        if fileManager.fileExists(atPath: keyringDirectory.path) {
            try fileManager.removeItem(at: keyringDirectory)
        }
        try fileManager.copyItem(at: url, to: keyringDirectory)
    }

    // MARK: - Verification Status Persistence

    func loadMetadata() -> KeyringMetadata {
        guard fileManager.fileExists(atPath: metadataPath.path) else {
            return KeyringMetadata()
        }

        do {
            let data = try Data(contentsOf: metadataPath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(KeyringMetadata.self, from: data)
        } catch {
            return KeyringMetadata()
        }
    }

    func saveMetadata(_ metadata: KeyringMetadata) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: metadataPath)
    }

    func getVerificationStatus(forFingerprint fingerprint: String) -> KeyVerificationMetadata? {
        let metadata = loadMetadata()
        return metadata.verifications[fingerprint]
    }

    func updateVerificationStatus(
        forFingerprint fingerprint: String,
        isVerified: Bool,
        verificationDate: Date?,
        verificationMethod: String?
    ) throws {
        var metadata = loadMetadata()

        let verificationMetadata = KeyVerificationMetadata(
            fingerprint: fingerprint,
            isVerified: isVerified,
            verificationDate: verificationDate,
            verificationMethod: verificationMethod
        )

        metadata.verifications[fingerprint] = verificationMetadata
        try saveMetadata(metadata)
    }

    func removeVerificationStatus(forFingerprint fingerprint: String) throws {
        var metadata = loadMetadata()
        metadata.verifications.removeValue(forKey: fingerprint)
        try saveMetadata(metadata)
    }

    // MARK: - Trust Level Persistence

    func getTrustLevel(forFingerprint fingerprint: String) -> KeyTrustMetadata? {
        let metadata = loadMetadata()
        return metadata.trusts[fingerprint]
    }

    func updateTrustLevel(
        forFingerprint fingerprint: String,
        trustLevel: TrustLevel,
        notes: String?
    ) throws {
        var metadata = loadMetadata()

        let trustMetadata = KeyTrustMetadata(
            fingerprint: fingerprint,
            trustLevel: trustLevel,
            lastModified: Date(),
            notes: notes
        )

        metadata.trusts[fingerprint] = trustMetadata
        try saveMetadata(metadata)
    }

    func removeTrustLevel(forFingerprint fingerprint: String) throws {
        var metadata = loadMetadata()
        metadata.trusts.removeValue(forKey: fingerprint)
        try saveMetadata(metadata)
    }
}
