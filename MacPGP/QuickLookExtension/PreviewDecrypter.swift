import Foundation
import RNPKit

struct PreviewDecrypter {

    struct Result: Equatable {
        let decryptedData: Data
    }

    nonisolated static func decrypt(
        encryptedData: Data,
        keys: [Key],
        passphrase: String
    ) throws -> Result {
        let result = try PGPDecryption.decrypt(
            data: encryptedData,
            usingAnySecretKeyIn: keys,
            passphrase: passphrase
        )
        return Result(decryptedData: result.decryptedData)
    }
}
