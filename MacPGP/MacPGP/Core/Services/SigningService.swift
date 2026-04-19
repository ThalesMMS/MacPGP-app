import Foundation
import ObjectivePGP

enum VerificationOutcome: Sendable, Equatable {
    case valid
    case invalidSignature
    case error

    nonisolated static func == (lhs: VerificationOutcome, rhs: VerificationOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.valid, .valid), (.invalidSignature, .invalidSignature), (.error, .error):
            return true
        default:
            return false
        }
    }
}

struct VerificationResult {
    let outcome: VerificationOutcome
    let signerKey: PGPKeyModel?
    let signatureDate: Date?
    let message: String
    let originalMessage: String?

    var isValid: Bool {
        outcome == .valid
    }

    var isError: Bool {
        outcome == .error
    }

    var signerKeyID: String? {
        signerKey?.shortKeyID
    }

    var title: String {
        switch outcome {
        case .valid:
            return "Signature Valid"
        case .invalidSignature:
            return "Signature Invalid"
        case .error:
            return "Verification Error"
        }
    }

    var symbolName: String {
        switch outcome {
        case .valid:
            return "checkmark.seal.fill"
        case .invalidSignature:
            return "xmark.seal.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    /// Create a VerificationResult representing a successful signature verification.
    /// - Parameters:
    ///   - signer: The key model for the signer, or `nil` if unknown.
    ///   - date: The signature timestamp, or `nil` if unavailable.
    ///   - originalMessage: The original signed message when available; `nil` otherwise.
    /// - Returns: A `VerificationResult` with outcome `.valid`, message `"Signature is valid"`, and the provided signer, date, and originalMessage.
    static func valid(signer: PGPKeyModel?, date: Date?, originalMessage: String? = nil) -> VerificationResult {
        VerificationResult(
            outcome: .valid,
            signerKey: signer,
            signatureDate: date,
            message: "Signature is valid",
            originalMessage: originalMessage
        )
    }

    /// Creates a verification result representing a signature verification failure.
    /// - Parameter reason: A human-readable explanation for why verification failed.
    /// - Returns: A `VerificationResult` with `outcome` set to `.invalidSignature`, `message` set to `reason`, and `signerKey`, `signatureDate`, and `originalMessage` set to `nil`.
    static func invalid(reason: String) -> VerificationResult {
        VerificationResult(
            outcome: .invalidSignature,
            signerKey: nil,
            signatureDate: nil,
            message: reason,
            originalMessage: nil
        )
    }

    /// Creates a `VerificationResult` representing a verification error with the provided message.
    /// - Parameter reason: A human-readable explanation for the verification error.
    /// - Returns: A `VerificationResult` with `outcome == .error`, `message` set to `reason`, and other contextual fields (`signerKey`, `signatureDate`, `originalMessage`) set to `nil`.
    static func verificationError(reason: String) -> VerificationResult {
        VerificationResult(
            outcome: .error,
            signerKey: nil,
            signatureDate: nil,
            message: reason,
            originalMessage: nil
        )
    }
}

private struct SigningKeySnapshot: @unchecked Sendable {
    nonisolated(unsafe) let rawKey: Key
    let shortKeyID: String
    let isSecret: Bool
    let isRevoked: Bool
    let isExpired: Bool
}

private struct VerificationKeySnapshot: @unchecked Sendable {
    nonisolated(unsafe) let rawKey: Key
    let shortKeyID: String
}

private struct DetachedVerificationPayload: Sendable {
    let outcome: String
    let signerShortID: String?
    let message: String
    let originalMessage: String?
}

final class SigningService {
    private let keyringService: KeyringService

    init(keyringService: KeyringService) {
        self.keyringService = keyringService
    }

    private func signingSnapshot(for key: PGPKeyModel) throws -> SigningKeySnapshot {
        guard let rawKey = keyringService.rawKey(for: key) else {
            throw OperationError.keyNotFound(keyID: key.shortKeyID)
        }

        return SigningKeySnapshot(
            rawKey: rawKey,
            shortKeyID: key.shortKeyID,
            isSecret: rawKey.isSecret,
            isRevoked: key.isRevoked,
            isExpired: key.isExpired
        )
    }

    private func verificationSnapshots() -> [VerificationKeySnapshot] {
        keyringService.keys.compactMap { keyModel in
            guard let rawKey = keyringService.rawKey(for: keyModel) else {
                return nil
            }

            return VerificationKeySnapshot(rawKey: rawKey, shortKeyID: keyModel.shortKeyID)
        }
    }

    private func verificationResult(from payload: DetachedVerificationPayload) -> VerificationResult {
        let signerKey = payload.signerShortID.flatMap { keyringService.key(withShortID: $0) }

        switch payload.outcome {
        case "valid":
            return .valid(signer: signerKey, date: nil, originalMessage: payload.originalMessage)
        case "invalidSignature":
            return .invalid(reason: payload.message)
        default:
            return .verificationError(reason: payload.message)
        }
    }

    nonisolated private static func signData(
        _ data: Data,
        using snapshot: SigningKeySnapshot,
        passphrase: String,
        detached: Bool,
        armored: Bool
    ) throws -> Data {
        guard snapshot.isSecret else {
            throw OperationError.noSecretKey
        }

        if snapshot.isRevoked {
            throw OperationError.keyRevoked
        }
        if snapshot.isExpired {
            throw OperationError.keyExpired
        }

        do {
            var signedData = try ObjectivePGP.sign(
                data,
                detached: detached,
                using: [snapshot.rawKey],
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

    nonisolated private static func signMessage(
        _ message: String,
        using snapshot: SigningKeySnapshot,
        passphrase: String,
        cleartext: Bool,
        detached: Bool,
        armored: Bool
    ) throws -> String {
        guard let messageData = message.data(using: .utf8) else {
            throw OperationError.signingFailed(underlying: nil)
        }

        if cleartext && !detached && armored {
            let signatureData = try signData(
                messageData,
                using: snapshot,
                passphrase: passphrase,
                detached: true,
                armored: false
            )

            let armoredSignature = Armor.armored(signatureData, as: .signature)

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

        let signedData = try signData(
            messageData,
            using: snapshot,
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

    nonisolated private static func signFile(
        _ file: URL,
        using snapshot: SigningKeySnapshot,
        passphrase: String,
        detached: Bool,
        outputURL: URL?,
        armored: Bool
    ) throws -> URL {
        let fileData = try SecureScopedFileAccess.readData(from: file)
        let signedData = try signData(
            fileData,
            using: snapshot,
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

        try SecureScopedFileAccess.writeData(signedData, to: outputPath)
        return outputPath
    }

    func sign(
        data: Data,
        using key: PGPKeyModel,
        passphrase: String,
        detached: Bool = false,
        armored: Bool = true
    ) throws -> Data {
        let snapshot = try signingSnapshot(for: key)
        return try Self.signData(
            data,
            using: snapshot,
            passphrase: passphrase,
            detached: detached,
            armored: armored
        )
    }

    func sign(
        message: String,
        using key: PGPKeyModel,
        passphrase: String,
        cleartext: Bool = true,
        detached: Bool = false,
        armored: Bool = true
    ) throws -> String {
        let snapshot = try signingSnapshot(for: key)
        return try Self.signMessage(
            message,
            using: snapshot,
            passphrase: passphrase,
            cleartext: cleartext,
            detached: detached,
            armored: armored
        )
    }

    func signAsync(
        message: String,
        using key: PGPKeyModel,
        passphrase: String,
        cleartext: Bool = true,
        detached: Bool = false,
        armored: Bool = true
    ) async throws -> String {
        let snapshot = try signingSnapshot(for: key)

        return try await Task.detached(priority: .userInitiated) {
            try Self.signMessage(
                message,
                using: snapshot,
                passphrase: passphrase,
                cleartext: cleartext,
                detached: detached,
                armored: armored
            )
        }.value
    }

    func sign(
        file: URL,
        using key: PGPKeyModel,
        passphrase: String,
        detached: Bool = true,
        outputURL: URL? = nil,
        armored: Bool = true
    ) throws -> URL {
        let snapshot = try signingSnapshot(for: key)
        return try Self.signFile(
            file,
            using: snapshot,
            passphrase: passphrase,
            detached: detached,
            outputURL: outputURL,
            armored: armored
        )
    }

    func signAsync(
        file: URL,
        using key: PGPKeyModel,
        passphrase: String,
        detached: Bool = true,
        outputURL: URL? = nil,
        armored: Bool = true
    ) async throws -> URL {
        let snapshot = try signingSnapshot(for: key)

        return try await Task.detached(priority: .userInitiated) {
            try Self.signFile(
                file,
                using: snapshot,
                passphrase: passphrase,
                detached: detached,
                outputURL: outputURL,
                armored: armored
            )
        }.value
    }

    nonisolated private static func verifyPayload(
        data: Data,
        signature: Data? = nil,
        using snapshots: [VerificationKeySnapshot],
        originalMessage: String? = nil
    ) -> DetachedVerificationPayload {
        let allKeys = snapshots.map(\.rawKey)

        guard !allKeys.isEmpty else {
            return DetachedVerificationPayload(
                outcome: "error",
                signerShortID: nil,
                message: "No keys available for verification",
                originalMessage: originalMessage
            )
        }

        do {
            try ObjectivePGP.verify(data, withSignature: signature, using: allKeys)

            let signerShortID = extractIssuerKeyID(from: signature ?? data).flatMap { issuerKeyID in
                snapshots.first {
                    $0.shortKeyID.hasSuffix(issuerKeyID) || issuerKeyID.hasSuffix($0.shortKeyID)
                }?.shortKeyID
            }

            return DetachedVerificationPayload(
                outcome: "valid",
                signerShortID: signerShortID,
                message: "Signature is valid",
                originalMessage: originalMessage
            )
        } catch {
            return DetachedVerificationPayload(
                outcome: "invalidSignature",
                signerShortID: nil,
                message: error.localizedDescription,
                originalMessage: originalMessage
            )
        }
    }

    nonisolated private static func verifyCleartextPayload(
        _ signedMessage: String,
        using snapshots: [VerificationKeySnapshot]
    ) -> DetachedVerificationPayload {
        guard let signatureStart = signedMessage.range(of: "-----BEGIN PGP SIGNATURE-----") else {
            return DetachedVerificationPayload(
                outcome: "error",
                signerShortID: nil,
                message: "Invalid cleartext signed message format",
                originalMessage: nil
            )
        }

        let headerEnd = signedMessage.range(of: "\n\n", range: signedMessage.startIndex..<signatureStart.lowerBound)
        guard let headerEndRange = headerEnd else {
            return DetachedVerificationPayload(
                outcome: "error",
                signerShortID: nil,
                message: "Invalid cleartext signed message header",
                originalMessage: nil
            )
        }

        var messageBody = String(signedMessage[headerEndRange.upperBound..<signatureStart.lowerBound])
        if messageBody.hasSuffix("\n") {
            messageBody.removeLast()
        }

        let signatureString = String(signedMessage[signatureStart.lowerBound...])
        guard let messageData = messageBody.data(using: .utf8),
              let signatureData = signatureString.data(using: .utf8) else {
            return DetachedVerificationPayload(
                outcome: "error",
                signerShortID: nil,
                message: "Failed to parse message or signature",
                originalMessage: nil
            )
        }

        return verifyPayload(
            data: messageData,
            signature: signatureData,
            using: snapshots,
            originalMessage: messageBody
        )
    }

    /// Verify a message's signature using keys available in the injected keyring.
    /// - Parameters:
    ///   - data: The message bytes to verify (or the combined signed message when `signature` is `nil`).
    ///   - signature: Optional signature bytes; when `nil`, verification will attempt to verify an embedded/inline signature inside `data`.
    /// - Returns: A `VerificationResult` indicating the outcome: `valid` with the signer when verification succeeds, `invalidSignature` with a reason when verification fails, or `error` with a reason when verification cannot proceed (for example, when no keys are available).
    func verify(data: Data, signature: Data? = nil) throws -> VerificationResult {
        let payload = Self.verifyPayload(
            data: data,
            signature: signature,
            using: verificationSnapshots()
        )
        return verificationResult(from: payload)
    }

    func verify(message: String, signature: String? = nil) throws -> VerificationResult {
        if message.hasPrefix("-----BEGIN PGP SIGNED MESSAGE-----") {
            let payload = Self.verifyCleartextPayload(message, using: verificationSnapshots())
            return verificationResult(from: payload)
        }

        guard let messageData = message.data(using: .utf8) else {
            return .verificationError(reason: "Failed to parse message or signature")
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

        let payload = Self.verifyPayload(
            data: messageData,
            signature: signatureData,
            using: verificationSnapshots()
        )
        return verificationResult(from: payload)
    }

    func verifyAsync(message: String, signature: String? = nil) async throws -> VerificationResult {
        let snapshots = verificationSnapshots()

        if message.hasPrefix("-----BEGIN PGP SIGNED MESSAGE-----") {
            let payload = await Task.detached(priority: .userInitiated) {
                Self.verifyCleartextPayload(message, using: snapshots)
            }.value
            return verificationResult(from: payload)
        }

        guard let messageData = message.data(using: .utf8) else {
            return .verificationError(reason: "Failed to parse message or signature")
        }

        var signatureData: Data?
        if let signature = signature {
            if signature.hasPrefix("-----BEGIN PGP SIGNATURE-----") {
                signatureData = signature.data(using: .utf8)
            } else {
                signatureData = Data(base64Encoded: signature)
            }
        }

        let payload = await Task.detached(priority: .userInitiated) {
            Self.verifyPayload(data: messageData, signature: signatureData, using: snapshots)
        }.value
        return verificationResult(from: payload)
    }

    /// Parses a cleartext PGP-signed message and verifies its detached signature.
    /// 
    /// Expects a message that contains the `"-----BEGIN PGP SIGNED MESSAGE-----"` header, optional header lines (e.g., `Hash: SHA256`), a blank line, the message body, and a PGP signature block starting with `"-----BEGIN PGP SIGNATURE-----"`.
    /// - Parameters:
    ///   - signedMessage: The full cleartext signed message text including headers, message body, and signature block.
    /// - Returns: A `VerificationResult` representing one of:
    ///   - a `.valid` outcome containing the signer (if found) and `originalMessage` when verification succeeds;
    ///   - an `.invalidSignature` outcome with a reason when signature verification fails;
    ///   - an `.error` outcome with a reason when the message format cannot be parsed or no verification keys are available.
    private func verifyCleartextSignedMessage(_ signedMessage: String) throws -> VerificationResult {
        let payload = Self.verifyCleartextPayload(signedMessage, using: verificationSnapshots())
        return verificationResult(from: payload)
    }

    func verify(file: URL, signatureFile: URL? = nil) throws -> VerificationResult {
        let fileData = try SecureScopedFileAccess.readData(from: file)

        var signatureData: Data?
        if let sigFile = signatureFile {
            signatureData = try SecureScopedFileAccess.readData(from: sigFile)
        }

        return try verify(data: fileData, signature: signatureData)
    }

    /// Verifies a file's signature asynchronously using the service's available verification keys.
    /// - Parameters:
    ///   - file: The URL of the file to verify.
    ///   - signatureFile: An optional URL to a detached signature file; pass `nil` when the signature is embedded or the file is cleartext-signed.
    /// - Returns: A `VerificationResult` describing the verification outcome, resolved signer (if any), and related metadata.
    func verifyAsync(file: URL, signatureFile: URL? = nil) async throws -> VerificationResult {
        let snapshots = verificationSnapshots()
        let payload = try await Task.detached(priority: .userInitiated) {
            let fileData = try SecureScopedFileAccess.readData(from: file)

            var signatureData: Data?
            if let signatureFile = signatureFile {
                signatureData = try SecureScopedFileAccess.readData(from: signatureFile)
            }

            return Self.verifyPayload(data: fileData, signature: signatureData, using: snapshots)
        }.value
        return verificationResult(from: payload)
    }

    /// Extracts the issuer (signer's) 8-byte key ID from a PGP signature if present.
    /// 
    /// Accepts either an ASCII-armored PGP signature/message or raw signature packet bytes and parses OpenPGP packets to locate a signature packet and its Issuer subpacket.
    /// - Parameter signatureData: Armored or raw signature data to inspect.
    /// - Returns: A 16-character uppercase hex string representing the 8-byte issuer key ID if found, `nil` otherwise.
    nonisolated static func extractIssuerKeyID(from signatureData: Data) -> String? {
        let packetData: Data
        if let armoredString = String(data: signatureData, encoding: .utf8),
           armoredString.hasPrefix("-----BEGIN PGP SIGNATURE-----") || armoredString.hasPrefix("-----BEGIN PGP MESSAGE-----") {
            guard let dearmoredData = try? Armor.readArmored(armoredString) else {
                return nil
            }
            packetData = dearmoredData
        } else {
            packetData = signatureData
        }

        let bytes = [UInt8](packetData)
        var offset = 0

        while offset < bytes.count {
            guard let packet = readPacket(in: bytes, offset: &offset) else {
                return nil
            }

            guard packet.bodyRange.upperBound <= bytes.count else {
                return nil
            }

            if packet.tag == 2 {
                return extractIssuerKeyID(fromSignaturePacketBody: Array(bytes[packet.bodyRange]))
            }
        }

        return nil
    }

    nonisolated private static func extractIssuerKeyID(fromSignaturePacketBody packetBody: [UInt8]) -> String? {
        guard packetBody.count >= 6 else {
            return nil
        }

        guard packetBody[0] == 4 else {
            print(
                "Unsupported signature packet version in extractIssuerKeyID: " +
                "version=\(packetBody[0]) bytes=\(packetBody.count)"
            )
            return nil
        }

        let hashedSubpacketLength = (Int(packetBody[4]) << 8) | Int(packetBody[5])
        let hashedSubpacketStart = 6
        let hashedSubpacketEnd = hashedSubpacketStart + hashedSubpacketLength

        guard hashedSubpacketEnd + 2 <= packetBody.count else {
            return nil
        }

        if let issuerKeyID = extractIssuerKeyID(
            fromSubpacketsIn: packetBody,
            range: hashedSubpacketStart..<hashedSubpacketEnd
        ) {
            return issuerKeyID
        }

        let unhashedLengthOffset = hashedSubpacketEnd
        let unhashedSubpacketLength = (Int(packetBody[unhashedLengthOffset]) << 8) | Int(packetBody[unhashedLengthOffset + 1])
        let unhashedSubpacketStart = unhashedLengthOffset + 2
        let unhashedSubpacketEnd = unhashedSubpacketStart + unhashedSubpacketLength

        guard unhashedSubpacketEnd <= packetBody.count else {
            return nil
        }

        return extractIssuerKeyID(
            fromSubpacketsIn: packetBody,
            range: unhashedSubpacketStart..<unhashedSubpacketEnd
        )
    }

    nonisolated private static func extractIssuerKeyID(fromSubpacketsIn bytes: [UInt8], range: Range<Int>) -> String? {
        var offset = range.lowerBound

        while offset < range.upperBound {
            guard let (subpacketLength, lengthFieldSize) = readSubpacketLength(
                in: bytes,
                offset: offset,
                upperBound: range.upperBound
            ) else {
                return nil
            }

            offset += lengthFieldSize

            guard subpacketLength > 0, offset + subpacketLength <= range.upperBound else {
                return nil
            }

            let type = bytes[offset] & 0x7F
            let bodyStart = offset + 1
            let bodyLength = subpacketLength - 1

            guard bodyLength >= 0 else {
                return nil
            }

            if type == 16 {
                guard bodyLength == 8, bodyStart + bodyLength <= range.upperBound else {
                    return nil
                }

                return bytes[bodyStart..<bodyStart + bodyLength]
                    .map { String(format: "%02X", $0) }
                    .joined()
            }

            offset += subpacketLength
        }

        return nil
    }

    nonisolated private static func readPacket(in bytes: [UInt8], offset: inout Int) -> (tag: UInt8, bodyRange: Range<Int>)? {
        guard offset < bytes.count else {
            return nil
        }

        let packetHeader = bytes[offset]
        guard (packetHeader & 0x80) != 0 else {
            return nil
        }

        let isNewFormat = (packetHeader & 0x40) != 0
        let packetTag: UInt8
        let packetLength: Int
        let bodyStart: Int

        if isNewFormat {
            packetTag = packetHeader & 0x3F
            let lengthOffset = offset + 1

            guard let (resolvedLength, headerLength) = readNewFormatPacketLength(in: bytes, offset: lengthOffset) else {
                return nil
            }

            packetLength = resolvedLength
            bodyStart = lengthOffset + headerLength
        } else {
            packetTag = (packetHeader & 0x3C) >> 2
            let lengthType = packetHeader & 0x03
            let lengthOffset = offset + 1

            guard let (resolvedLength, headerLength) = readOldFormatPacketLength(
                in: bytes,
                offset: lengthOffset,
                lengthType: lengthType
            ) else {
                return nil
            }

            packetLength = resolvedLength
            bodyStart = lengthOffset + headerLength
        }

        let bodyEnd = bodyStart + packetLength
        guard bodyStart <= bodyEnd, bodyEnd <= bytes.count else {
            return nil
        }

        offset = bodyEnd
        return (packetTag, bodyStart..<bodyEnd)
    }

    nonisolated private static func readNewFormatPacketLength(in bytes: [UInt8], offset: Int) -> (length: Int, headerLength: Int)? {
        guard offset < bytes.count else {
            return nil
        }

        let firstOctet = bytes[offset]

        switch firstOctet {
        case 0..<192:
            return (Int(firstOctet), 1)
        case 192..<224:
            guard offset + 1 < bytes.count else {
                return nil
            }

            let secondOctet = bytes[offset + 1]
            let length = ((Int(firstOctet) - 192) << 8) + Int(secondOctet) + 192
            return (length, 2)
        case 255:
            guard offset + 4 < bytes.count else {
                return nil
            }

            let length = (Int(bytes[offset + 1]) << 24) |
                         (Int(bytes[offset + 2]) << 16) |
                         (Int(bytes[offset + 3]) << 8) |
                         Int(bytes[offset + 4])
            return (length, 5)
        case 224..<255:
            print(
                "Unsupported partial body length in readNewFormatPacketLength: " +
                "firstOctet=\(firstOctet) offset=\(offset) bytes=\(bytes.count)"
            )
            return nil
        default:
            return nil
        }
    }

    nonisolated private static func readOldFormatPacketLength(in bytes: [UInt8], offset: Int, lengthType: UInt8) -> (length: Int, headerLength: Int)? {
        switch lengthType {
        case 0:
            guard offset < bytes.count else {
                return nil
            }
            return (Int(bytes[offset]), 1)
        case 1:
            guard offset + 1 < bytes.count else {
                return nil
            }
            let length = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
            return (length, 2)
        case 2:
            guard offset + 3 < bytes.count else {
                return nil
            }
            let length = (Int(bytes[offset]) << 24) |
                         (Int(bytes[offset + 1]) << 16) |
                         (Int(bytes[offset + 2]) << 8) |
                         Int(bytes[offset + 3])
            return (length, 4)
        case 3:
            guard offset <= bytes.count else {
                return nil
            }
            return (bytes.count - offset, 0)
        default:
            return nil
        }
    }

    nonisolated private static func readSubpacketLength(in bytes: [UInt8], offset: Int, upperBound: Int) -> (length: Int, headerLength: Int)? {
        guard offset < upperBound else {
            return nil
        }

        let firstOctet = bytes[offset]

        switch firstOctet {
        case 0..<192:
            return (Int(firstOctet), 1)
        case 192..<255:
            guard offset + 1 < upperBound else {
                return nil
            }

            let secondOctet = bytes[offset + 1]
            let length = ((Int(firstOctet) - 192) << 8) + Int(secondOctet) + 192
            return (length, 2)
        case 255:
            guard offset + 4 < upperBound else {
                return nil
            }

            let length = (Int(bytes[offset + 1]) << 24) |
                         (Int(bytes[offset + 2]) << 16) |
                         (Int(bytes[offset + 3]) << 8) |
                         Int(bytes[offset + 4])
            return (length, 5)
        default:
            return nil
        }
    }
}
