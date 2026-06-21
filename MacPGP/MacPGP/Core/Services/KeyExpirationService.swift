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
@MainActor
final class KeyExpirationService {
    static let shared = KeyExpirationService()

    private var activeOperationCount = 0
    private(set) var lastError: OperationError?

    var isProcessing: Bool {
        activeOperationCount > 0
    }

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

    /// Extends the expiration date of a PGP key.
    /// - Parameters:
    ///   - key: The key model to extend.
    ///   - newExpirationDate: The new expiration date (must be in the future).
    ///   - passphrase: The passphrase to unlock the secret key.
    /// - Returns: The updated key with the new expiration date.
    /// - Throws: `OperationError` if the key is not a secret key, the date is not in the future, the passphrase is empty, or the operation fails.
    @available(*, deprecated, message: "Use extendExpirationAsync(for:newExpirationDate:passphrase:) to keep cryptographic work off the main actor.")
    func extendExpiration(
        for key: PGPKeyModel,
        newExpirationDate: Date,
        passphrase: String
    ) throws -> PGPKeyModel {
        beginOperation()
        lastError = nil
        defer { endOperation() }

        do {
            return try Self.extendedKey(key, newExpirationDate: newExpirationDate, passphrase: passphrase)
        } catch let error as CancellationError {
            throw error
        } catch {
            let wrapped = OperationError.from(error)
            lastError = wrapped
            throw wrapped
        }
    }

    /// Asynchronously extends the expiration date of a PGP key.
    /// - Parameters:
    ///   - key: The PGP key to extend.
    ///   - newExpirationDate: The new expiration date (must be in the future).
    ///   - passphrase: The passphrase for the key.
    /// - Returns: The updated key with the extended expiration date.
    /// - Throws: `OperationError` if the key is invalid, the expiration date is invalid, or the passphrase is incorrect.
    func extendExpirationAsync(
        for key: PGPKeyModel,
        newExpirationDate: Date,
        passphrase: String
    ) async throws -> PGPKeyModel {
        beginOperation()
        lastError = nil
        defer { endOperation() }

        do {
            return try await Task.detached(priority: .userInitiated) {
                try Self.extendedKey(key, newExpirationDate: newExpirationDate, passphrase: passphrase)
            }.value
        } catch let error as CancellationError {
            throw error
        } catch {
            let wrapped = OperationError.from(error)
            lastError = wrapped
            throw wrapped
        }
    }

    private func beginOperation() {
        activeOperationCount += 1
    }

    private func endOperation() {
        activeOperationCount = max(0, activeOperationCount - 1)
    }

    /// Extends the expiration date of a secret key.
    ///
    /// Creates and returns a new `PGPKeyModel` with the updated expiration while preserving the original key's verification metadata.
    ///
    /// - Parameters:
    ///   - key: The key whose expiration to extend; must be a secret key.
    ///   - newExpirationDate: The new expiration date; must be in the future.
    ///   - passphrase: The passphrase to unlock the key; must not be empty.
    /// - Returns: A new `PGPKeyModel` with the updated expiration.
    /// - Throws: `OperationError.noSecretKey` if the key is not a secret key; `OperationError.passphraseRequired` if the passphrase is empty; `OperationError.unknownError` if the expiration date is not in the future or if the underlying key update fails.
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
