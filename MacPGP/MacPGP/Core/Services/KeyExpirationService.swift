import Foundation
import RNPKit

nonisolated struct ValidationIssue: Hashable {
    enum Severity: Hashable {
        case warning
        case error
    }

    let message: String
    let severity: Severity
}

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

        do {
            let updatedKey = try Self.extendedKey(
                key,
                newExpirationDate: newExpirationDate,
                passphrase: passphrase
            )
            isProcessing = false
            return updatedKey
        } catch {
            let wrapped = Self.operationError(from: error)
            lastError = wrapped
            isProcessing = false
            throw wrapped
        }
    }

    /// Asynchronously extends the expiration date of a key
    /// - Parameters:
    ///   - key: The key model to extend
    ///   - newExpirationDate: The new expiration date (must be in the future)
    ///   - passphrase: The passphrase to unlock the secret key
    /// - Returns: Updated PGPKeyModel with new expiration date
    /// - Throws: OperationError if the operation fails
    func extendExpirationAsync(
        for key: PGPKeyModel,
        newExpirationDate: Date,
        passphrase: String
    ) async throws -> PGPKeyModel {
        isProcessing = true
        lastError = nil

        do {
            let updatedKey = try await Task.detached(priority: .userInitiated) {
                try Self.extendedKey(
                    key,
                    newExpirationDate: newExpirationDate,
                    passphrase: passphrase
                )
            }.value
            isProcessing = false
            return updatedKey
        } catch {
            let wrapped = Self.operationError(from: error)
            lastError = wrapped
            isProcessing = false
            throw wrapped
        }
    }

    private nonisolated static func extendedKey(
        _ key: PGPKeyModel,
        newExpirationDate: Date,
        passphrase: String
    ) throws -> PGPKeyModel {
        guard key.isSecretKey else {
            throw OperationError.noSecretKey
        }

        guard newExpirationDate > Date() else {
            throw OperationError.unknownError(message: "New expiration date must be in the future")
        }

        guard !passphrase.isEmpty else {
            throw OperationError.passphraseRequired
        }

        let updatedKey = try key.rawKey.setExpiration(
            newExpirationDate,
            passphraseForKey: { _ in passphrase }
        )

        return PGPKeyModel(
            from: updatedKey,
            isVerified: key.isVerified,
            verificationDate: key.verificationDate,
            verificationMethod: key.verificationMethod,
            trustLevel: key.trustLevel
        )
    }

    private nonisolated static func operationError(from error: Error) -> OperationError {
        if let operationError = error as? OperationError {
            return operationError
        }
        if case RNPError.invalidPassphrase = error {
            return .invalidPassphrase
        }
        return OperationError.unknownError(message: error.localizedDescription)
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
    func validateExpirationDate(_ date: Date, forKey key: PGPKeyModel) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if date <= Date() {
            issues.append(ValidationIssue(message: "Expiration date must be in the future", severity: .error))
        }

        if date <= key.creationDate {
            issues.append(ValidationIssue(message: "Expiration date cannot be before key creation date", severity: .error))
        }

        // Warn if expiration is too far in the future (more than 5 years)
        let fiveYearsFromNow = Calendar.current.date(byAdding: .year, value: 5, to: Date()) ?? Date()
        if date > fiveYearsFromNow {
            issues.append(ValidationIssue(message: "Setting expiration more than 5 years in the future is not recommended", severity: .warning))
        }

        return issues
    }
}
