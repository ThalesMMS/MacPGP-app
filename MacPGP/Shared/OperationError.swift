import Foundation

enum OperationError: LocalizedError {
    case keyNotFound(keyID: String)
    case invalidPassphrase
    case passphraseRequired
    case encryptionFailed(underlying: Error?)
    case decryptionFailed(underlying: Error?)
    case signingFailed(underlying: Error?)
    case verificationFailed(underlying: Error?)
    case keyGenerationFailed(underlying: Error?)
    case keyImportFailed(underlying: Error?)
    case keyExportFailed(underlying: Error?)
    case keychainError(underlying: Error?)
    case persistenceError(underlying: Error?)
    case invalidKeyData
    case keyExpired
    case noPublicKey
    case noSecretKey
    case recipientKeyMissing
    case signerKeyMissing
    case fileAccessError(path: String)
    case unknownError(message: String)

    var errorDescription: String? {
        switch self {
        case .keyNotFound(let keyID):
            return "Key not found: \(keyID)"
        case .invalidPassphrase:
            return "Invalid passphrase"
        case .passphraseRequired:
            return "Passphrase is required for this operation"
        case .encryptionFailed(let error):
            return "Encryption failed\(error.map { ": \($0.localizedDescription)" } ?? "")"
        case .decryptionFailed(let error):
            return "Decryption failed\(error.map { ": \($0.localizedDescription)" } ?? "")"
        case .signingFailed(let error):
            return "Signing failed\(error.map { ": \($0.localizedDescription)" } ?? "")"
        case .verificationFailed(let error):
            return "Verification failed\(error.map { ": \($0.localizedDescription)" } ?? "")"
        case .keyGenerationFailed(let error):
            return "Key generation failed\(error.map { ": \($0.localizedDescription)" } ?? "")"
        case .keyImportFailed(let error):
            return "Key import failed\(error.map { ": \($0.localizedDescription)" } ?? "")"
        case .keyExportFailed(let error):
            return "Key export failed\(error.map { ": \($0.localizedDescription)" } ?? "")"
        case .keychainError(let error):
            return "Keychain error\(error.map { ": \($0.localizedDescription)" } ?? "")"
        case .persistenceError(let error):
            return "Storage error\(error.map { ": \($0.localizedDescription)" } ?? "")"
        case .invalidKeyData:
            return "Invalid key data"
        case .keyExpired:
            return "Key has expired"
        case .noPublicKey:
            return "No public key available"
        case .noSecretKey:
            return "No secret key available"
        case .recipientKeyMissing:
            return "Recipient's public key is required"
        case .signerKeyMissing:
            return "Signer's secret key is required"
        case .fileAccessError(let path):
            return "Cannot access file: \(path)"
        case .unknownError(let message):
            return message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .keyNotFound:
            return "Import the required key or generate a new one."
        case .invalidPassphrase:
            return "Please enter the correct passphrase for this key."
        case .passphraseRequired:
            return "Enter the passphrase to unlock the key."
        case .encryptionFailed:
            return "Check that the recipient's public key is valid."
        case .decryptionFailed:
            return "Verify that you have the correct private key and passphrase."
        case .signingFailed:
            return "Ensure you have the private key and correct passphrase."
        case .verificationFailed:
            return "The signature may be invalid or the public key may not match."
        case .keyGenerationFailed:
            return "Try again with different parameters."
        case .keyImportFailed:
            return "Check that the key file is a valid PGP key."
        case .keyExportFailed:
            return "Check file permissions and try again."
        case .keychainError:
            return "Check Keychain access permissions for this app."
        case .persistenceError:
            return "Check file permissions and available disk space."
        case .invalidKeyData:
            return "The key data appears to be corrupted or in an unsupported format."
        case .keyExpired:
            return "Generate a new key or extend the expiration date."
        case .noPublicKey, .noSecretKey:
            return "Import or generate the required key type."
        case .recipientKeyMissing:
            return "Import the recipient's public key before encrypting."
        case .signerKeyMissing:
            return "Import or generate a key pair for signing."
        case .fileAccessError:
            return "Check that the file exists and you have permission to access it."
        case .unknownError:
            return "Please try again or contact support."
        }
    }
}
