//
//  KeyringServiceTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 04/02/26.
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

@MainActor
@Suite("KeyringService Tests")
struct KeyringServiceTests {
    @Test("Default test persistence uses a unique keyring directory per instance")
    func testDefaultTestPersistenceUsesUniqueDirectoryPerInstance() {
        let firstPersistence = KeyringPersistence()
        let secondPersistence = KeyringPersistence()

        #expect(firstPersistence.keyringDirectory != secondPersistence.keyringDirectory)
    }

    // MARK: - Initialization and Load Tests

    @Test("KeyringService initializes correctly")
    func testInitialization() {
        let service = KeyringService()

        #expect(!service.isLoading)
        #expect(service.lastError == nil)
        #expect(service.keys.count >= 0)
    }

    @Test("Load keys completes successfully")
    func testLoadKeys() {
        let service = KeyringService()

        service.loadKeys()

        #expect(!service.isLoading)
        #expect(service.lastError == nil)
    }

    // MARK: - Search Functionality Tests

    @Test("Search with empty query returns all keys")
    func testSearchEmptyQuery() {
        let service = KeyringService()

        let results = service.search("")

        #expect(results.count == service.keys.count)
    }

    @Test("Search with non-existent term returns no matches")
    func testSearchNoMatches() {
        let service = KeyringService()

        let results = service.search("xyz-nonexistent-unique-12345")

        let hasMatch = results.contains { key in
            key.displayName.contains("xyz-nonexistent-unique-12345") ||
            key.email?.contains("xyz-nonexistent-unique-12345") == true
        }

        #expect(!hasMatch)
    }

    @Test("Search is case insensitive")
    func testSearchCaseInsensitive() {
        let service = KeyringService()

        if let firstKey = service.keys.first, let email = firstKey.email, email.count > 3 {
            let searchTerm = String(email.prefix(3))
            let upperResults = service.search(searchTerm.uppercased())
            let lowerResults = service.search(searchTerm.lowercased())

            let upperHasKey = upperResults.contains { $0.id == firstKey.id }
            let lowerHasKey = lowerResults.contains { $0.id == firstKey.id }

            #expect(upperHasKey == lowerHasKey)
        }
    }

    // MARK: - Key Lookup Tests

    @Test("Find key by non-existent fingerprint returns nil")
    func testFindByInvalidFingerprint() {
        let service = KeyringService()

        let result = service.key(withFingerprint: "0000000000000000000000000000000000000000")

        #expect(result == nil)
    }

    @Test("Find key by non-existent short ID returns nil")
    func testFindByInvalidShortID() {
        let service = KeyringService()

        let result = service.key(withShortID: "00000000")

        #expect(result == nil)
    }

    @Test("Find key by valid fingerprint returns key")
    func testFindByFingerprint() {
        let service = KeyringService()

        if let firstKey = service.keys.first {
            let found = service.key(withFingerprint: firstKey.fingerprint)

            #expect(found != nil)
            #expect(found?.id == firstKey.id)
        }
    }

    @Test("Find key by valid short ID returns key")
    func testFindByShortID() {
        let service = KeyringService()

        if let firstKey = service.keys.first {
            let shortID = String(firstKey.shortKeyID.suffix(8))
            let found = service.key(withShortID: shortID)

            #expect(found != nil)
        }
    }

    // MARK: - Filter Tests

    @Test("Secret keys filter returns only secret keys")
    func testSecretKeysFilter() {
        let service = KeyringService()

        let secretKeys = service.secretKeys()

        for key in secretKeys {
            #expect(key.isSecretKey == true)
        }
    }

    @Test("Public keys filter returns only non-expired keys")
    func testPublicKeysFilter() {
        let service = KeyringService()

        let publicKeys = service.publicKeys()

        for key in publicKeys {
            #expect(key.isExpired == false)
        }
    }

