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

protocol KeyringPersisting {
    var shouldSyncSharedContainer: Bool { get }

    func loadKeys() throws -> [Key]
    func saveKeys(_ keys: [Key]) throws
    func importKey(from url: URL) throws -> [Key]
    func importKey(from data: Data) throws -> [Key]
    func importKey(fromArmored string: String) throws -> [Key]
    func exportKey(_ key: Key, armored: Bool) throws -> Data
    func exportPublicKey(_ key: Key, armored: Bool) throws -> Data
    func deleteKey(withFingerprint fingerprint: String, from keys: inout [Key])
    func loadMetadata() -> KeyringMetadata
    func updateVerificationStatus(
        forFingerprint fingerprint: String,
        isVerified: Bool,
        verificationDate: Date?,
        verificationMethod: String?
    ) throws
    func removeVerificationStatus(forFingerprint fingerprint: String) throws
    func updateTrustLevel(
        forFingerprint fingerprint: String,
        trustLevel: TrustLevel,
        notes: String?
    ) throws
    func removeTrustLevel(forFingerprint fingerprint: String) throws
}

final class KeyringPersistence: KeyringPersisting {
    private let fileManager = FileManager.default
    private let directoryOverride: URL?
    private let testDirectory: URL?

    private static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil ||
        NSClassFromString("XCTestCase") != nil

    var shouldSyncSharedContainer: Bool {
        directoryOverride == nil && !Self.isRunningTests
    }

    var keyringDirectory: URL {
        if let directoryOverride {
            return directoryOverride
        }

        if let testDirectory {
            return testDirectory
        }

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

    init(directoryOverride: URL? = nil) {
        self.directoryOverride = directoryOverride
        if directoryOverride == nil && Self.isRunningTests {
            let sessionIdentifier = ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] ??
                ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]?
                    .replacingOccurrences(of: "/", with: "-") ??
                UUID().uuidString
            self.testDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MacPGPTests-\(sessionIdentifier)", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("Keyring", isDirectory: true)
        } else {
            self.testDirectory = nil
        }
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
        let publicKeys: [Key]
        if fileManager.fileExists(atPath: publicKeyringPath.path) {
            publicKeys = try ObjectivePGP.readKeys(fromPath: publicKeyringPath.path)
        } else {
            publicKeys = []
        }

        let secretKeys: [Key]
        if fileManager.fileExists(atPath: secretKeyringPath.path) {
            secretKeys = try ObjectivePGP.readKeys(fromPath: secretKeyringPath.path)
        } else {
            secretKeys = []
        }

        return mergeKeys(publicKeys: publicKeys, secretKeys: secretKeys)
    }

    private func mergeKeys(publicKeys: [Key], secretKeys: [Key]) -> [Key] {
        guard !secretKeys.isEmpty else { return publicKeys }

        var mergedKeys = publicKeys
        var indexByFingerprint: [String: Int] = [:]
        indexByFingerprint.reserveCapacity(publicKeys.count + secretKeys.count)

        for (index, key) in publicKeys.enumerated() {
            if let fingerprint = key.publicKey?.fingerprint.description(),
               indexByFingerprint[fingerprint] == nil {
                indexByFingerprint[fingerprint] = index
            }
        }

        for secretKey in secretKeys {
            guard let fingerprint = secretKey.publicKey?.fingerprint.description() else {
                if let existingIndex = mergedKeys.firstIndex(where: { $0.publicKey?.fingerprint == nil }) {
                    mergedKeys[existingIndex] = secretKey
                } else {
                    mergedKeys.append(secretKey)
                }
                continue
            }

            if let existingIndex = indexByFingerprint[fingerprint] {
                mergedKeys[existingIndex] = secretKey
            } else {
                indexByFingerprint[fingerprint] = mergedKeys.count
                mergedKeys.append(secretKey)
            }
        }

        return mergedKeys
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

        guard shouldSyncSharedContainer else { return }

        do {
            try SharedContainerSync.syncKeysToContainer(keys: keys)
        } catch {
            NSLog("[KeyringPersistence] Failed to sync keys to shared container: \(error.localizedDescription)")
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
