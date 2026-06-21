import Foundation

/// Typed failure for key generation.
///
/// Generation can fail for invalid parameters (unsupported curve/size), backend
/// initialization, or librnp generation/protection/export errors. Rather than
/// trapping the process, the wrapper surfaces a thrown error whose `underlying`
/// value preserves the backend's typed/contextual failure so the app layer can
/// map it to a recoverable `OperationError`.
public enum KeyGenerationError: Error {
    case backendFailure(underlying: Error)
}

public final class KeyGenerator {
    public enum Algorithm: Sendable {
        case RSA
        case ECDSA
        case edDSA
    }

    /// Backend entry point for generation. Defaults to librnp; tests inject a
    /// closure (e.g. one that throws) to exercise failure handling without
    /// invoking librnp.
    public typealias Backend = @Sendable (Algorithm, Int32, String, String) throws -> Key

    public var keyBitsLength: Int32 = 4096
    public var keyAlgorithm: Algorithm = .RSA

    private let backend: Backend?

    public init() {
        self.backend = nil
    }

    /// Test/seam initializer: inject a backend to validate the throwing contract
    /// deterministically.
    public init(backend: @escaping Backend) {
        self.backend = backend
    }

    /// Generates a key pair, throwing ``KeyGenerationError`` on failure.
    ///
    /// Previously this trapped with `preconditionFailure`, which could not be
    /// caught and terminated the whole app on any recoverable backend failure.
    public func generate(for userID: String, passphrase: String) throws -> Key {
        do {
            if let backend {
                return try backend(keyAlgorithm, keyBitsLength, userID, passphrase)
            }
            return try RNPBackend.generateKey(
                algorithm: keyAlgorithm,
                keyBitsLength: keyBitsLength,
                userID: userID,
                passphrase: passphrase
            )
        } catch let error as KeyGenerationError {
            throw error
        } catch {
            throw KeyGenerationError.backendFailure(underlying: error)
        }
    }
}
