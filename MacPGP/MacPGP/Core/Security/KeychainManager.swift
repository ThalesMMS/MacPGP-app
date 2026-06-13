import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()

    private static let defaultServiceName = "com.macpgp.keychain"
    private static let migratedDataProtectionMarker = Data("MacPGP.DataProtectionKeychain".utf8)
    private let serviceName: String

    init(serviceName: String = KeychainManager.defaultServiceName) {
        self.serviceName = serviceName
    }

    func storePassphrase(_ passphrase: String, for key: PGPKeyModel) throws {
        try storePassphrase(passphrase, forKeyID: canonicalKeyID(for: key))

        if let legacyKeyID = legacyKeyID(for: key) {
            try deletePassphrase(forKeyID: legacyKeyID)
        }
    }

    func storePassphrase(_ passphrase: String, forKeyID keyID: String) throws {
        guard let passphraseData = passphrase.data(using: .utf8) else {
            throw OperationError.keychainError(underlying: nil)
        }

        try deletePassphrase(forKeyID: keyID)

        var query = passphraseQuery(forKeyID: keyID)
        query[kSecValueData as String] = passphraseData
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            return
        }

        guard isDataProtectionKeychainUnavailable(status) else {
            throw OperationError.keychainError(underlying: keychainError(from: status))
        }

        var legacyQuery = passphraseQuery(forKeyID: keyID, useDataProtectionKeychain: false)
        legacyQuery[kSecValueData as String] = passphraseData
        legacyQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let legacyStatus = SecItemAdd(legacyQuery as CFDictionary, nil)
        guard legacyStatus == errSecSuccess else {
            throw OperationError.keychainError(underlying: keychainError(from: legacyStatus))
        }
    }

    func retrievePassphrase(for key: PGPKeyModel) throws -> String? {
        let canonicalKeyID = canonicalKeyID(for: key)

        if let passphrase = try retrievePassphrase(forKeyID: canonicalKeyID) {
            return passphrase
        }

        guard let legacyKeyID = legacyKeyID(for: key),
              let legacyPassphrase = try retrievePassphrase(forKeyID: legacyKeyID) else {
            return nil
        }

        try storePassphrase(legacyPassphrase, forKeyID: canonicalKeyID)
        try deletePassphrase(forKeyID: legacyKeyID)
        return legacyPassphrase
    }

    func retrievePassphrase(forKeyID keyID: String) throws -> String? {
        if let passphrase = try retrievePassphrase(forKeyID: keyID, useDataProtectionKeychain: true) {
            return passphrase
        }

        guard let legacyPassphrase = try retrievePassphrase(forKeyID: keyID, useDataProtectionKeychain: false) else {
            return nil
        }

        if try storePassphraseInDataProtectionKeychain(legacyPassphrase, forKeyID: keyID),
           try retrieveMigratedDataProtectionPassphrase(forKeyID: keyID) == legacyPassphrase {
            try deletePassphrase(forKeyID: keyID, useDataProtectionKeychain: false)
            if try retrieveMigratedDataProtectionPassphrase(forKeyID: keyID) != legacyPassphrase {
                try storePassphraseInLegacyKeychain(legacyPassphrase, forKeyID: keyID)
            }
        }
        return legacyPassphrase
    }

    private func storePassphraseInDataProtectionKeychain(_ passphrase: String, forKeyID keyID: String) throws -> Bool {
        guard let passphraseData = passphrase.data(using: .utf8) else {
            throw OperationError.keychainError(underlying: nil)
        }

        var query = passphraseQuery(forKeyID: keyID)
        query[kSecValueData as String] = passphraseData
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        query[kSecAttrGeneric as String] = Self.migratedDataProtectionMarker

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        }

        if isDataProtectionKeychainUnavailable(status) {
            return false
        }

        throw OperationError.keychainError(underlying: keychainError(from: status))
    }

    private func storePassphraseInLegacyKeychain(_ passphrase: String, forKeyID keyID: String) throws {
        guard let passphraseData = passphrase.data(using: .utf8) else {
            throw OperationError.keychainError(underlying: nil)
        }

        var query = passphraseQuery(forKeyID: keyID, useDataProtectionKeychain: false)
        query[kSecValueData as String] = passphraseData
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            return
        }

        guard status == errSecDuplicateItem else {
            throw OperationError.keychainError(underlying: keychainError(from: status))
        }

        let updateQuery = passphraseQuery(forKeyID: keyID, useDataProtectionKeychain: false)
        let attributes: [String: Any] = [kSecValueData as String: passphraseData]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw OperationError.keychainError(underlying: keychainError(from: updateStatus))
        }
    }

    private func retrieveMigratedDataProtectionPassphrase(forKeyID keyID: String) throws -> String? {
        var query = passphraseQuery(forKeyID: keyID)
        query[kSecAttrGeneric as String] = Self.migratedDataProtectionMarker
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
        case _ where isDataProtectionKeychainUnavailable(status):
            return nil
        default:
            throw OperationError.keychainError(underlying: keychainError(from: status))
        }
    }

    private func retrievePassphrase(forKeyID keyID: String, useDataProtectionKeychain: Bool) throws -> String? {
        var query = passphraseQuery(forKeyID: keyID, useDataProtectionKeychain: useDataProtectionKeychain)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let passphrase = String(data: data, encoding: .utf8) else {
                return nil
            }
            return passphrase
        case errSecItemNotFound:
            return nil
        case _ where useDataProtectionKeychain && isDataProtectionKeychainUnavailable(status):
            return nil
        default:
            throw OperationError.keychainError(underlying: keychainError(from: status))
        }
    }

    func deletePassphrase(for key: PGPKeyModel) throws {
        try deletePassphrase(forKeyID: canonicalKeyID(for: key))

        if let legacyKeyID = legacyKeyID(for: key) {
            try deletePassphrase(forKeyID: legacyKeyID)
        }
    }

    func deletePassphrase(forKeyID keyID: String) throws {
        try deletePassphrase(forKeyID: keyID, useDataProtectionKeychain: true)
        try deletePassphrase(forKeyID: keyID, useDataProtectionKeychain: false)
    }

    private func deletePassphrase(forKeyID keyID: String, useDataProtectionKeychain: Bool) throws {
        let query = passphraseQuery(forKeyID: keyID, useDataProtectionKeychain: useDataProtectionKeychain)

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess
                || status == errSecItemNotFound
                || (useDataProtectionKeychain && isDataProtectionKeychainUnavailable(status)) else {
            throw OperationError.keychainError(underlying: keychainError(from: status))
        }
    }

    func deleteAllPassphrases() throws {
        try deleteAllPassphrases(useDataProtectionKeychain: true)
        try deleteAllPassphrases(useDataProtectionKeychain: false)
    }

    private func deleteAllPassphrases(useDataProtectionKeychain: Bool) throws {
        let query = passphraseQuery(useDataProtectionKeychain: useDataProtectionKeychain)

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess
                || status == errSecItemNotFound
                || (useDataProtectionKeychain && isDataProtectionKeychainUnavailable(status)) else {
            throw OperationError.keychainError(underlying: keychainError(from: status))
        }
    }

    func hasStoredPassphrase(forKeyID keyID: String) -> Bool {
        hasStoredPassphrase(forKeyID: keyID, useDataProtectionKeychain: true)
            || hasStoredPassphrase(forKeyID: keyID, useDataProtectionKeychain: false)
    }

    private func hasStoredPassphrase(forKeyID keyID: String, useDataProtectionKeychain: Bool) -> Bool {
        var query = passphraseQuery(forKeyID: keyID, useDataProtectionKeychain: useDataProtectionKeychain)
        query[kSecReturnData as String] = false

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func passphraseQuery(
        forKeyID keyID: String? = nil,
        useDataProtectionKeychain: Bool = true
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]

        if let keyID {
            query[kSecAttrAccount as String] = keyID
        }

        // On macOS 10.15+, generic-password accessibility attributes are honored
        // for non-synchronizable items only in the Data Protection keychain.
        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }

        return query
    }

    private func isDataProtectionKeychainUnavailable(_ status: OSStatus) -> Bool {
        status == errSecMissingEntitlement
    }

    private func canonicalKeyID(for key: PGPKeyModel) -> String {
        if !key.fingerprint.isEmpty {
            return key.fingerprint
        }

        return key.shortKeyID
    }

    private func legacyKeyID(for key: PGPKeyModel) -> String? {
        let canonicalKeyID = canonicalKeyID(for: key)
        guard !key.shortKeyID.isEmpty, key.shortKeyID != canonicalKeyID else {
            return nil
        }

        return key.shortKeyID
    }

    private func keychainError(from status: OSStatus) -> NSError {
        let message: String
        switch status {
        case errSecDuplicateItem:
            message = "Item already exists"
        case errSecItemNotFound:
            message = "Item not found"
        case errSecAuthFailed:
            message = "Authentication failed"
        case errSecInteractionNotAllowed:
            message = "User interaction not allowed"
        case errSecDecode:
            message = "Unable to decode data"
        case errSecMissingEntitlement:
            message = "Missing keychain entitlement"
        default:
            message = "Unknown keychain error (status: \(status))"
        }
        return NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
}
