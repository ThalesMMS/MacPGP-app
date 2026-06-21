//
//  KeyringTransactionTests.swift
//  MacPGPTests
//
//  Coverage for the transactional keyring mutation boundary (issue #144):
//  a persistence failure must leave in-memory keys (and the committed on-disk
//  generation) unchanged, multi-key import is all-or-nothing, delete cannot
//  partially strip auxiliary state, and the persistence layer publishes one
//  atomic generation with staging recovery and surfaced metadata corruption.
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

// MARK: - Failure-injecting persistence fake

private final class FaultyKeyringPersistence: KeyringPersisting {
    var storedKeys: [Key]
    var failSave = false
    var importStash: [Key] = []
    private(set) var savedCount = 0
    private(set) var removedVerifications: [String] = []
    private(set) var removedTrusts: [String] = []

    let shouldSyncSharedContainer = false

    init(keys: [Key] = []) { self.storedKeys = keys }

    func loadKeys() throws -> [Key] { storedKeys }

    func saveKeys(_ keys: [Key]) throws {
        if failSave {
            throw OperationError.persistenceError(underlying: KeyringTransactionError.stagedValidationMismatch)
        }
        storedKeys = keys
        savedCount += 1
    }

    func importKey(from url: URL) throws -> [Key] { importStash }
    func importKey(from data: Data) throws -> [Key] { importStash }
    func importKey(fromArmored string: String) throws -> [Key] { importStash }
    func exportKey(_ key: Key, armored: Bool) throws -> Data { Data() }
    func exportPublicKey(_ key: Key, armored: Bool) throws -> Data { Data() }
    func deleteKey(withFingerprint fingerprint: String, from keys: inout [Key]) {
        keys.removeAll { $0.fingerprint == fingerprint }
    }
    func loadMetadata() -> KeyringMetadata { KeyringMetadata() }
    func updateVerificationStatus(forFingerprint fingerprint: String, isVerified: Bool, verificationDate: Date?, verificationMethod: String?) throws {}
    func removeVerificationStatus(forFingerprint fingerprint: String) throws { removedVerifications.append(fingerprint) }
    func updateTrustLevel(forFingerprint fingerprint: String, trustLevel: TrustLevel, notes: String?) throws {}
    func removeTrustLevel(forFingerprint fingerprint: String) throws { removedTrusts.append(fingerprint) }
}

private func makeKey() -> Key {
    let generator = KeyGenerator()
    generator.keyAlgorithm = .RSA
    generator.keyBitsLength = 2048
    return try! generator.generate(
        for: "keyring-txn-\(UUID().uuidString)@example.com",
        passphrase: "TestPassword123!"
    )
}

@MainActor
@Suite("Keyring transaction — in-memory boundary (#144)", .serialized)
struct KeyringTransactionMemoryTests {

    @Test("addKey: a persistence failure leaves in-memory keys unchanged")
    func testAddKeyRollbackOnPersistenceFailure() throws {
        let persistence = FaultyKeyringPersistence()
        let service = KeyringService(persistence: persistence, autoSave: { true })
        #expect(service.keys.isEmpty)

        persistence.failSave = true
        let key = makeKey()
        #expect(throws: Error.self) { try service.addKey(key) }

        // Memory unchanged; nothing was published.
        #expect(service.keys.isEmpty)
        #expect(persistence.storedKeys.isEmpty)
    }

    @Test("addKey: success publishes and persists")
    func testAddKeySuccess() throws {
        let persistence = FaultyKeyringPersistence()
        let service = KeyringService(persistence: persistence, autoSave: { true })

        let key = makeKey()
        try service.addKey(key)

        #expect(service.keys.contains { $0.fingerprint == key.fingerprint })
        #expect(persistence.storedKeys.contains { $0.fingerprint == key.fingerprint })
        #expect(persistence.savedCount == 1)
    }

    @Test("deleteKey: a persistence failure keeps the key and does not strip metadata")
    func testDeleteKeyRollbackKeepsKeyAndMetadata() throws {
        let existing = makeKey()
        let persistence = FaultyKeyringPersistence(keys: [existing])
        let service = KeyringService(persistence: persistence, autoSave: { true })
        guard let model = service.keys.first(where: { $0.fingerprint == existing.fingerprint }) else {
            Issue.record("seed key not loaded"); return
        }

        persistence.failSave = true
        #expect(throws: Error.self) { try service.deleteKey(model) }

        // The authoritative keyring commit failed, so the key remains AND the
        // auxiliary metadata/Keychain cleanup never ran (no partial removal).
        #expect(service.keys.contains { $0.fingerprint == existing.fingerprint })
        #expect(persistence.storedKeys.contains { $0.fingerprint == existing.fingerprint })
        #expect(persistence.removedVerifications.isEmpty)
        #expect(persistence.removedTrusts.isEmpty)
    }

