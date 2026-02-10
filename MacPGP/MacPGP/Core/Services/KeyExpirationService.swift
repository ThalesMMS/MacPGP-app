import Foundation
import ObjectivePGP

@Observable
final class KeyExpirationService {
    static let shared = KeyExpirationService()

    private(set) var isProcessing = false
    private(set) var lastError: OperationError?

    private init() {}

    /// Returns keys that are expiring within the specified number of days
    /// - Parameters:
    ///   - days: Number of days from now to check for expiration
    ///   - from: Array of keys to filter
    /// - Returns: Array of PGPKeyModel instances that expire within the threshold
    func getExpiringKeys(within days: Int, from keys: [PGPKeyModel]) -> [PGPKeyModel] {
        return keys.filter { key in
            guard let daysUntil = key.daysUntilExpiration else {
                return false
            }

            return daysUntil > 0 && daysUntil <= days
        }
    }

    /// Extends the expiration date of a key
    /// - Parameters:
    ///   - key: The key model to extend
    ///   - newExpirationDate: The new expiration date (must be in the future)
    ///   - passphrase: The passphrase to unlock the secret key
    /// - Returns: Updated PGPKeyModel with new expiration date
    /// - Throws: OperationError if the operation fails
    func extendExpiration(
        for key: PGPKeyModel,
        newExpirationDate: Date,
        passphrase: String
    ) throws -> PGPKeyModel {
        isProcessing = true
        lastError = nil

        defer {
            isProcessing = false
        }

        // Validate inputs
        guard key.isSecretKey else {
            lastError = .noSecretKey
            throw OperationError.noSecretKey
        }

        guard newExpirationDate > Date() else {
            let error = OperationError.unknownError(message: "New expiration date must be in the future")
            lastError = error
            throw error
        }

        guard !passphrase.isEmpty else {
            lastError = .passphraseRequired
            throw OperationError.passphraseRequired
        }

        do {
            // Note: ObjectivePGP does not currently support modifying key expiration dates
            // This is a placeholder implementation that will need to be enhanced
            // when ObjectivePGP adds this functionality or when we implement it manually
            // by manipulating the key packets directly

            // For now, we'll throw an error indicating the feature is not yet implemented
            let error = OperationError.unknownError(
                message: "Key expiration modification is not yet supported by the underlying crypto library"
            )
            lastError = error
            throw error

            // TODO: Implement key expiration extension when ObjectivePGP supports it
            // The implementation would look something like:
            // 1. Decrypt the secret key with the passphrase
            // 2. Modify the key's expiration time in the self-signature packet
            // 3. Re-sign the key with the new expiration date
            // 4. Update the key in the keyring
            // 5. Return the updated PGPKeyModel
        } catch let error as OperationError {
            lastError = error
            throw error
        } catch {
            let wrapped = OperationError.unknownError(message: error.localizedDescription)
            lastError = wrapped
            throw wrapped
        }
    }

    /// Asynchronously extends the expiration date of a key
    /// - Parameters:
    ///   - key: The key model to extend
    ///   - newExpirationDate: The new expiration date (must be in the future)
    ///   - passphrase: The passphrase to unlock the secret key
    ///   - completion: Completion handler with result
    func extendExpirationAsync(
        for key: PGPKeyModel,
        newExpirationDate: Date,
        passphrase: String,
        completion: @escaping (Result<PGPKeyModel, OperationError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let updatedKey = try self.extendExpiration(
                    for: key,
                    newExpirationDate: newExpirationDate,
                    passphrase: passphrase
                )

                DispatchQueue.main.async {
                    completion(.success(updatedKey))
                }
            } catch let error as OperationError {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.unknownError(message: error.localizedDescription)))
                }
            }
        }
    }

    /// Returns all expired keys
    /// - Parameter from: Array of keys to filter
    /// - Returns: Array of expired PGPKeyModel instances
    func getExpiredKeys(from keys: [PGPKeyModel]) -> [PGPKeyModel] {
        return keys.filter { $0.isExpired }
    }

    /// Checks if a key needs attention (expired or expiring soon)
    /// - Parameter key: The key to check
    /// - Returns: True if the key is expired or expiring within 30 days
    func needsAttention(_ key: PGPKeyModel) -> Bool {
        return key.isExpired || key.isExpiringSoon
    }

    /// Validates a new expiration date
    /// - Parameters:
    ///   - date: The proposed expiration date
    ///   - forKey: The key to validate against
    /// - Returns: Array of validation issues (empty if valid)
    func validateExpirationDate(_ date: Date, forKey key: PGPKeyModel) -> [String] {
        var issues: [String] = []

        if date <= Date() {
            issues.append("Expiration date must be in the future")
        }

        if date <= key.creationDate {
            issues.append("Expiration date cannot be before key creation date")
        }

        // Warn if expiration is too far in the future (more than 5 years)
        let fiveYearsFromNow = Calendar.current.date(byAdding: .year, value: 5, to: Date()) ?? Date()
        if date > fiveYearsFromNow {
            issues.append("Warning: Setting expiration more than 5 years in the future is not recommended")
        }

        return issues
    }
}
