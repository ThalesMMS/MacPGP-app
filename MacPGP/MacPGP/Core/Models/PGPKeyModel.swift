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
        from key: Key,
        isVerified: Bool,
        verificationDate: Date?,
        verificationMethod: FingerprintVerificationMethod?,
        trustLevel: TrustLevel = .unknown
    ) {
        self.rawKey = key
        self.fingerprint = key.publicKey?.fingerprint.description() ?? ""
        self.id = fingerprint
        self.shortKeyID = String(fingerprint.suffix(16))

        self.algorithm = .rsa
        self.keySize = 4096
        self.creationDate = Date()

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
