import Foundation
import RNPKit

nonisolated struct KeyVerificationMetadata: Codable {
    let fingerprint: String
    let isVerified: Bool
    let verificationDate: Date?
    let verificationMethod: String?
}

nonisolated struct KeyTrustMetadata: Codable {
    let fingerprint: String
    let trustLevel: TrustLevel
    let lastModified: Date
    let notes: String?
}

nonisolated struct KeyringMetadata: Codable {
    var verifications: [String: KeyVerificationMetadata] = [:]
    var trusts: [String: KeyTrustMetadata] = [:]
}

/// Failures specific to the transactional keyring commit (issue #144).
nonisolated enum KeyringTransactionError: Error, Equatable {
    /// The staged generation did not round-trip to the intended key set on
    /// read-back, so it was not published.
    case stagedValidationMismatch
}

nonisolated protocol KeyringPersisting {
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

nonisolated final class KeyringPersistence: KeyringPersisting {
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

    /// Atomically-published keyring generation. `current/` holds the committed
    /// `pubring.gpg` + `secring.gpg` as one unit; a new generation is staged in a
    /// sibling temp directory and swapped in via an atomic directory replace, so
    /// the two keyrings can never refer to different generations (issue #144).
    var currentDirectory: URL {
        keyringDirectory.appendingPathComponent("current", isDirectory: true)
    }

    /// Legacy flat layout (pre-#144): keyrings directly under the keyring dir.
    /// Still read on load until the first transactional save publishes `current/`.
    var legacyPublicKeyringPath: URL {
        keyringDirectory.appendingPathComponent("pubring.gpg")
    }

    var legacySecretKeyringPath: URL {
        keyringDirectory.appendingPathComponent("secring.gpg")
    }

    /// True once a committed generation exists; load/read uses it in preference to
    /// the legacy flat files.
    private var hasCurrentGeneration: Bool {
        fileManager.fileExists(atPath: currentDirectory.path)
    }

    var publicKeyringPath: URL {
        hasCurrentGeneration ? currentDirectory.appendingPathComponent("pubring.gpg") : legacyPublicKeyringPath
    }

    var secretKeyringPath: URL {
        hasCurrentGeneration ? currentDirectory.appendingPathComponent("secring.gpg") : legacySecretKeyringPath
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
        cleanupStaleStagingDirectories()
    }

    /// Removes any `.staging-*` directories left behind by an interrupted commit.
    /// A staged generation is never read (only `current/` is), so discarding it on
    /// startup recovers cleanly to the last committed generation (issue #144).
    private func cleanupStaleStagingDirectories() {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: keyringDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix(".staging-") {
            try? fileManager.removeItem(at: entry)
        }
    }

    func loadKeys() throws -> [Key] {
        let publicKeys: [Key]
        if fileManager.fileExists(atPath: publicKeyringPath.path) {
            publicKeys = try RNP.readKeys(fromPath: publicKeyringPath.path)
        } else {
            publicKeys = []
        }

        let secretKeys: [Key]
        if fileManager.fileExists(atPath: secretKeyringPath.path) {
            secretKeys = try RNP.readKeys(fromPath: secretKeyringPath.path)
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
            let fingerprint = key.fingerprint
            if !fingerprint.isEmpty,
               indexByFingerprint[fingerprint] == nil {
                indexByFingerprint[fingerprint] = index
            }
        }

        for secretKey in secretKeys {
            let fingerprint = secretKey.fingerprint
            guard !fingerprint.isEmpty else {
                if let existingIndex = mergedKeys.firstIndex(where: {
                    let publicFingerprint = $0.publicKey?.fingerprint.rawValue
                    return publicFingerprint == nil || publicFingerprint?.isEmpty == true
                }) {
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
        // Commit the keyrings as one atomically-published generation. Only after a
        // durable commit is the derived shared projection regenerated; a projection
        // failure is logged and never rolls back the committed canonical keyring.
        try commitGeneration(keys)
        syncSharedProjectionIfNeeded(keys: keys)
    }

    /// Stages a new keyring generation in a sibling temp directory, validates it by
    /// reading it back, and atomically publishes it as `current/`. Throws on any
    /// staging/validation/publish failure, leaving the previously committed
    /// generation (and therefore the caller's in-memory state) untouched.
    private func commitGeneration(_ keys: [Key]) throws {
        var publicData = Data()
        var secretData = Data()
        for key in keys {
            publicData.append(try PublicKeyExport.export(key))
            if key.isSecret {
                secretData.append(try key.export())
            }
        }

        let stagingDir = keyringDirectory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        var published = false
        defer {
            if !published, fileManager.fileExists(atPath: stagingDir.path) {
                try? fileManager.removeItem(at: stagingDir)
            }
        }

        let stagedPublic = stagingDir.appendingPathComponent("pubring.gpg")
        let stagedSecret = stagingDir.appendingPathComponent("secring.gpg")
        if !publicData.isEmpty {
            try publicData.write(to: stagedPublic, options: .atomic)
        }
        if !secretData.isEmpty {
            try secretData.write(to: stagedSecret, options: .atomic)
        }

        // Validate the staged generation before committing: read it back and
        // confirm the key set (and which keys are secret) matches what we intended.
        try validateStagedGeneration(publicPath: stagedPublic, secretPath: stagedSecret, expected: keys)

        // Atomically publish: replace (or create) current/ in one filesystem op so
        // pubring and secring can never refer to different generations.
        if fileManager.fileExists(atPath: currentDirectory.path) {
            _ = try fileManager.replaceItemAt(currentDirectory, withItemAt: stagingDir)
        } else {
            try fileManager.moveItem(at: stagingDir, to: currentDirectory)
        }
        published = true

        // current/ is now authoritative; remove any superseded legacy flat files.
        try? fileManager.removeItem(at: legacyPublicKeyringPath)
        try? fileManager.removeItem(at: legacySecretKeyringPath)
    }

    /// Reads the staged keyrings back and asserts they round-trip to exactly the
    /// intended key set, so a serialization/corruption failure is caught before
    /// the generation is published rather than after.
    private func validateStagedGeneration(publicPath: URL, secretPath: URL, expected: [Key]) throws {
        let publicKeys = fileManager.fileExists(atPath: publicPath.path)
            ? try RNP.readKeys(fromPath: publicPath.path) : []
        let secretKeys = fileManager.fileExists(atPath: secretPath.path)
            ? try RNP.readKeys(fromPath: secretPath.path) : []
        let readBack = mergeKeys(publicKeys: publicKeys, secretKeys: secretKeys)

        let expectedFingerprints = Set(expected.map(\.fingerprint).filter { !$0.isEmpty })
        let actualFingerprints = Set(readBack.map(\.fingerprint).filter { !$0.isEmpty })
        let expectedSecret = Set(expected.filter(\.isSecret).map(\.fingerprint).filter { !$0.isEmpty })
        let actualSecret = Set(readBack.filter(\.isSecret).map(\.fingerprint).filter { !$0.isEmpty })

        guard expectedFingerprints == actualFingerprints, expectedSecret == actualSecret else {
            throw OperationError.persistenceError(underlying: KeyringTransactionError.stagedValidationMismatch)
        }
    }

    private func syncSharedProjectionIfNeeded(keys: [Key]) {
        guard shouldSyncSharedContainer else { return }

        do {
            try SharedContainerSync.syncKeysToContainer(keys: keys)
        } catch {
            NSLog("[KeyringPersistence] Failed to sync keys to shared container: \(error.localizedDescription)")
        }
    }

    func importKey(from url: URL) throws -> [Key] {
        let data = try SecureScopedFileAccess.readData(from: url)
        return try importKey(from: data)
    }

    func importKey(from data: Data) throws -> [Key] {
        let keys = try RNP.readKeys(from: data)
        if keys.isEmpty {
            throw OperationError.invalidKeyData
        }
        return keys
    }

    func importKey(fromArmored string: String) throws -> [Key] {
        guard let data = string.data(using: .utf8) else {
            throw OperationError.invalidKeyData
        }
        return try RNP.readKeys(from: data)
    }

    func exportKey(_ key: Key, armored: Bool = true) throws -> Data {
        let keyData = try key.export()
        if armored {
            let armoredString = try Armor.armored(keyData, as: key.isSecret ? .secretKey : .publicKey)
            return armoredString.data(using: .utf8) ?? keyData
        } else {
            return keyData
        }
    }

    func exportPublicKey(_ key: Key, armored: Bool = true) throws -> Data {
        let keyData = try PublicKeyExport.export(key)
        if armored {
            let armoredString = try Armor.armored(keyData, as: .publicKey)
            return armoredString.data(using: .utf8) ?? keyData
        } else {
            return keyData
        }
    }

    func deleteKey(withFingerprint fingerprint: String, from keys: inout [Key]) {
        keys.removeAll { key in
            key.fingerprint == fingerprint
        }
    }

    func backupKeyring(to url: URL) throws {
        try fileManager.copyItem(at: keyringDirectory, to: url)
    }

    func restoreKeyring(from url: URL) throws {
        let parentDirectory = keyringDirectory.deletingLastPathComponent()
        let stagingDirectory = parentDirectory.appendingPathComponent(
            ".\(keyringDirectory.lastPathComponent).restore-\(UUID().uuidString)",
            isDirectory: true
        )

        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        try fileManager.copyItem(at: url, to: stagingDirectory)
        defer {
            if fileManager.fileExists(atPath: stagingDirectory.path) {
                try? fileManager.removeItem(at: stagingDirectory)
            }
        }

        if fileManager.fileExists(atPath: keyringDirectory.path) {
            _ = try fileManager.replaceItemAt(keyringDirectory, withItemAt: stagingDirectory)
        } else {
            try fileManager.moveItem(at: stagingDirectory, to: keyringDirectory)
        }
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
            // Surface corruption rather than silently presenting empty trust/
            // verification state (issue #144): preserve the unreadable file under a
            // .corrupt name (so it is not overwritten by the next save) and log it.
            // Trust/verification are auxiliary, so the keyring still loads.
            let quarantine = metadataPath.deletingLastPathComponent()
                .appendingPathComponent("metadata.json.corrupt-\(UUID().uuidString)")
            try? fileManager.moveItem(at: metadataPath, to: quarantine)
            NSLog("[KeyringPersistence] metadata.json was unreadable (\(error.localizedDescription)); quarantined to \(quarantine.lastPathComponent). Trust/verification reset to empty.")
            return KeyringMetadata()
        }
    }

    func saveMetadata(_ metadata: KeyringMetadata) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: metadataPath, options: .atomic)
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
