import Foundation
import RNPBridge

public struct Fingerprint: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public var description: String {
        rawValue
    }
}

public struct KeyUser: Hashable, Sendable {
    public let userID: String

    public init(userID: String) {
        self.userID = userID
    }
}

public enum PublicKeyAlgorithm: String, Sendable, Hashable {
    case rsa
    case ecdsa
    case eddsa
    case ecdh
    case curve25519
    case dsa
    case elgamal
    case unknown

    static func from(rnp name: String) -> PublicKeyAlgorithm {
        switch name.uppercased() {
        case "RSA":
            return .rsa
        case "ECDSA":
            return .ecdsa
        case "EDDSA", "ED25519":
            return .eddsa
        case "ECDH":
            return .ecdh
        case "X25519", "CURVE25519":
            return .curve25519
        case "DSA":
            return .dsa
        case "ELGAMAL":
            return .elgamal
        default:
            return .unknown
        }
    }
}

public struct KeyCapabilities: Hashable, Sendable {
    public let canEncrypt: Bool
    public let canSign: Bool

    public init(canEncrypt: Bool, canSign: Bool) {
        self.canEncrypt = canEncrypt
        self.canSign = canSign
    }
}

public struct PublicKey: Hashable, Sendable {
    public let exportedData: Data
    public let fingerprint: Fingerprint
    public let users: [KeyUser]
    public let algorithm: PublicKeyAlgorithm
    public let keySize: Int
    public let capabilities: KeyCapabilities
    let metadata: Key.Metadata

    init(exportedData: Data, metadata: Key.Metadata) {
        self.exportedData = exportedData
        self.fingerprint = Fingerprint(metadata.fingerprint)
        self.users = metadata.userIDs.map { KeyUser(userID: $0) }
        self.algorithm = metadata.primaryAlgorithm
        self.keySize = metadata.primaryKeySize
        self.capabilities = metadata.capabilities
        self.metadata = metadata
    }
}

public struct SecretKey: Hashable, Sendable {
    public let exportedData: Data
    public let fingerprint: Fingerprint
    let metadata: Key.Metadata

    init(exportedData: Data, metadata: Key.Metadata) {
        self.exportedData = exportedData
        self.fingerprint = Fingerprint(metadata.fingerprint)
        self.metadata = metadata
    }
}

public struct Key: Hashable, Sendable {
    public struct Metadata: Hashable, Sendable {
        public let fingerprint: String
        public let shortKeyID: String
        public let userIDs: [String]
        public let primaryAlgorithm: PublicKeyAlgorithm
        public let primaryKeySize: Int
        public let creationDate: Date
        public let expirationDate: Date?
        public let isRevoked: Bool
        public let revokedDate: Date?
        public let capabilities: KeyCapabilities

        public init(
            fingerprint: String,
            shortKeyID: String,
            userIDs: [String],
            primaryAlgorithm: PublicKeyAlgorithm,
            primaryKeySize: Int,
            creationDate: Date,
            expirationDate: Date?,
            isRevoked: Bool,
            revokedDate: Date?,
            capabilities: KeyCapabilities
        ) {
            self.fingerprint = fingerprint.uppercased()
            self.shortKeyID = shortKeyID.uppercased()
            self.userIDs = userIDs
            self.primaryAlgorithm = primaryAlgorithm
            self.primaryKeySize = primaryKeySize
            self.creationDate = creationDate
            self.expirationDate = expirationDate
            self.isRevoked = isRevoked
            self.revokedDate = revokedDate
            self.capabilities = capabilities
        }
    }

    public let publicKey: PublicKey?
    public let secretKey: SecretKey?
    public let metadata: Metadata

    public init(secretKey: SecretKey?, publicKey: PublicKey?) {
        guard let metadata = publicKey.map(\.metadata) ?? secretKey.map(\.metadata) else {
            preconditionFailure("Key requires at least a public or secret key payload")
        }

        self.publicKey = publicKey
        self.secretKey = secretKey
        self.metadata = metadata
    }

    init(publicData: Data?, secretData: Data?, metadata: Metadata) {
        self.publicKey = publicData.map { PublicKey(exportedData: $0, metadata: metadata) }
        self.secretKey = secretData.map { SecretKey(exportedData: $0, metadata: metadata) }
        self.metadata = metadata
    }

    public var fingerprint: String {
        metadata.fingerprint
    }

    public var shortKeyID: String {
        metadata.shortKeyID
    }

    public var expirationDate: Date? {
        metadata.expirationDate
    }

    public var isSecret: Bool {
        secretKey != nil
    }

    public var isRevoked: Bool {
        metadata.isRevoked
    }

    public var userIDs: [String] {
        metadata.userIDs
    }

    public var capabilities: KeyCapabilities {
        metadata.capabilities
    }

    public func export() throws -> Data {
        if let secretKey {
            return secretKey.exportedData
        }
        if let publicKey {
            return publicKey.exportedData
        }
        return Data()
    }

    public func exportPublic() throws -> Data {
        guard let publicKey else {
            throw ObjectivePGPError.missingPublicKey
        }
        return publicKey.exportedData
    }

    public func exportRevocation(
        hash: String? = nil,
        reasonCode: String = "no",
        reason: String? = nil,
        passphraseForKey: ((Key) -> String?)? = nil
    ) throws -> Data {
        try RNP.exportRevocation(
            for: self,
            hash: hash,
            reasonCode: reasonCode,
            reason: reason,
            passphraseForKey: passphraseForKey
        )
    }

    public func applyRevocation(
        _ certificate: Data,
        passphraseForKey: ((Key) -> String?)? = nil
    ) throws -> Key {
        try RNP.applyRevocation(
            certificate,
            to: self,
            passphraseForKey: passphraseForKey
        )
    }

    public func setExpiration(
        _ expirationDate: Date?,
        passphraseForKey: ((Key) -> String?)? = nil
    ) throws -> Key {
        try RNP.setExpiration(
            expirationDate,
            for: self,
            passphraseForKey: passphraseForKey
        )
    }
}

public enum PGPArmorType: String, Sendable {
    case message = "message"
    case publicKey = "public key"
    case secretKey = "secret key"
    case signature = "signature"
    case cleartext = "cleartext"
}

public struct ProtectionInfo: Hashable, Sendable {
    public let mode: String?
    public let cipher: String?
}

/// Signature verification metadata returned by RNP.
/// `isValid` reflects mathematical validity at signature creation time and may still be `true`
/// for signatures that have since expired. Use `isExpired` to distinguish that case.
public struct VerifiedSignature: Hashable, Sendable {
    public let keyID: String?
    public let fingerprint: String?
    public let creationDate: Date?
    public let expiresAfter: TimeInterval?
    public let statusCode: UInt32
    public let isValid: Bool

    public var isExpired: Bool {
        statusCode == RNP_ERROR_SIGNATURE_EXPIRED
    }
}

public struct MessageInspection: Sendable {
    public let contents: String
    public let isArmored: Bool
    public let isEncrypted: Bool
    public let isSigned: Bool
    public let recipientKeyIDs: [String]
    public let protection: ProtectionInfo?
    public let signatures: [VerifiedSignature]
    public let literalFilename: String?
    public let literalMTime: Date?
    public let outputData: Data?
}

public enum ObjectivePGPError: Error {
    case missingPublicKey
    case missingSecretKey
    case missingDecryptedOutput
    case missingSigningKey
}
