import Foundation
import ObjectivePGP

final class EncryptionService {
    private let keyringService: KeyringService

    init(keyringService: KeyringService) {
        self.keyringService = keyringService
    }

    func encrypt(
        data: Data,
        for recipients: [PGPKeyModel],
        signedBy signer: PGPKeyModel? = nil,
        passphrase: String? = nil,
        armored: Bool = true
    ) throws -> Data {
        guard !recipients.isEmpty else {
            throw OperationError.recipientKeyMissing
        }

        let recipientKeys = recipients.compactMap { keyringService.rawKey(for: $0) }
        guard recipientKeys.count == recipients.count else {
            throw OperationError.keyNotFound(keyID: "recipient")
        }

        var signerKey: Key?
        if let signer = signer {
            guard let key = keyringService.rawKey(for: signer) else {
                throw OperationError.keyNotFound(keyID: signer.shortKeyID)
            }
            guard key.isSecret else {
                throw OperationError.noSecretKey
            }
            signerKey = key
        }

        do {
            var encryptedData: Data

            if let signerKey = signerKey, let passphrase = passphrase {
                var allKeys = recipientKeys
                allKeys.append(signerKey)
                encryptedData = try ObjectivePGP.encrypt(
                    data,
                    addSignature: true,
                    using: allKeys,
                    passphraseForKey: { _ in passphrase }
                )
            } else {
                encryptedData = try ObjectivePGP.encrypt(data, addSignature: false, using: recipientKeys)
            }

            if armored {
                let armoredString = Armor.armored(encryptedData, as: .message)
                encryptedData = armoredString.data(using: .utf8) ?? encryptedData
            }

            return encryptedData
        } catch {
            throw OperationError.encryptionFailed(underlying: error)
        }
    }

    func encrypt(
        message: String,
        for recipients: [PGPKeyModel],
        signedBy signer: PGPKeyModel? = nil,
        passphrase: String? = nil,
        armored: Bool = true
    ) throws -> String {
        guard let messageData = message.data(using: .utf8) else {
            throw OperationError.encryptionFailed(underlying: nil)
        }

        let encryptedData = try encrypt(
            data: messageData,
            for: recipients,
            signedBy: signer,
            passphrase: passphrase,
            armored: armored
        )

        if armored {
            return String(data: encryptedData, encoding: .utf8) ?? ""
        } else {
            return encryptedData.base64EncodedString()
        }
    }

    func encrypt(
        file: URL,
        for recipients: [PGPKeyModel],
        signedBy signer: PGPKeyModel? = nil,
        passphrase: String? = nil,
        outputURL: URL? = nil,
        armored: Bool = false,
        progressCallback: ((Double) -> Void)? = nil
    ) throws -> URL {
        progressCallback?(0.0)

        let fileData = try Data(contentsOf: file)
        progressCallback?(0.3)

        let encryptedData = try encrypt(
            data: fileData,
            for: recipients,
            signedBy: signer,
            passphrase: passphrase,
            armored: armored
        )
        progressCallback?(0.7)

        let outputPath = outputURL ?? file.appendingPathExtension(armored ? "asc" : "gpg")
        try encryptedData.write(to: outputPath)

        progressCallback?(1.0)
        return outputPath
    }

    func decrypt(
        data: Data,
        using key: PGPKeyModel,
        passphrase: String
    ) throws -> Data {
        guard let rawKey = keyringService.rawKey(for: key) else {
            throw OperationError.keyNotFound(keyID: key.shortKeyID)
        }

        guard rawKey.isSecret else {
            throw OperationError.noSecretKey
        }

        do {
            let decryptedData = try ObjectivePGP.decrypt(
                data,
                andVerifySignature: false,
                using: [rawKey],
                passphraseForKey: { _ in passphrase }
            )
            return decryptedData
        } catch {
            let nsError = error as NSError
            if nsError.domain == "ObjectivePGP" && nsError.code == 2 {
                throw OperationError.invalidPassphrase
            }
            throw OperationError.decryptionFailed(underlying: error)
        }
    }

    func decrypt(
        message: String,
        using key: PGPKeyModel,
        passphrase: String
    ) throws -> String {
        guard let messageData = message.data(using: .utf8) else {
            throw OperationError.decryptionFailed(underlying: nil)
        }

        let decryptedData = try decrypt(data: messageData, using: key, passphrase: passphrase)

        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw OperationError.decryptionFailed(underlying: nil)
        }

        return decryptedString
    }

    func decrypt(
        file: URL,
        using key: PGPKeyModel,
        passphrase: String,
        outputURL: URL? = nil,
        progressCallback: ((Double) -> Void)? = nil
    ) throws -> URL {
        progressCallback?(0.0)

        let fileData = try Data(contentsOf: file)
        progressCallback?(0.3)

        let decryptedData = try decrypt(data: fileData, using: key, passphrase: passphrase)
        progressCallback?(0.7)

        var outputPath: URL
        if let output = outputURL {
            outputPath = output
        } else {
            let path = file.deletingPathExtension()
            if file.pathExtension == "asc" || file.pathExtension == "gpg" {
                outputPath = path
            } else {
                outputPath = file.appendingPathExtension("decrypted")
            }
        }

        try decryptedData.write(to: outputPath)
        progressCallback?(1.0)
        return outputPath
    }

    func encryptAsync(
        file: URL,
        for recipients: [PGPKeyModel],
        signedBy signer: PGPKeyModel? = nil,
        passphrase: String? = nil,
        outputURL: URL? = nil,
        armored: Bool = false,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await Task.detached {
            await MainActor.run { progressCallback?(0.0) }

            let fileData = try Data(contentsOf: file)
            await MainActor.run { progressCallback?(0.3) }

            let encryptedData = try self.encrypt(
                data: fileData,
                for: recipients,
                signedBy: signer,
                passphrase: passphrase,
                armored: armored
            )
            await MainActor.run { progressCallback?(0.7) }

            let outputPath = outputURL ?? file.appendingPathExtension(armored ? "asc" : "gpg")
            try encryptedData.write(to: outputPath)

            await MainActor.run { progressCallback?(1.0) }
            return outputPath
        }.value
    }

    func decryptAsync(
        file: URL,
        using key: PGPKeyModel,
        passphrase: String,
        outputURL: URL? = nil,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await Task.detached {
            await MainActor.run { progressCallback?(0.0) }

            let fileData = try Data(contentsOf: file)
            await MainActor.run { progressCallback?(0.3) }

            let decryptedData = try self.decrypt(data: fileData, using: key, passphrase: passphrase)
            await MainActor.run { progressCallback?(0.7) }

            var outputPath: URL
            if let output = outputURL {
                outputPath = output
            } else {
                let path = file.deletingPathExtension()
                if file.pathExtension == "asc" || file.pathExtension == "gpg" {
                    outputPath = path
                } else {
                    outputPath = file.appendingPathExtension("decrypted")
                }
            }

            try decryptedData.write(to: outputPath)
            await MainActor.run { progressCallback?(1.0) }
            return outputPath
        }.value
    }

    func tryDecrypt(data: Data, passphrase: String) throws -> (Data, PGPKeyModel) {
        let secretKeys = keyringService.secretKeys()

        for keyModel in secretKeys {
            do {
                let decrypted = try decrypt(data: data, using: keyModel, passphrase: passphrase)
                return (decrypted, keyModel)
            } catch OperationError.invalidPassphrase {
                continue
            } catch {
                continue
            }
        }

        throw OperationError.decryptionFailed(underlying: nil)
    }
}
