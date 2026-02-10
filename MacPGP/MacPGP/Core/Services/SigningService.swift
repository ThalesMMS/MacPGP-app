import Foundation
import ObjectivePGP

struct VerificationResult {
    let isValid: Bool
    let signerKey: PGPKeyModel?
    let signatureDate: Date?
    let message: String
    let originalMessage: String?

    static func valid(signer: PGPKeyModel?, date: Date?, originalMessage: String? = nil) -> VerificationResult {
        VerificationResult(
            isValid: true,
            signerKey: signer,
            signatureDate: date,
            message: "Signature is valid",
            originalMessage: originalMessage
        )
    }

    static func invalid(reason: String) -> VerificationResult {
        VerificationResult(
            isValid: false,
            signerKey: nil,
            signatureDate: nil,
            message: reason,
            originalMessage: nil
        )
    }
}

final class SigningService {
    private let keyringService: KeyringService

    init(keyringService: KeyringService) {
        self.keyringService = keyringService
    }

    func sign(
        data: Data,
        using key: PGPKeyModel,
        passphrase: String,
        detached: Bool = false,
        armored: Bool = true
    ) throws -> Data {
        guard let rawKey = keyringService.rawKey(for: key) else {
            throw OperationError.keyNotFound(keyID: key.shortKeyID)
        }

        guard rawKey.isSecret else {
            throw OperationError.noSecretKey
        }

        // Validate signing key is not expired or revoked
        if key.isRevoked {
            throw OperationError.keyRevoked
        }
        if key.isExpired {
            throw OperationError.keyExpired
        }

        do {
            var signedData = try ObjectivePGP.sign(
                data,
                detached: detached,
                using: [rawKey],
                passphraseForKey: { _ in passphrase }
            )

            if armored {
                let armorType: PGPArmorType = detached ? .signature : .message
                let armoredString = Armor.armored(signedData, as: armorType)
                signedData = armoredString.data(using: .utf8) ?? signedData
            }

            return signedData
        } catch {
            let nsError = error as NSError
            if nsError.domain == "ObjectivePGP" && nsError.code == 2 {
                throw OperationError.invalidPassphrase
            }
            throw OperationError.signingFailed(underlying: error)
        }
    }

    func sign(
        message: String,
        using key: PGPKeyModel,
        passphrase: String,
        cleartext: Bool = true,
        detached: Bool = false,
        armored: Bool = true
    ) throws -> String {
        guard let messageData = message.data(using: .utf8) else {
            throw OperationError.signingFailed(underlying: nil)
        }

        // For cleartext signing, create a PGP SIGNED MESSAGE format
        if cleartext && !detached && armored {
            // Create detached signature first
            let signatureData = try sign(
                data: messageData,
                using: key,
                passphrase: passphrase,
                detached: true,
                armored: false
            )

            // Armor just the signature
            let armoredSignature = Armor.armored(signatureData, as: .signature)

            // Build cleartext signed message
            var result = "-----BEGIN PGP SIGNED MESSAGE-----\n"
            result += "Hash: SHA256\n"
            result += "\n"
            result += message
            if !message.hasSuffix("\n") {
                result += "\n"
            }
            result += armoredSignature

            return result
        }

        let signedData = try sign(
            data: messageData,
            using: key,
            passphrase: passphrase,
            detached: detached,
            armored: armored
        )

        if armored {
            return String(data: signedData, encoding: .utf8) ?? ""
        } else {
            return signedData.base64EncodedString()
        }
    }

    func sign(
        file: URL,
        using key: PGPKeyModel,
        passphrase: String,
        detached: Bool = true,
        outputURL: URL? = nil,
        armored: Bool = true
    ) throws -> URL {
        let fileData = try Data(contentsOf: file)

        let signedData = try sign(
            data: fileData,
            using: key,
            passphrase: passphrase,
            detached: detached,
            armored: armored
        )

        let outputPath: URL
        if let output = outputURL {
            outputPath = output
        } else if detached {
            outputPath = file.appendingPathExtension(armored ? "asc" : "sig")
        } else {
            outputPath = file.appendingPathExtension(armored ? "asc" : "gpg")
        }

        try signedData.write(to: outputPath)
        return outputPath
    }

    func verify(data: Data, signature: Data? = nil) throws -> VerificationResult {
        let allKeys = keyringService.keys.compactMap { keyringService.rawKey(for: $0) }

        guard !allKeys.isEmpty else {
            return .invalid(reason: "No keys available for verification")
        }

        do {
            try ObjectivePGP.verify(data, withSignature: signature, using: allKeys)

            let signerKey = findSignerKey(in: signature ?? data)
            return .valid(signer: signerKey, date: nil)
        } catch {
            return .invalid(reason: error.localizedDescription)
        }
    }

    func verify(message: String, signature: String? = nil) throws -> VerificationResult {
        // Check if this is a cleartext signed message
        if message.hasPrefix("-----BEGIN PGP SIGNED MESSAGE-----") {
            return try verifyCleartextSignedMessage(message)
        }

        guard let messageData = message.data(using: .utf8) else {
            throw OperationError.verificationFailed(underlying: nil)
        }

        var signatureData: Data?
        if let signature = signature {
            // Check if signature is armored (ASCII) or base64-encoded binary
            if signature.hasPrefix("-----BEGIN PGP SIGNATURE-----") {
                // Armored signature - convert from UTF-8
                signatureData = signature.data(using: .utf8)
            } else {
                // Base64-encoded binary signature - decode from base64
                signatureData = Data(base64Encoded: signature)
            }
        }

        return try verify(data: messageData, signature: signatureData)
    }

    private func verifyCleartextSignedMessage(_ signedMessage: String) throws -> VerificationResult {
        // Parse the cleartext signed message format
        guard let signatureStart = signedMessage.range(of: "-----BEGIN PGP SIGNATURE-----") else {
            return .invalid(reason: "Invalid cleartext signed message format")
        }

        // Extract the message body (between header and signature)
        let headerEnd = signedMessage.range(of: "\n\n", range: signedMessage.startIndex..<signatureStart.lowerBound)
        guard let headerEndRange = headerEnd else {
            return .invalid(reason: "Invalid cleartext signed message header")
        }

        var messageBody = String(signedMessage[headerEndRange.upperBound..<signatureStart.lowerBound])
        // Remove trailing newline that was added before signature
        if messageBody.hasSuffix("\n") {
            messageBody.removeLast()
        }

        // Extract the signature
        let signatureString = String(signedMessage[signatureStart.lowerBound...])

        guard let messageData = messageBody.data(using: .utf8),
              let signatureData = signatureString.data(using: .utf8) else {
            return .invalid(reason: "Failed to parse message or signature")
        }

        // Verify the detached signature against the message
        let allKeys = keyringService.keys.compactMap { keyringService.rawKey(for: $0) }

        guard !allKeys.isEmpty else {
            return .invalid(reason: "No keys available for verification")
        }

        do {
            try ObjectivePGP.verify(messageData, withSignature: signatureData, using: allKeys)
            let signerKey = findSignerKey(in: signatureData)
            return .valid(signer: signerKey, date: nil, originalMessage: messageBody)
        } catch {
            return .invalid(reason: error.localizedDescription)
        }
    }

    func verify(file: URL, signatureFile: URL? = nil) throws -> VerificationResult {
        let fileData = try Data(contentsOf: file)

        var signatureData: Data?
        if let sigFile = signatureFile {
            signatureData = try Data(contentsOf: sigFile)
        }

        return try verify(data: fileData, signature: signatureData)
    }

    private func findSignerKey(in signatureData: Data) -> PGPKeyModel? {
        return nil
    }
}
