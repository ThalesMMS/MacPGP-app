import Foundation
import RNPKit
import Testing
@testable import MacPGP

@Suite("KeyringPersistence Tests")
struct KeyringPersistenceTests {
    @Test("saving a secret key writes only public material to pubring")
    func savingSecretKeyWritesOnlyPublicMaterialToPubring() throws {
        let directory = makeTestDirectory()
        let persistence = KeyringPersistence(directoryOverride: directory)
        let secretKey = makeSecretKey()

        defer { try? FileManager.default.removeItem(at: directory) }

        try persistence.saveKeys([secretKey])

        let publicData = try Data(contentsOf: persistence.publicKeyringPath)
        let secretData = try Data(contentsOf: persistence.secretKeyringPath)
        let publicKeys = try RNP.readKeys(from: publicData)
        let secretKeys = try RNP.readKeys(from: secretData)

        #expect(publicKeys.count == 1)
        #expect(publicKeys.first?.fingerprint == secretKey.fingerprint)
        #expect(publicKeys.allSatisfy { !$0.isSecret })
        #expect(secretKeys.contains { $0.fingerprint == secretKey.fingerprint && $0.isSecret })
    }

    @Test("failed replacement keeps existing keyring files intact")
    func failedReplacementKeepsExistingKeyringFilesIntact() throws {
        let directory = makeTestDirectory()
        let persistence = KeyringPersistence(directoryOverride: directory)
        let originalKey = makeSecretKey()
        let replacementKey = makeSecretKey()

        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }

        try persistence.saveKeys([originalKey])

        let originalPublicData = try Data(contentsOf: persistence.publicKeyringPath)
        let originalSecretData = try Data(contentsOf: persistence.secretKeyringPath)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)

        #expect(throws: Error.self) {
            try persistence.saveKeys([replacementKey])
        }

        #expect(try Data(contentsOf: persistence.publicKeyringPath) == originalPublicData)
        #expect(try Data(contentsOf: persistence.secretKeyringPath) == originalSecretData)

        let loadedKeys = try persistence.loadKeys()

        #expect(loadedKeys.contains { $0.fingerprint == originalKey.fingerprint && $0.isSecret })
        #expect(!loadedKeys.contains { $0.fingerprint == replacementKey.fingerprint })
    }

    @Test("failed restore keeps existing keyring files intact")
    func failedRestoreKeepsExistingKeyringFilesIntact() throws {
        let directory = makeTestDirectory()
        let persistence = KeyringPersistence(directoryOverride: directory)
        let originalKey = makeSecretKey()
        let missingBackup = directory.deletingLastPathComponent()
            .appendingPathComponent("missing-backup-\(UUID().uuidString)", isDirectory: true)

        defer { try? FileManager.default.removeItem(at: directory) }

        try persistence.saveKeys([originalKey])

        let originalPublicData = try Data(contentsOf: persistence.publicKeyringPath)
        let originalSecretData = try Data(contentsOf: persistence.secretKeyringPath)

        #expect(throws: Error.self) {
            try persistence.restoreKeyring(from: missingBackup)
        }

        #expect(try Data(contentsOf: persistence.publicKeyringPath) == originalPublicData)
        #expect(try Data(contentsOf: persistence.secretKeyringPath) == originalSecretData)

        let loadedKeys = try persistence.loadKeys()

        #expect(loadedKeys.contains { $0.fingerprint == originalKey.fingerprint && $0.isSecret })
    }

    @Test("successful restore replaces the existing keyring")
    func successfulRestoreReplacesExistingKeyring() throws {
        let rootDirectory = makeTestDirectory()
        let liveDirectory = rootDirectory.appendingPathComponent("Live", isDirectory: true)
        let backupDirectory = rootDirectory.appendingPathComponent("Backup", isDirectory: true)
        let livePersistence = KeyringPersistence(directoryOverride: liveDirectory)
        let backupPersistence = KeyringPersistence(directoryOverride: backupDirectory)
        let originalKey = makeSecretKey()
        let replacementKey = makeSecretKey()

        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        try livePersistence.saveKeys([originalKey])
        try backupPersistence.saveKeys([replacementKey])

        try livePersistence.restoreKeyring(from: backupDirectory)

        let loadedKeys = try livePersistence.loadKeys()

        #expect(loadedKeys.contains { $0.fingerprint == replacementKey.fingerprint && $0.isSecret })
        #expect(!loadedKeys.contains { $0.fingerprint == originalKey.fingerprint })
    }

    private func makeTestDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPGP-KeyringPersistenceTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeSecretKey() -> Key {
        let generator = KeyGenerator()
        generator.keyAlgorithm = .RSA
        generator.keyBitsLength = 2048

        return generator.generate(
            for: "keyring-persistence-\(UUID().uuidString)@example.com",
            passphrase: "TestPassword123!"
        )
    }
}
