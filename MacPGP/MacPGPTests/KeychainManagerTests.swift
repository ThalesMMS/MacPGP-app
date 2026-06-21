import Foundation
import RNPKit
import Security
import Testing
@testable import MacPGP

@Suite("KeychainManager Tests")
struct KeychainManagerTests {
    private static let migratedDataProtectionMarker = Data("MacPGP.DataProtectionKeychain".utf8)

    @Test("generated key passphrase is stored, retrieved, and deleted by canonical key")
    func generatedKeyPassphraseRoundTripsByCanonicalKey() throws {
        let key = makeGeneratedKey()
        let manager = makeManager()
        let passphrase = "KeychainTest-\(UUID().uuidString)"

        cleanupPassphrase(for: key, manager: manager)
        defer { cleanupPassphrase(for: key, manager: manager) }

        try manager.storePassphrase(passphrase, for: key)

        #expect(try manager.retrievePassphrase(for: key) == passphrase)
        #expect(try manager.retrievePassphrase(forKeyID: key.fingerprint) == passphrase)

        try manager.deletePassphrase(for: key)

        #expect(try manager.retrievePassphrase(for: key) == nil)
        #expect(try manager.retrievePassphrase(forKeyID: key.fingerprint) == nil)
    }

    @Test("legacy short key ID passphrase migrates to fingerprint on retrieval")
    func legacyShortKeyIDPassphraseMigratesToFingerprint() throws {
        let key = makeGeneratedKey()
        let manager = makeManager()
        let passphrase = "LegacyKeychainTest-\(UUID().uuidString)"

        cleanupPassphrase(for: key, manager: manager)
        defer { cleanupPassphrase(for: key, manager: manager) }

        try manager.storePassphrase(passphrase, forKeyID: key.shortKeyID)

        #expect(try manager.retrievePassphrase(for: key) == passphrase)
        #expect(try manager.retrievePassphrase(forKeyID: key.fingerprint) == passphrase)
        #expect(try manager.retrievePassphrase(forKeyID: key.shortKeyID) == nil)
    }

    @Test("stores passphrases in the data protection keychain")
    func storesPassphrasesInDataProtectionKeychain() throws {
        let serviceName = makeServiceName()
        let manager = KeychainManager(serviceName: serviceName)
        let keyID = "data-protection-\(UUID().uuidString)"
        let passphrase = "DataProtectionKeychainTest-\(UUID().uuidString)"
        let supportsDataProtectionKeychain = dataProtectionKeychainIsAvailable(serviceName: serviceName)
        defer { cleanupPassphrase(serviceName: serviceName, keyID: keyID) }

        try manager.storePassphrase(passphrase, forKeyID: keyID)

        #expect(manager.hasStoredPassphrase(forKeyID: keyID))
        #expect(try manager.retrievePassphrase(forKeyID: keyID) == passphrase)
        if supportsDataProtectionKeychain {
            #expect(try rawPassphrase(serviceName: serviceName, keyID: keyID, useDataProtectionKeychain: true) == passphrase)
        } else {
            #expect(try rawPassphrase(serviceName: serviceName, keyID: keyID, useDataProtectionKeychain: false) == passphrase)
        }
    }

    @Test("legacy login keychain passphrase migrates to data protection keychain")
    func legacyLoginKeychainPassphraseMigratesToDataProtectionKeychain() throws {
        let serviceName = makeServiceName()
        let manager = KeychainManager(serviceName: serviceName)
        let keyID = "legacy-login-\(UUID().uuidString)"
        let passphrase = "LegacyLoginKeychainTest-\(UUID().uuidString)"
        defer { cleanupPassphrase(serviceName: serviceName, keyID: keyID) }

        try storeRawPassphrase(
            passphrase,
            serviceName: serviceName,
            keyID: keyID,
            useDataProtectionKeychain: false
        )

        #expect(try manager.retrievePassphrase(forKeyID: keyID) == passphrase)
        if try rawPassphrase(
            serviceName: serviceName,
            keyID: keyID,
            useDataProtectionKeychain: true,
            generic: Self.migratedDataProtectionMarker
        ) == passphrase {
            #expect(try rawPassphrase(serviceName: serviceName, keyID: keyID, useDataProtectionKeychain: false) == nil)
        } else {
            #expect(try rawPassphrase(serviceName: serviceName, keyID: keyID, useDataProtectionKeychain: false) == passphrase)
        }
    }

