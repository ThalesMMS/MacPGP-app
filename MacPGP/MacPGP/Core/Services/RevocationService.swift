import Foundation
import RNPKit

enum RevocationReason: Int, CaseIterable, Sendable {
    case noReason = 0
    case compromised = 1
    case superseded = 2
    case noLongerUsed = 3

    var description: String {
        switch self {
        case .noReason:
            return "No reason specified"
        case .compromised:
            return "Key has been compromised"
        case .superseded:
            return "Key is superseded by a new key"
        case .noLongerUsed:
            return "Key is no longer used"
        }
    }

    var displayName: String {
        switch self {
        case .noReason:
            return "No Reason"
        case .compromised:
            return "Compromised"
        case .superseded:
            return "Superseded"
        case .noLongerUsed:
            return "No Longer Used"
        }
    }

    var rnpCode: String {
        switch self {
        case .noReason:
            return "no"
        case .compromised:
            return "compromised"
        case .superseded:
            return "superseded"
        case .noLongerUsed:
            return "retired"
        }
    }
}

@MainActor
@Observable
final class RevocationService {
    static let shared = RevocationService()

    private(set) var isProcessing = false
    private(set) var lastError: OperationError?

    private init() {}

    /// Generates a revocation certificate for a key
    /// - Parameters:
    ///   - key: The key model to generate revocation certificate for
    ///   - reason: The reason for revocation
    ///   - passphrase: The passphrase to unlock the secret key
    /// - Returns: Data containing the armored revocation certificate
    /// - Throws: OperationError if the operation fails
    func generateRevocationCertificate(
        for key: PGPKeyModel,
        reason: RevocationReason,
        passphrase: String
    ) throws -> Data {
        isProcessing = true
        lastError = nil

        defer {
            isProcessing = false
        }

        do {
            return try Self.generateRevocationCertificateData(
                for: key,
                reason: reason,
                passphrase: passphrase
            )
        } catch {
            let wrapped = Self.operationError(from: error)
            lastError = wrapped
            throw wrapped
        }
    }

    /// Asynchronously generates a revocation certificate for a key
    /// - Parameters:
    ///   - key: The key model to generate revocation certificate for
    ///   - reason: The reason for revocation
    ///   - passphrase: The passphrase to unlock the secret key
    /// - Returns: Data containing the armored revocation certificate
    /// - Throws: OperationError if the operation fails
    func generateRevocationCertificateAsync(
        for key: PGPKeyModel,
        reason: RevocationReason,
        passphrase: String
    ) async throws -> Data {
        isProcessing = true
        lastError = nil

        defer {
            isProcessing = false
        }

        do {
            return try await Task.detached(priority: .userInitiated) {
                try Self.generateRevocationCertificateData(
                    for: key,
                    reason: reason,
                    passphrase: passphrase
                )
            }.value
        } catch {
            let wrapped = Self.operationError(from: error)
            lastError = wrapped
            throw wrapped
        }
    }

    /// Imports a revocation certificate from data and verifies it targets a local key.
    /// - Parameters:
    ///   - data: The revocation certificate data (armored or binary)
    ///   - keyringService: The keyring used to verify the certificate issuer is local
    ///   - expectedKey: Optional key the caller intends to revoke
    /// - Returns: The local key fingerprint that the revocation applies to
    /// - Throws: OperationError if the operation fails
    func importRevocationCertificate(
        data: Data,
        keyringService: KeyringService,
        expectedKey: PGPKeyModel? = nil
    ) throws -> String {
        isProcessing = true
        lastError = nil

        defer {
            isProcessing = false
        }

        guard let identifier = SigningService.extractIssuerKeyID(from: data), !identifier.isEmpty else {
            let error = OperationError.keyImportFailed(underlying: nil)
            lastError = error
            throw error
        }

        guard let matchingKey = localKey(matching: identifier, in: keyringService) else {
            let error = OperationError.keyNotFound(keyID: identifier)
            lastError = error
            throw error
        }

        if let expectedKey,
           Self.normalizedHexIdentifier(matchingKey.fingerprint) != Self.normalizedHexIdentifier(expectedKey.fingerprint) {
            let error = OperationError.unknownError(message: "Certificate does not match this key")
            lastError = error
            throw error
        }

        return matchingKey.fingerprint
    }

    /// Applies a revocation certificate to a key
    /// - Parameters:
    ///   - key: The key model to revoke
    ///   - certificate: The revocation certificate data
    /// - Returns: Updated PGPKeyModel with revocation applied
    /// - Throws: OperationError if the operation fails
    func applyRevocation(to key: PGPKeyModel, certificate: Data) throws -> PGPKeyModel {
        isProcessing = true
        lastError = nil

        defer {
            isProcessing = false
        }

        do {
            return try Self.applyRevocationData(to: key, certificate: certificate)
        } catch {
            let wrapped = Self.operationError(from: error)
            lastError = wrapped
            throw wrapped
        }
    }

