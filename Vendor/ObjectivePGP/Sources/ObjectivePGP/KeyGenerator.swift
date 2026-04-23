import Foundation

public final class KeyGenerator {
    public enum Algorithm {
        case RSA
        case ECDSA
        case edDSA
    }

    public var keyBitsLength: Int32 = 4096
    public var keyAlgorithm: Algorithm = .RSA

    public init() {}

    public func generate(for userID: String, passphrase: String) -> Key {
        do {
            return try RNP.generateKey(
                algorithm: keyAlgorithm,
                keyBitsLength: keyBitsLength,
                userID: userID,
                passphrase: passphrase
            )
        } catch {
            preconditionFailure("Failed to generate key: \(error.localizedDescription)")
        }
    }
}
