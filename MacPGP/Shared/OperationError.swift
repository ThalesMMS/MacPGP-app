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
    case keyRevoked
    case noPublicKey
    case noSecretKey
    case recipientKeyMissing
    case signerKeyMissing
    case fileAccessError(path: String)
    case unknownError(message: String)

    var errorDescription: String? {
        switch self {
        case .keyNotFound(let keyID):
            return String(format: NSLocalizedString("error.key_not_found.description", comment: "Error description when a PGP key is not found in the keyring"), keyID)
        case .invalidPassphrase:
            return NSLocalizedString("error.invalid_passphrase.description", comment: "Error description when an incorrect passphrase is entered")
        case .passphraseRequired:
            return NSLocalizedString("error.passphrase_required.description", comment: "Error description when a passphrase is required to unlock a private key")
        case .encryptionFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.encryption_failed.description_with_details", comment: "Error description when encryption fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.encryption_failed.description", comment: "Error description when encryption fails without specific details")
            }
        case .decryptionFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.decryption_failed.description_with_details", comment: "Error description when decryption fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.decryption_failed.description", comment: "Error description when decryption fails without specific details")
            }
        case .signingFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.signing_failed.description_with_details", comment: "Error description when signing fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.signing_failed.description", comment: "Error description when signing fails without specific details")
            }
        case .verificationFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.verification_failed.description_with_details", comment: "Error description when signature verification fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.verification_failed.description", comment: "Error description when signature verification fails without specific details")
            }
        case .keyGenerationFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.key_generation_failed.description_with_details", comment: "Error description when key generation fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.key_generation_failed.description", comment: "Error description when key generation fails without specific details")
            }
        case .keyImportFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.key_import_failed.description_with_details", comment: "Error description when key import fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.key_import_failed.description", comment: "Error description when key import fails without specific details")
            }
        case .keyExportFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.key_export_failed.description_with_details", comment: "Error description when key export fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.key_export_failed.description", comment: "Error description when key export fails without specific details")
            }
        case .keychainError(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.keychain_error.description_with_details", comment: "Error description when Keychain access fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.keychain_error.description", comment: "Error description when Keychain access fails without specific details")
            }
        case .persistenceError(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.persistence_error.description_with_details", comment: "Error description when data persistence fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.persistence_error.description", comment: "Error description when data persistence fails without specific details")
            }
        case .invalidKeyData:
            return NSLocalizedString("error.invalid_key_data.description", comment: "Error description when key data is invalid or corrupted")
        case .keyExpired:
            return NSLocalizedString("error.key_expired.description", comment: "Error description when a PGP key has expired")
        case .keyRevoked:
            return NSLocalizedString("error.key_revoked.description", comment: "Error description when a PGP key has been revoked")
        case .noPublicKey:
            return NSLocalizedString("error.no_public_key.description", comment: "Error description when no public key is available")
        case .noSecretKey:
            return NSLocalizedString("error.no_secret_key.description", comment: "Error description when no private key is available")
        case .recipientKeyMissing:
            return NSLocalizedString("error.recipient_key_missing.description", comment: "Error description when recipient's public key is missing")
        case .signerKeyMissing:
            return NSLocalizedString("error.signer_key_missing.description", comment: "Error description when signer's private key is missing")
        case .fileAccessError(let path):
            return String(format: NSLocalizedString("error.file_access_error.description", comment: "Error description when unable to access a file at a specific path"), path)
        case .unknownError(let message):
            return String(format: NSLocalizedString("error.unknown_error.description", comment: "Error description for unexpected errors"), message)
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .keyNotFound:
            return NSLocalizedString("error.key_not_found.recovery", comment: "Recovery suggestion when a PGP key is not found")
        case .invalidPassphrase:
            return NSLocalizedString("error.invalid_passphrase.recovery", comment: "Recovery suggestion when an incorrect passphrase is entered")
        case .passphraseRequired:
            return NSLocalizedString("error.passphrase_required.recovery", comment: "Recovery suggestion when a passphrase is required")
        case .encryptionFailed:
            return NSLocalizedString("error.encryption_failed.recovery", comment: "Recovery suggestion when encryption fails")
        case .decryptionFailed:
            return NSLocalizedString("error.decryption_failed.recovery", comment: "Recovery suggestion when decryption fails")
        case .signingFailed:
            return NSLocalizedString("error.signing_failed.recovery", comment: "Recovery suggestion when signing fails")
        case .verificationFailed:
            return NSLocalizedString("error.verification_failed.recovery", comment: "Recovery suggestion when signature verification fails")
        case .keyGenerationFailed:
            return NSLocalizedString("error.key_generation_failed.recovery", comment: "Recovery suggestion when key generation fails")
        case .keyImportFailed:
            return NSLocalizedString("error.key_import_failed.recovery", comment: "Recovery suggestion when key import fails")
        case .keyExportFailed:
            return NSLocalizedString("error.key_export_failed.recovery", comment: "Recovery suggestion when key export fails")
        case .keychainError:
            return NSLocalizedString("error.keychain_error.recovery", comment: "Recovery suggestion when Keychain access fails")
        case .persistenceError:
            return NSLocalizedString("error.persistence_error.recovery", comment: "Recovery suggestion when data persistence fails")
        case .invalidKeyData:
            return NSLocalizedString("error.invalid_key_data.recovery", comment: "Recovery suggestion when key data is invalid")
        case .keyExpired:
            return NSLocalizedString("error.key_expired.recovery", comment: "Recovery suggestion when a key has expired")
        case .keyRevoked:
            return NSLocalizedString("error.key_revoked.recovery", comment: "Recovery suggestion when a key has been revoked")
        case .noPublicKey:
            return NSLocalizedString("error.no_public_key.recovery", comment: "Recovery suggestion when no public key is available")
        case .noSecretKey:
            return NSLocalizedString("error.no_secret_key.recovery", comment: "Recovery suggestion when no private key is available")
        case .recipientKeyMissing:
            return NSLocalizedString("error.recipient_key_missing.recovery", comment: "Recovery suggestion when recipient's key is missing")
        case .signerKeyMissing:
            return NSLocalizedString("error.signer_key_missing.recovery", comment: "Recovery suggestion when signer's key is missing")
        case .fileAccessError:
            return NSLocalizedString("error.file_access_error.recovery", comment: "Recovery suggestion when file access fails")
        case .unknownError:
            return NSLocalizedString("error.unknown_error.recovery", comment: "Recovery suggestion for unexpected errors")
        }
    }

    var failureReason: String? {
        switch self {
        case .keyNotFound(let keyID):
            return String(format: NSLocalizedString("error.key_not_found.reason", comment: "Failure reason when a PGP key is not found"), keyID)
        case .invalidPassphrase:
            return NSLocalizedString("error.invalid_passphrase.reason", comment: "Failure reason when an incorrect passphrase is entered")
        case .passphraseRequired:
            return NSLocalizedString("error.passphrase_required.reason", comment: "Failure reason when a passphrase is required")
        case .encryptionFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.encryption_failed.reason_with_details", comment: "Failure reason when encryption fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.encryption_failed.reason", comment: "Failure reason when encryption fails without specific details")
            }
        case .decryptionFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.decryption_failed.reason_with_details", comment: "Failure reason when decryption fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.decryption_failed.reason", comment: "Failure reason when decryption fails without specific details")
            }
        case .signingFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.signing_failed.reason_with_details", comment: "Failure reason when signing fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.signing_failed.reason", comment: "Failure reason when signing fails without specific details")
            }
        case .verificationFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.verification_failed.reason_with_details", comment: "Failure reason when signature verification fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.verification_failed.reason", comment: "Failure reason when signature verification fails without specific details")
            }
        case .keyGenerationFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.key_generation_failed.reason_with_details", comment: "Failure reason when key generation fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.key_generation_failed.reason", comment: "Failure reason when key generation fails without specific details")
            }
        case .keyImportFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.key_import_failed.reason_with_details", comment: "Failure reason when key import fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.key_import_failed.reason", comment: "Failure reason when key import fails without specific details")
            }
        case .keyExportFailed(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.key_export_failed.reason_with_details", comment: "Failure reason when key export fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.key_export_failed.reason", comment: "Failure reason when key export fails without specific details")
            }
        case .keychainError(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.keychain_error.reason_with_details", comment: "Failure reason when Keychain access fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.keychain_error.reason", comment: "Failure reason when Keychain access fails without specific details")
            }
        case .persistenceError(let error):
            if let error = error {
                return String(format: NSLocalizedString("error.persistence_error.reason_with_details", comment: "Failure reason when data persistence fails with underlying error details"), error.localizedDescription)
            } else {
                return NSLocalizedString("error.persistence_error.reason", comment: "Failure reason when data persistence fails without specific details")
            }
        case .invalidKeyData:
            return NSLocalizedString("error.invalid_key_data.reason", comment: "Failure reason when key data is invalid")
        case .keyExpired:
            return NSLocalizedString("error.key_expired.reason", comment: "Failure reason when a key has expired")
        case .keyRevoked:
            return NSLocalizedString("error.key_revoked.reason", comment: "Failure reason when a key has been revoked")
        case .noPublicKey:
            return NSLocalizedString("error.no_public_key.reason", comment: "Failure reason when no public key is available")
        case .noSecretKey:
            return NSLocalizedString("error.no_secret_key.reason", comment: "Failure reason when no private key is available")
        case .recipientKeyMissing:
            return NSLocalizedString("error.recipient_key_missing.reason", comment: "Failure reason when recipient's key is missing")
        case .signerKeyMissing:
            return NSLocalizedString("error.signer_key_missing.reason", comment: "Failure reason when signer's key is missing")
        case .fileAccessError(let path):
            return String(format: NSLocalizedString("error.file_access_error.reason", comment: "Failure reason when file access fails"), path)
        case .unknownError(let message):
            return String(format: NSLocalizedString("error.unknown_error.reason", comment: "Failure reason for unexpected errors"), message)
        }
    }
}
