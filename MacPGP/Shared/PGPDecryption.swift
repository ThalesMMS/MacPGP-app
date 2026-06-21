import Foundation
import RNPKit

nonisolated enum PGPDecryption {
    nonisolated struct Result {
        let decryptedData: Data
        let key: Key
    }

    nonisolated static func decrypt(
        data: Data,
        using key: Key,
        passphrase: String
    ) throws -> Data {
        guard key.isSecret else {
            throw OperationError.noSecretKey
        }

        do {
            return try RNP.decrypt(
                data,
                andVerifySignature: false,
                using: [key],
                passphraseForKey: { _ in passphrase }
            )
        } catch RNPError.invalidPassphrase {
            throw OperationError.invalidPassphrase
        } catch {
            throw OperationError.decryptionFailed(underlying: error)
        }
    }

    nonisolated static func decrypt(
        data: Data,
        usingAnySecretKeyIn keys: [Key],
        passphrase: String
    ) throws -> Result {
        let secretKeys = keys.filter { $0.isSecret }
        guard !secretKeys.isEmpty else {
            throw OperationError.noSecretKey
        }

        var sawInvalidPassphrase = false
        var lastError: Error?

        for key in secretKeys {
            do {
                let decryptedData = try decrypt(data: data, using: key, passphrase: passphrase)
                return Result(decryptedData: decryptedData, key: key)
            } catch OperationError.invalidPassphrase {
                sawInvalidPassphrase = true
                lastError = OperationError.invalidPassphrase
            } catch {
                lastError = error
            }
        }

        if sawInvalidPassphrase {
            throw OperationError.invalidPassphrase
        }

        throw OperationError.decryptionFailed(underlying: lastError)
    }
}