    @Test("Raw key lookup returns matching RNP key")
    func testRawKeyLookup() {
        let service = KeyringService()

        if let firstKey = service.keys.first {
            let rawKey = service.rawKey(for: firstKey)

            #expect(rawKey != nil)
            #expect(rawKey?.publicKey?.fingerprint.description == firstKey.fingerprint)
        }
    }

    // MARK: - Error Handling Tests

    @Test("Import invalid data throws error")
    func testImportInvalidData() {
        let service = KeyringService()

        let invalidData = "Not a valid PGP key data".data(using: .utf8)!

        #expect(throws: Error.self) {
            try service.importKey(from: invalidData)
        }
    }

    @Test("Export non-existent key throws error")
    func testExportNonExistentKey() {
        let service = KeyringService()

        // Create a key model that doesn't exist in the keyring
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let tempKey = keyGen.generate(for: "nonexistent@test.local", passphrase: "pass")
        let fakeModel = PGPKeyModel(from: tempKey)

        #expect(throws: OperationError.self) {
            try service.exportKey(fakeModel)
        }
    }

    // MARK: - Integration Tests

    @Test("Add key workflow")
    func testAddKey() async throws {
        let service = KeyringService()
        let initialCount = service.keys.count

        // Generate a test key
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let testKey = keyGen.generate(for: "test-add@example.com", passphrase: "test")

        // Add the key
        try service.addKey(testKey)

        #expect(service.keys.count == initialCount + 1)

        let addedKey = service.keys.first { $0.email == "test-add@example.com" }
        #expect(addedKey != nil)

        // Cleanup
        if let key = addedKey {
            try? service.deleteKey(key)
        }
    }

    @Test("Delete key workflow")
    func testDeleteKey() async throws {
        let service = KeyringService()

        // Clean up any existing keys with test email from previous runs
        let existingKeys = service.keys.filter { $0.email == "test-delete@example.com" }
        for key in existingKeys {
            try? service.deleteKey(key)
        }

        // Add a test key
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let testKey = keyGen.generate(for: "test-delete@example.com", passphrase: "test")
        try service.addKey(testKey)

        guard let keyToDelete = service.keys.first(where: { $0.email == "test-delete@example.com" }) else {
            Issue.record("Test key not found")
            return
        }

        let countBeforeDelete = service.keys.count

        // Delete the key
        try service.deleteKey(keyToDelete)

        #expect(service.keys.count == countBeforeDelete - 1)

        let deletedKey = service.keys.first { $0.email == "test-delete@example.com" }
        #expect(deletedKey == nil)
    }

    @Test("Import key from armored string workflow")
    func testImportArmoredKey() async throws {
        let service = KeyringService()
        let initialCount = service.keys.count

        // Generate and armor a test key
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let testKey = keyGen.generate(for: "test-import@example.com", passphrase: "test")
        let keyData = try testKey.export()
        let armoredKey = try Armor.armored(keyData, as: .publicKey)

        // Import the key
        let imported = try service.importKey(fromArmored: armoredKey)

        #expect(imported.count > 0)
        #expect(service.keys.count == initialCount + imported.count)

        // Cleanup
        for key in imported {
            try? service.deleteKey(key)
        }
    }

    @Test("Export key workflow")
    func testExportKey() async throws {
        let service = KeyringService()

        // Add a test key
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let testKey = keyGen.generate(for: "test-export@example.com", passphrase: "test")
        try service.addKey(testKey)

        guard let keyToExport = service.keys.first(where: { $0.email == "test-export@example.com" }) else {
            Issue.record("Test key not found")
            return
        }

        // Export the key
        let exportedData = try service.exportKey(keyToExport, includeSecretKey: false, armored: true)

        #expect(!exportedData.isEmpty)

        if let exportedString = String(data: exportedData, encoding: .utf8) {
            #expect(exportedString.contains("-----BEGIN PGP"))
        }

        // Cleanup
        try? service.deleteKey(keyToExport)
    }

    @Test("Search finds added key")
    func testSearchFindsKey() async throws {
        let service = KeyringService()

        // Add a test key
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let testKey = keyGen.generate(for: "test-search@example.com", passphrase: "test")
        try service.addKey(testKey)

        // Search for the key
        let results = service.search("test-search")

        #expect(results.count > 0)
        #expect(results.contains { $0.email == "test-search@example.com" })

        // Cleanup
        if let key = service.keys.first(where: { $0.email == "test-search@example.com" }) {
            try? service.deleteKey(key)
        }
    }

    // MARK: - updateTrustLevel In-Place Update Tests

    @Test("updateTrustLevel updates key in-place without full reload")
    func testUpdateTrustLevelUpdatesKeyInPlace() throws {
        let service = KeyringService()

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let rawKey = keyGen.generate(for: "trust-inplace@test.local", passphrase: "pass")
        try service.addKey(rawKey)

        guard let addedKey = service.keys.first(where: { $0.email == "trust-inplace@test.local" }) else {
            Issue.record("Test key not found after add")
            return
        }

        defer { try? service.deleteKey(addedKey) }

        #expect(addedKey.trustLevel == .unknown)

        try service.updateTrustLevel(addedKey, trustLevel: .full)

        let updatedKey = service.keys.first(where: { $0.fingerprint == addedKey.fingerprint })
        #expect(updatedKey?.trustLevel == .full)
    }

    @Test("updateTrustLevel sets the correct trust level on the key")
    func testUpdateTrustLevelSetsCorrectLevel() throws {
        let service = KeyringService()

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let rawKey = keyGen.generate(for: "trust-level-set@test.local", passphrase: "pass")
        try service.addKey(rawKey)

        guard let addedKey = service.keys.first(where: { $0.email == "trust-level-set@test.local" }) else {
            Issue.record("Test key not found after add")
            return
        }

        defer { try? service.deleteKey(addedKey) }

        let trustLevels: [TrustLevel] = [.never, .marginal, .full, .ultimate]
        for level in trustLevels {
            try service.updateTrustLevel(addedKey, trustLevel: level)
            let result = service.keys.first(where: { $0.fingerprint == addedKey.fingerprint })
            #expect(result?.trustLevel == level)
        }
    }

    @Test("updateTrustLevel does not change count of keys in keyring")
    func testUpdateTrustLevelPreservesKeyCount() throws {
        let service = KeyringService()

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let rawKey = keyGen.generate(for: "trust-count-preserve@test.local", passphrase: "pass")
        try service.addKey(rawKey)

        guard let addedKey = service.keys.first(where: { $0.email == "trust-count-preserve@test.local" }) else {
            Issue.record("Test key not found after add")
            return
        }

        defer { try? service.deleteKey(addedKey) }

        let countBefore = service.keys.count
        try service.updateTrustLevel(addedKey, trustLevel: .marginal)
        #expect(service.keys.count == countBefore)
    }

    @Test("updateTrustLevel only modifies the targeted key")
    func testUpdateTrustLevelOnlyModifiesTargetKey() throws {
        let service = KeyringService()

        let keyGen1 = KeyGenerator()
        keyGen1.keyBitsLength = 2048
        let rawKey1 = keyGen1.generate(for: "trust-target-1@test.local", passphrase: "pass")
        try service.addKey(rawKey1)

        let keyGen2 = KeyGenerator()
        keyGen2.keyBitsLength = 2048
        let rawKey2 = keyGen2.generate(for: "trust-target-2@test.local", passphrase: "pass")
        try service.addKey(rawKey2)

        guard let key1 = service.keys.first(where: { $0.email == "trust-target-1@test.local" }),
              let key2 = service.keys.first(where: { $0.email == "trust-target-2@test.local" }) else {
            Issue.record("Test keys not found")
            return
        }

        defer {
            if let k = service.keys.first(where: { $0.email == "trust-target-1@test.local" }) { try? service.deleteKey(k) }
            if let k = service.keys.first(where: { $0.email == "trust-target-2@test.local" }) { try? service.deleteKey(k) }
        }

        try service.updateTrustLevel(key1, trustLevel: .full)

        let updatedKey1 = service.keys.first(where: { $0.fingerprint == key1.fingerprint })
        let updatedKey2 = service.keys.first(where: { $0.fingerprint == key2.fingerprint })

        #expect(updatedKey1?.trustLevel == .full)
        #expect(updatedKey2?.trustLevel == .unknown)
    }

    // MARK: - clearTrustLevel In-Place Update Tests

    @Test("clearTrustLevel resets key trust level to unknown in-place")
    func testClearTrustLevelResetsToUnknown() throws {
        let service = KeyringService()

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let rawKey = keyGen.generate(for: "trust-clear@test.local", passphrase: "pass")
        try service.addKey(rawKey)

        guard let addedKey = service.keys.first(where: { $0.email == "trust-clear@test.local" }) else {
            Issue.record("Test key not found after add")
            return
        }

        defer { try? service.deleteKey(addedKey) }

        try service.updateTrustLevel(addedKey, trustLevel: .full)

        let afterUpdate = service.keys.first(where: { $0.fingerprint == addedKey.fingerprint })
        #expect(afterUpdate?.trustLevel == .full)

        try service.clearTrustLevel(addedKey)

        let afterClear = service.keys.first(where: { $0.fingerprint == addedKey.fingerprint })
        #expect(afterClear?.trustLevel == .unknown)
    }

    @Test("clearTrustLevel does not change count of keys in keyring")
    func testClearTrustLevelPreservesKeyCount() throws {
        let service = KeyringService()

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let rawKey = keyGen.generate(for: "trust-clear-count@test.local", passphrase: "pass")
        try service.addKey(rawKey)

        guard let addedKey = service.keys.first(where: { $0.email == "trust-clear-count@test.local" }) else {
            Issue.record("Test key not found after add")
            return
        }

        defer { try? service.deleteKey(addedKey) }

        try service.updateTrustLevel(addedKey, trustLevel: .marginal)

        let countBefore = service.keys.count
        try service.clearTrustLevel(addedKey)
        #expect(service.keys.count == countBefore)
    }

    @Test("clearTrustLevel only resets the targeted key")
    func testClearTrustLevelOnlyResetsTargetKey() throws {
        let service = KeyringService()

        let keyGen1 = KeyGenerator()
        keyGen1.keyBitsLength = 2048
        let rawKey1 = keyGen1.generate(for: "trust-clear-t1@test.local", passphrase: "pass")
        try service.addKey(rawKey1)

        let keyGen2 = KeyGenerator()
        keyGen2.keyBitsLength = 2048
        let rawKey2 = keyGen2.generate(for: "trust-clear-t2@test.local", passphrase: "pass")
        try service.addKey(rawKey2)

        guard let key1 = service.keys.first(where: { $0.email == "trust-clear-t1@test.local" }),
              let key2 = service.keys.first(where: { $0.email == "trust-clear-t2@test.local" }) else {
            Issue.record("Test keys not found")
            return
        }

        defer {
            if let k = service.keys.first(where: { $0.email == "trust-clear-t1@test.local" }) { try? service.deleteKey(k) }
            if let k = service.keys.first(where: { $0.email == "trust-clear-t2@test.local" }) { try? service.deleteKey(k) }
        }

        try service.updateTrustLevel(key1, trustLevel: .full)
        try service.updateTrustLevel(key2, trustLevel: .marginal)

        try service.clearTrustLevel(key1)

        let clearedKey1 = service.keys.first(where: { $0.fingerprint == key1.fingerprint })
        let unchangedKey2 = service.keys.first(where: { $0.fingerprint == key2.fingerprint })

        #expect(clearedKey1?.trustLevel == .unknown)
        #expect(unchangedKey2?.trustLevel == .marginal)
    }
}
