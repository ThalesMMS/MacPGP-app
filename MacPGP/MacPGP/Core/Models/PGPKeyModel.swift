import Foundation
import ObjectivePGP

enum ExpirationWarningLevel {
    case none
    case warning    // 30 days or less
    case critical   // 7 days or less
    case expired
}

enum FingerprintVerificationMethod: String, Codable {
    case inPerson = "in_person"
    case phone = "phone"
    case qrCode = "qr_code"
    case trusted = "trusted"
}

struct PGPKeyModel: Identifiable, Hashable {
    let id: String
    let fingerprint: String
    let shortKeyID: String
    let algorithm: KeyAlgorithm
    let keySize: Int
    let creationDate: Date
    let expirationDate: Date?
    let userIDs: [KeyIdentity]
    let isSecretKey: Bool
    let isExpired: Bool
    let isRevoked: Bool
    let revokedDate: Date?
    let isVerified: Bool
    let verificationDate: Date?
    let verificationMethod: FingerprintVerificationMethod?
    let trustLevel: TrustLevel
    let canEncrypt: Bool
    let canSign: Bool
    let rawKey: Key

    init(from key: Key) {
        self.init(
            from: key,
            isVerified: false,
            verificationDate: nil,
            verificationMethod: nil,
            trustLevel: .unknown
        )
    }

    init(
        copying key: PGPKeyModel,
        isExpired: Bool? = nil,
        isRevoked: Bool? = nil,
        revokedDate: Date? = nil,
        trustLevel: TrustLevel? = nil
    ) {
        let expired = isExpired ?? key.isExpired
        let revoked = isRevoked ?? key.isRevoked

        self.id = key.id
        self.fingerprint = key.fingerprint
        self.shortKeyID = key.shortKeyID
        self.algorithm = key.algorithm
        self.keySize = key.keySize
        self.creationDate = key.creationDate
        self.expirationDate = key.expirationDate
        self.userIDs = key.userIDs
        self.isSecretKey = key.isSecretKey
        self.isExpired = expired
        self.isRevoked = revoked
        self.revokedDate = revokedDate ?? key.revokedDate
        self.isVerified = key.isVerified
        self.verificationDate = key.verificationDate
        self.verificationMethod = key.verificationMethod
        self.trustLevel = trustLevel ?? key.trustLevel
        self.canEncrypt = key.canEncrypt
        self.canSign = key.canSign
        self.rawKey = key.rawKey
    }

    init(
        from key: Key,
        isVerified: Bool,
        verificationDate: Date?,
        verificationMethod: FingerprintVerificationMethod?,
        trustLevel: TrustLevel = .unknown
    ) {
        let derivedAlgorithm = Self.mapAlgorithm(from: key.metadata.primaryAlgorithm)

        self.rawKey = key
        self.fingerprint = key.metadata.fingerprint
        self.id = fingerprint
        self.shortKeyID = key.metadata.shortKeyID

        self.algorithm = derivedAlgorithm
        self.keySize = key.metadata.primaryKeySize
        self.creationDate = key.metadata.creationDate
        self.expirationDate = key.metadata.expirationDate
        self.isExpired = key.metadata.expirationDate.map { $0 < Date() } ?? false

        self.isSecretKey = key.isSecret
        self.isRevoked = key.metadata.isRevoked
        self.revokedDate = key.metadata.revokedDate

        // Verification status from parameters
        self.isVerified = isVerified
        self.verificationDate = verificationDate
        self.verificationMethod = verificationMethod

        // Trust level from parameter
        self.trustLevel = trustLevel

        self.userIDs = key.metadata.userIDs.compactMap { userID -> KeyIdentity? in
            guard !userID.isEmpty else { return nil }
            return KeyIdentity.parse(from: userID)
        }
        self.canEncrypt = key.metadata.capabilities.canEncrypt
        self.canSign = key.metadata.capabilities.canSign
    }

    var primaryUserID: KeyIdentity? {
        userIDs.first
    }

    var displayName: String {
        primaryUserID?.shortDisplayString ?? shortKeyID
    }

    var email: String? {
        primaryUserID?.email
    }

    var formattedFingerprint: String {
        stride(from: 0, to: fingerprint.count, by: 4).map { i -> String in
            let start = fingerprint.index(fingerprint.startIndex, offsetBy: i)
            let end = fingerprint.index(start, offsetBy: min(4, fingerprint.count - i))
            return String(fingerprint[start..<end])
        }.joined(separator: " ")
    }

    var keyTypeDescription: String {
        if isSecretKey {
            return "Secret & Public Key"
        } else {
            return "Public Key Only"
        }
    }

    var algorithmDescription: String {
        "\(algorithm.displayName) \(keySize)"
    }

    var daysUntilExpiration: Int? {
        guard let expDate = expirationDate else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.day], from: now, to: expDate)
        return components.day
    }

    var isExpiringSoon: Bool {
        guard let days = daysUntilExpiration else { return false }
        return days <= 30 && days >= 0
    }

    var expirationWarningLevel: ExpirationWarningLevel {
        if isExpired {
            return .expired
        }

        guard let days = daysUntilExpiration else {
            return .none
        }

        if days <= 0 {
            return .expired
        } else if days <= 7 {
            return .critical
        } else if days <= 30 {
            return .warning
        } else {
            return .none
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PGPKeyModel, rhs: PGPKeyModel) -> Bool {
        lhs.id == rhs.id
    }

    private static func mapAlgorithm(from algorithm: PublicKeyAlgorithm) -> KeyAlgorithm {
        switch algorithm {
        case .rsa:
            return .rsa
        case .ecdsa:
            return .ecdsa
        case .eddsa:
            return .eddsa
        case .dsa:
            return .dsa
        case .elgamal:
            return .elgamal
        case .ecdh, .curve25519, .unknown:
            return .unknown
        default:
            return .unknown
        }
    }
}

extension PGPKeyModel {
    static var preview: PGPKeyModel {
        let keyGenerator = KeyGenerator()
        let key = keyGenerator.generate(
            for: "preview@example.com",
            passphrase: "preview"
        )
        return PGPKeyModel(from: key)
    }
}
