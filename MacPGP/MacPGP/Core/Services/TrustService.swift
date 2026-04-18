import Foundation

/// Service for per-key trust validation and warnings.
@Observable
final class TrustService {
    private let keyringService: KeyringService

    init(keyringService: KeyringService) {
        self.keyringService = keyringService
    }

    // MARK: - Helper Methods

    /// Get all keys that can certify others (fully or ultimately trusted)
    func getCertifyingKeys() -> [PGPKeyModel] {
        keyringService.keys.filter { $0.trustLevel.canCertify }
    }

    /// Check if a key can be used to encrypt to a recipient
    func isKeyValidForEncryption(_ key: PGPKeyModel) -> Bool {
        // A key is valid for encryption if:
        // 1. It's not expired or revoked
        // 2. It's not marked as "never trust"

        if key.isExpired || key.isRevoked {
            return false
        }

        if key.trustLevel == .never {
            return false
        }

        // For now, allow encryption to any key that's not marked as "never"
        // This can be made stricter based on user preferences
        return true
    }

    /// Get a warning message for encrypting to a key with questionable trust
    func getTrustWarning(for key: PGPKeyModel) -> String? {
        if key.trustLevel == .never {
            return "This key is marked as 'Never Trust'. Encryption is not recommended."
        }

        if key.isExpired {
            return "This key has expired."
        }

        if key.isRevoked {
            return "This key has been revoked."
        }

        if key.trustLevel == .unknown {
            return "This key has unknown trust level."
        }

        return nil
    }
}