    /// Asynchronously applies a revocation certificate to a key
    /// - Parameters:
    ///   - key: The key model to revoke
    ///   - certificate: The revocation certificate data
    /// - Returns: Updated PGPKeyModel with revocation applied
    /// - Throws: OperationError if the operation fails
    func applyRevocationAsync(
        to key: PGPKeyModel,
        certificate: Data
    ) async throws -> PGPKeyModel {
        isProcessing = true
        lastError = nil

        defer {
            isProcessing = false
        }

        do {
            return try await Task.detached(priority: .userInitiated) {
                try Self.applyRevocationData(to: key, certificate: certificate)
            }.value
        } catch {
            let wrapped = Self.operationError(from: error)
            lastError = wrapped
            throw wrapped
        }
    }

    /// Checks if a key is revoked
    /// - Parameter key: The key to check
    /// - Returns: True if the key is revoked
    func isRevoked(_ key: PGPKeyModel) -> Bool {
        return key.isRevoked
    }

    /// Returns all revoked keys from a list
    /// - Parameter from: Array of keys to filter
    /// - Returns: Array of revoked PGPKeyModel instances
    func getRevokedKeys(from keys: [PGPKeyModel]) -> [PGPKeyModel] {
        return keys.filter { $0.isRevoked }
    }

    /// Validates that a key can be used for operations
    /// - Parameter key: The key to validate
    /// - Returns: Array of validation issues (empty if valid)
    func validateKeyUsability(_ key: PGPKeyModel) -> [String] {
        var issues: [String] = []

        if key.isRevoked {
            issues.append("Key has been revoked and cannot be used")
        }

        if key.isExpired {
            issues.append("Key has expired")
        }

        return issues
    }

    /// Exports a revocation certificate to a file URL
    /// - Parameters:
    ///   - certificate: The certificate data to export
    ///   - url: The file URL to write to
    /// - Throws: OperationError if the operation fails
    func exportRevocationCertificate(certificate: Data, to url: URL) throws {
        do {
            try SecureScopedFileAccess.writeData(certificate, to: url, options: [.atomic])
        } catch let error as OperationError {
            lastError = error
            throw error
        } catch {
            let wrapped = OperationError.fileAccessError(path: url.path)
            lastError = wrapped
            throw wrapped
        }
    }

    /// Imports a revocation certificate from a file URL
    /// - Parameter url: The file URL to read from
    /// - Returns: The certificate data
    /// - Throws: OperationError if the operation fails
    func importRevocationCertificateFromFile(from url: URL) throws -> Data {
        do {
            return try SecureScopedFileAccess.readData(from: url)
        } catch let error as OperationError {
            lastError = error
            throw error
        } catch {
            let wrapped = OperationError.fileAccessError(path: url.path)
            lastError = wrapped
            throw wrapped
        }
    }

    private func localKey(matching identifier: String, in keyringService: KeyringService) -> PGPKeyModel? {
        return keyringService.keys.first { key in
            Self.identifier(identifier, matchesFingerprint: key.fingerprint, shortKeyID: key.shortKeyID)
        }
    }

    nonisolated static func identifier(_ identifier: String, matchesFingerprint fingerprint: String, shortKeyID: String) -> Bool {
        let normalizedIdentifier = normalizedHexIdentifier(identifier)

        return normalizedHexIdentifier(fingerprint) == normalizedIdentifier ||
            normalizedHexIdentifier(shortKeyID) == normalizedIdentifier
    }

    private nonisolated static func normalizedHexIdentifier(_ identifier: String) -> String {
        identifier
            .uppercased()
            .filter { $0.isHexDigit }
    }

    private nonisolated static func generateRevocationCertificateData(
        for key: PGPKeyModel,
        reason: RevocationReason,
        passphrase: String
    ) throws -> Data {
        guard key.isSecretKey else {
            throw OperationError.noSecretKey
        }

        guard !passphrase.isEmpty else {
            throw OperationError.passphraseRequired
        }

        do {
            return try key.rawKey.exportRevocation(
                hash: "SHA256",
                reasonCode: reason.rnpCode,
                reason: reason.description,
                passphraseForKey: { _ in passphrase }
            )
        } catch {
            throw operationError(from: error)
        }
    }

    private nonisolated static func applyRevocationData(
        to key: PGPKeyModel,
        certificate: Data
    ) throws -> PGPKeyModel {
        do {
            let updatedKey = try key.rawKey.applyRevocation(certificate)
            guard updatedKey.isRevoked else {
                throw OperationError.unknownError(message: "Revocation certificate did not revoke the key")
            }

            return PGPKeyModel(
                from: updatedKey,
                isVerified: key.isVerified,
                verificationDate: key.verificationDate,
                verificationMethod: key.verificationMethod,
                trustLevel: key.trustLevel
            )
        } catch {
            throw operationError(from: error)
        }
    }

    private nonisolated static func operationError(from error: Error) -> OperationError {
        if let operationError = error as? OperationError {
            return operationError
        }

        do {
            throw error
        } catch RNPError.invalidPassphrase {
            return .invalidPassphrase
        } catch {
            return .unknownError(message: error.localizedDescription)
        }
    }
}
