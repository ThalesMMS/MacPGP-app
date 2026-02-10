import Foundation
import ObjectivePGP

enum RevocationReason: Int, CaseIterable {
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
}

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

        // Validate inputs
        guard key.isSecretKey else {
            lastError = .noSecretKey
            throw OperationError.noSecretKey
        }

        guard !passphrase.isEmpty else {
            lastError = .passphraseRequired
            throw OperationError.passphraseRequired
        }

        do {
            // Note: ObjectivePGP does not currently have a direct API for generating
            // revocation certificates. This is a placeholder implementation that will
            // need to be enhanced when ObjectivePGP adds this functionality or when
            // we implement it manually by creating the appropriate signature packets.

            // For now, we'll throw an error indicating the feature is not yet implemented
            let error = OperationError.unknownError(
                message: "Revocation certificate generation is not yet supported by the underlying crypto library"
            )
            lastError = error
            throw error

            // TODO: Implement revocation certificate generation when ObjectivePGP supports it
            // The implementation would look something like:
            // 1. Decrypt the secret key with the passphrase
            // 2. Create a revocation signature packet with the specified reason
            // 3. Export the revocation certificate in armored format
            // 4. Return the certificate data
        } catch let error as OperationError {
            lastError = error
            throw error
        } catch {
            let wrapped = OperationError.unknownError(message: error.localizedDescription)
            lastError = wrapped
            throw wrapped
        }
    }

    /// Asynchronously generates a revocation certificate for a key
    /// - Parameters:
    ///   - key: The key model to generate revocation certificate for
    ///   - reason: The reason for revocation
    ///   - passphrase: The passphrase to unlock the secret key
    ///   - completion: Completion handler with result containing certificate data
    func generateRevocationCertificateAsync(
        for key: PGPKeyModel,
        reason: RevocationReason,
        passphrase: String,
        completion: @escaping (Result<Data, OperationError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let certificate = try self.generateRevocationCertificate(
                    for: key,
                    reason: reason,
                    passphrase: passphrase
                )

                DispatchQueue.main.async {
                    completion(.success(certificate))
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

    /// Imports a revocation certificate from data
    /// - Parameter data: The revocation certificate data (armored or binary)
    /// - Returns: The key fingerprint that the revocation applies to
    /// - Throws: OperationError if the operation fails
    func importRevocationCertificate(data: Data) throws -> String {
        isProcessing = true
        lastError = nil

        defer {
            isProcessing = false
        }

        do {
            // Note: ObjectivePGP does not currently have a direct API for importing
            // revocation certificates. This is a placeholder implementation.

            // For now, we'll throw an error indicating the feature is not yet implemented
            let error = OperationError.unknownError(
                message: "Revocation certificate import is not yet supported by the underlying crypto library"
            )
            lastError = error
            throw error

            // TODO: Implement revocation certificate import when ObjectivePGP supports it
            // The implementation would look something like:
            // 1. Parse the revocation certificate data
            // 2. Extract the key fingerprint and revocation signature
            // 3. Validate the signature
            // 4. Return the key fingerprint for matching with keyring
        } catch let error as OperationError {
            lastError = error
            throw error
        } catch {
            let wrapped = OperationError.keyImportFailed(underlying: error)
            lastError = wrapped
            throw wrapped
        }
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
            // Note: ObjectivePGP does not currently have a direct API for applying
            // revocation certificates. This is a placeholder implementation.

            // For now, we'll throw an error indicating the feature is not yet implemented
            let error = OperationError.unknownError(
                message: "Applying revocation certificate is not yet supported by the underlying crypto library"
            )
            lastError = error
            throw error

            // TODO: Implement revocation certificate application when ObjectivePGP supports it
            // The implementation would look something like:
            // 1. Parse the revocation certificate
            // 2. Verify the revocation signature matches the key
            // 3. Merge the revocation signature into the key
            // 4. Update the key in the keyring
            // 5. Return the updated PGPKeyModel with isRevoked = true
        } catch let error as OperationError {
            lastError = error
            throw error
        } catch {
            let wrapped = OperationError.unknownError(message: error.localizedDescription)
            lastError = wrapped
            throw wrapped
        }
    }

    /// Asynchronously applies a revocation certificate to a key
    /// - Parameters:
    ///   - key: The key model to revoke
    ///   - certificate: The revocation certificate data
    ///   - completion: Completion handler with result containing updated key model
    func applyRevocationAsync(
        to key: PGPKeyModel,
        certificate: Data,
        completion: @escaping (Result<PGPKeyModel, OperationError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let updatedKey = try self.applyRevocation(
                    to: key,
                    certificate: certificate
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
            try certificate.write(to: url, options: [.atomic])
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
            return try Data(contentsOf: url)
        } catch {
            let wrapped = OperationError.fileAccessError(path: url.path)
            lastError = wrapped
            throw wrapped
        }
    }
}
