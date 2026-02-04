import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()

    private let serviceName = "com.macpgp.keychain"

    private init() {}

    func storePassphrase(_ passphrase: String, forKeyID keyID: String) throws {
        guard let passphraseData = passphrase.data(using: .utf8) else {
            throw OperationError.keychainError(underlying: nil)
        }

        try deletePassphrase(forKeyID: keyID)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyID,
            kSecValueData as String: passphraseData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw OperationError.keychainError(underlying: keychainError(from: status))
        }
    }

    func retrievePassphrase(forKeyID keyID: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

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
        default:
            throw OperationError.keychainError(underlying: keychainError(from: status))
        }
    }

    func deletePassphrase(forKeyID keyID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyID
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OperationError.keychainError(underlying: keychainError(from: status))
        }
    }

    func deleteAllPassphrases() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OperationError.keychainError(underlying: keychainError(from: status))
        }
    }

    func hasStoredPassphrase(forKeyID keyID: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyID,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
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
        default:
            message = "Unknown keychain error (status: \(status))"
        }
        return NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
}