    @Test("import is all-or-nothing: a persistence failure adds none of the keys")
    func testImportIsAtomic() throws {
        let persistence = FaultyKeyringPersistence()
        persistence.importStash = [makeKey(), makeKey()]
        let service = KeyringService(persistence: persistence, autoSave: { true })

        persistence.failSave = true
        #expect(throws: Error.self) { _ = try service.importKey(from: Data()) }

        #expect(service.keys.isEmpty)
        #expect(persistence.storedKeys.isEmpty)
    }

    @Test("import success adds every key in one commit")
    func testImportSuccessAtomic() throws {
        let persistence = FaultyKeyringPersistence()
        let keys = [makeKey(), makeKey()]
        persistence.importStash = keys
        let service = KeyringService(persistence: persistence, autoSave: { true })

        let imported = try service.importKey(from: Data())

        #expect(imported.count == 2)
        #expect(persistence.savedCount == 1) // single transaction, not one save per key
        for key in keys {
            #expect(service.keys.contains { $0.fingerprint == key.fingerprint })
        }
    }
}

@Suite("Keyring transaction — persistence layer (#144)")
struct KeyringTransactionPersistenceTests {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPGP-KeyringTxnTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("a committed save publishes one atomic generation containing both keyrings")
    func testAtomicGeneration() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = KeyringPersistence(directoryOverride: dir)

        try persistence.saveKeys([makeKey()])

        #expect(FileManager.default.fileExists(atPath: persistence.currentDirectory.path))
        #expect(FileManager.default.fileExists(atPath: persistence.currentDirectory.appendingPathComponent("pubring.gpg").path))
        #expect(FileManager.default.fileExists(atPath: persistence.currentDirectory.appendingPathComponent("secring.gpg").path))
        // Legacy flat files are not used by a freshly published generation.
        #expect(!FileManager.default.fileExists(atPath: persistence.legacyPublicKeyringPath.path))
    }

    @Test("legacy flat keyrings are read, then migrated to a generation on first save")
    func testLegacyMigration() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = KeyringPersistence(directoryOverride: dir)
        let key = makeKey()

        // Simulate the pre-#144 flat layout: keyrings directly under the dir.
        try PublicKeyExport.export(key).write(to: persistence.legacyPublicKeyringPath)
        try key.export().write(to: persistence.legacySecretKeyringPath)

        // Read path falls back to legacy when no generation exists.
        let loadedLegacy = try persistence.loadKeys()
        #expect(loadedLegacy.contains { $0.fingerprint == key.fingerprint })

        // First save publishes current/ and removes the legacy files.
        try persistence.saveKeys(loadedLegacy)
        #expect(FileManager.default.fileExists(atPath: persistence.currentDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: persistence.legacyPublicKeyringPath.path))
        #expect(!FileManager.default.fileExists(atPath: persistence.legacySecretKeyringPath.path))

        // A fresh instance reads the migrated generation.
        let reopened = KeyringPersistence(directoryOverride: dir)
        #expect(try reopened.loadKeys().contains { $0.fingerprint == key.fingerprint })
    }

    @Test("interrupted staging directories are discarded on startup")
    func testStaleStagingRecovery() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = KeyringPersistence(directoryOverride: dir) // creates the keyring dir

        let staging = dir.appendingPathComponent(".staging-interrupted", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        #expect(FileManager.default.fileExists(atPath: staging.path))

        // A new instance cleans leftover staging from an interrupted commit.
        _ = KeyringPersistence(directoryOverride: dir)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }

    @Test("corrupt metadata is surfaced (quarantined) rather than silently presented as empty")
    func testMetadataCorruptionQuarantined() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = KeyringPersistence(directoryOverride: dir)

        try Data("{ this is not valid json".utf8).write(to: persistence.metadataPath)

        let metadata = persistence.loadMetadata()
        #expect(metadata.verifications.isEmpty)
        #expect(metadata.trusts.isEmpty)

        // The unreadable file is preserved under a .corrupt name, not overwritten.
        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(entries.contains { $0.hasPrefix("metadata.json.corrupt-") })
        #expect(!FileManager.default.fileExists(atPath: persistence.metadataPath.path))
    }
}
