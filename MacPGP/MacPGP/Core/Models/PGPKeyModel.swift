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
        self.rawKey = key.rawKey
    }

    init(
        from key: Key,
        isVerified: Bool,
        verificationDate: Date?,
        verificationMethod: FingerprintVerificationMethod?,
        trustLevel: TrustLevel = .unknown
    ) {
        let primaryKeyPacket = key.publicKey?.value(forKey: "primaryKeyPacket") as? NSObject
        let derivedAlgorithm = Self.mapAlgorithm(from: primaryKeyPacket)

        self.rawKey = key
        self.fingerprint = key.publicKey?.fingerprint.description() ?? ""
        self.id = fingerprint
        self.shortKeyID = String(fingerprint.suffix(16))

        self.algorithm = derivedAlgorithm
        self.keySize = Self.extractKeySize(from: primaryKeyPacket, algorithm: derivedAlgorithm)
        self.creationDate = Self.extractCreationDate(from: primaryKeyPacket)

        self.expirationDate = key.expirationDate

        if let expDate = key.expirationDate {
            self.isExpired = expDate < Date()
        } else {
            self.isExpired = false
        }

        self.isSecretKey = key.isSecret

        // Check for revocation status
        // Note: ObjectivePGP may not have direct revocation status, so we default to false
        self.isRevoked = false
        self.revokedDate = nil

        // Verification status from parameters
        self.isVerified = isVerified
        self.verificationDate = verificationDate
        self.verificationMethod = verificationMethod

        // Trust level from parameter
        self.trustLevel = trustLevel

        self.userIDs = key.publicKey?.users.compactMap { user -> KeyIdentity? in
            let userID = user.userID
            guard !userID.isEmpty else { return nil }
            return KeyIdentity.parse(from: userID)
        } ?? []
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

    private static func mapAlgorithm(from packet: NSObject?) -> KeyAlgorithm {
        guard let algorithm = packet?
            .value(forKey: "publicKeyAlgorithm") as? NSNumber else {
            return .unknown
        }

        // publicKeyAlgorithm stores OpenPGP algorithm IDs from RFC 4880 section 9.1
        // and RFC 9580 section 9.1: 1/2/3 = RSA, 16/20 = Elgamal, 17 = DSA,
        // 19 = ECDSA, 22 = EdDSA. See https://www.rfc-editor.org/rfc/rfc4880#section-9.1
        // and https://www.rfc-editor.org/rfc/rfc9580#section-9.1.
        switch algorithm.intValue {
        case 1, 2, 3:
            return .rsa
        case 19:
            return .ecdsa
        case 22:
            return .eddsa
        case 17:
            return .dsa
        case 16, 20:
            return .elgamal
        default:
            return .unknown
        }
    }

    private static func extractCreationDate(from packet: NSObject?) -> Date {
        packet?.value(forKey: "createDate") as? Date ?? Date()
    }

    private static func extractKeySize(from packet: NSObject?, algorithm: KeyAlgorithm) -> Int {
        guard let packet else {
            return algorithm.defaultKeySize
        }

        switch algorithm {
        case .rsa:
            return mpiBitCount(from: packet, identifier: "N") ?? algorithm.defaultKeySize
        case .ecdsa:
            return ellipticCurveKeySize(from: packet) ?? algorithm.defaultKeySize
        case .eddsa:
            return 256
        case .dsa, .elgamal:
            return mpiBitCount(from: packet, identifier: "P") ?? algorithm.defaultKeySize
        case .unknown:
            return 0
        }
    }

    private static func mpiBitCount(from packet: NSObject, identifier: String) -> Int? {
        guard
            let mpi = publicMPI(from: packet, identifier: identifier),
            let bigNum = mpi.value(forKey: "bigNum") as? NSObject,
            let bitsCount = bigNum.value(forKey: "bitsCount") as? NSNumber,
            bitsCount.intValue > 0
        else {
            return nil
        }

        return bitsCount.intValue
    }

    private static func publicMPI(from packet: NSObject, identifier: String) -> NSObject? {
        let selector = NSSelectorFromString("publicMPI:")
        guard packet.responds(to: selector) else {
            return nil
        }

        return packet.perform(selector, with: identifier)?.takeUnretainedValue() as? NSObject
    }

    private static func ellipticCurveKeySize(from packet: NSObject) -> Int? {
        guard
            let curveOID = packet.value(forKey: "curveOID") as? NSObject,
            let curveKind = curveOID.value(forKey: "curveKind") as? NSNumber
        else {
            return nil
        }

        // curveKind is ObjectivePGP.PGPCurve.rawValue: 0 = P-256, 1 = P-384,
        // 2 = P-521, 3 = BrainpoolP256r1, 4 = BrainpoolP512r1, 5 = Ed25519,
        // 6 = Curve25519. Those raw values collapse to 256 bits for 0/3/5/6,
        // 384 for 1, 521 for 2, and 512 for 4.
        switch curveKind.intValue {
        case 0, 3, 5, 6:
            return 256
        case 1:
            return 384
        case 2:
            return 521
        case 4:
            return 512
        default:
            return nil
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
