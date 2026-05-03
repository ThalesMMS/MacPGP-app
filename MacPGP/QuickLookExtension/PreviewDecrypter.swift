import Foundation
import RNPKit

struct PreviewDecrypter {

    enum DecryptError: Error, Equatable {
        case noSecretKeys
        case invalidPassphrase
        case unableToDecrypt(RNPError?)
    }

    struct Result: Equatable {
        let decryptedData: Data
    }

    nonisolated static func decrypt(
        encryptedData: Data,
        keys: [Key],
        passphrase: String
    ) throws -> Result {
        let secretKeys = keys.filter { $0.isSecret }
        guard !secretKeys.isEmpty else {
            throw DecryptError.noSecretKeys
        }

        var lastError: Error?
        var sawInvalidPassphrase = false
        for key in secretKeys {
            do {
                let decrypted = try RNP.decrypt(
                    encryptedData,
                    andVerifySignature: false,
                    using: [key],
                    passphraseForKey: { _ in passphrase }
                )
                return Result(decryptedData: decrypted)
            } catch {
                if let rnpError = error as? RNPError, rnpError == .invalidPassphrase {
                    sawInvalidPassphrase = true
                }
                lastError = error
                continue
            }
        }

        if sawInvalidPassphrase {
            throw DecryptError.invalidPassphrase
        }

        if let rnpError = lastError as? RNPError {
            throw DecryptError.unableToDecrypt(rnpError)
        }

        throw DecryptError.unableToDecrypt(nil)
    }
}