    @Test("deleteAll removes data protection and legacy login keychain passphrases")
    func deleteAllRemovesDataProtectionAndLegacyLoginKeychainPassphrases() throws {
        let serviceName = makeServiceName()
        let manager = KeychainManager(serviceName: serviceName)
        let dataProtectionKeyID = "delete-all-data-protection-\(UUID().uuidString)"
        let legacyKeyID = "delete-all-legacy-\(UUID().uuidString)"
        let supportsDataProtectionKeychain = dataProtectionKeychainIsAvailable(serviceName: serviceName)
        defer {
            cleanupPassphrase(serviceName: serviceName, keyID: dataProtectionKeyID)
            cleanupPassphrase(serviceName: serviceName, keyID: legacyKeyID)
        }

        if supportsDataProtectionKeychain {
            try storeRawPassphrase(
                "delete-all-data-protection",
                serviceName: serviceName,
                keyID: dataProtectionKeyID,
                useDataProtectionKeychain: true
            )
        }
        try storeRawPassphrase(
            "delete-all-legacy",
            serviceName: serviceName,
            keyID: legacyKeyID,
            useDataProtectionKeychain: false
        )

        try manager.deleteAllPassphrases()

        if supportsDataProtectionKeychain {
            #expect(try rawPassphrase(serviceName: serviceName, keyID: dataProtectionKeyID, useDataProtectionKeychain: true) == nil)
        }
        #expect(try rawPassphrase(serviceName: serviceName, keyID: legacyKeyID, useDataProtectionKeychain: false) == nil)
    }

    private func makeGeneratedKey() -> PGPKeyModel {
        let generator = KeyGenerator()
        generator.keyAlgorithm = .RSA
        generator.keyBitsLength = 2048

        let key = try! generator.generate(
            for: "keychain-manager-\(UUID().uuidString)@example.com",
            passphrase: "TestPassword123!"
        )

        return PGPKeyModel(from: key)
    }

    private func makeManager() -> KeychainManager {
        KeychainManager(serviceName: makeServiceName())
    }

    private func makeServiceName() -> String {
        "com.macpgp.keychain.tests.\(UUID().uuidString)"
    }

    private func cleanupPassphrase(for key: PGPKeyModel, manager: KeychainManager) {
        try? manager.deletePassphrase(forKeyID: key.fingerprint)
        try? manager.deletePassphrase(forKeyID: key.shortKeyID)
    }

    private func cleanupPassphrase(serviceName: String, keyID: String) {
        try? deleteRawPassphrase(serviceName: serviceName, keyID: keyID, useDataProtectionKeychain: true)
        try? deleteRawPassphrase(serviceName: serviceName, keyID: keyID, useDataProtectionKeychain: false)
    }

    private func dataProtectionKeychainIsAvailable(serviceName: String) -> Bool {
        let keyID = "data-protection-probe-\(UUID().uuidString)"
        var query = rawPassphraseQuery(
            serviceName: serviceName,
            keyID: keyID,
            useDataProtectionKeychain: true
        )
        query[kSecValueData as String] = Data("probe".utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            return false
        }

        try? deleteRawPassphrase(
            serviceName: serviceName,
            keyID: keyID,
            useDataProtectionKeychain: true
        )
        return true
    }

    private func storeRawPassphrase(
        _ passphrase: String,
        serviceName: String,
        keyID: String,
        useDataProtectionKeychain: Bool
    ) throws {
        try deleteRawPassphrase(
            serviceName: serviceName,
            keyID: keyID,
            useDataProtectionKeychain: useDataProtectionKeychain
        )

        var query = rawPassphraseQuery(
            serviceName: serviceName,
            keyID: keyID,
            useDataProtectionKeychain: useDataProtectionKeychain
        )
        query[kSecValueData as String] = Data(passphrase.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func rawPassphrase(
        serviceName: String,
        keyID: String,
        useDataProtectionKeychain: Bool,
        generic: Data? = nil
    ) throws -> String? {
        var query = rawPassphraseQuery(
            serviceName: serviceName,
            keyID: keyID,
            useDataProtectionKeychain: useDataProtectionKeychain,
            generic: generic
        )
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func deleteRawPassphrase(
        serviceName: String,
        keyID: String,
        useDataProtectionKeychain: Bool
    ) throws {
        let query = rawPassphraseQuery(
            serviceName: serviceName,
            keyID: keyID,
            useDataProtectionKeychain: useDataProtectionKeychain
        )

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func rawPassphraseQuery(
        serviceName: String,
        keyID: String,
        useDataProtectionKeychain: Bool,
        generic: Data? = nil
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyID
        ]

        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        if let generic {
            query[kSecAttrGeneric as String] = generic
        }

        return query
    }
}
