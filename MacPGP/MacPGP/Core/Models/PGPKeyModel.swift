import Foundation
import RNPKit

nonisolated enum ExpirationWarningLevel {
    case none
    case warning    // 30 days or less
    case critical   // 7 days or less
    case expired
}

nonisolated enum FingerprintVerificationMethod: String, Codable {
    case inPerson = "in_person"
    case phone = "phone"
    case qrCode = "qr_code"
    case trusted = "trusted"
}

nonisolated struct PGPKeyModel: Identifiable, Hashable, PGPKeyCapabilityProviding {
    let id: String
    let fingerprint: String
    let shortKeyID: String
    let algorithm: KeyAlgorithm
    let keySize: Int
    let creationDate: Date
    let expirationDate: Date?
    let userIDs: [KeyIdentity]
    let isSecretKey: Bool
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
        expirationDate: Date? = nil,
        isRevoked: Bool? = nil,
        revokedDate: Date? = nil,
        trustLevel: TrustLevel? = nil
    ) {
        let revoked = isRevoked ?? key.isRevoked

        self.id = key.id
        self.fingerprint = key.fingerprint
        self.shortKeyID = key.shortKeyID
        self.algorithm = key.algorithm
        self.keySize = key.keySize
        self.creationDate = key.creationDate
        self.expirationDate = expirationDate ?? key.expirationDate
        self.userIDs = key.userIDs
        self.isSecretKey = key.isSecretKey
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
        let derivedAlgorithm = KeyAlgorithm.from(publicKeyAlgorithm: key.metadata.primaryAlgorithm)

        self.rawKey = key
        self.fingerprint = key.metadata.fingerprint
        self.id = fingerprint
        self.shortKeyID = key.metadata.shortKeyID

        self.algorithm = derivedAlgorithm
        self.keySize = key.metadata.primaryKeySize
        self.creationDate = key.metadata.creationDate
        self.expirationDate = key.metadata.expirationDate

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
        fingerprint.formattedAsFingerprint()
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

    // MARK: - Time-dependent validity
    //
    // Expiration is derived from `expirationDate` at evaluation time rather than
    // cached, so a key that crosses its expiration boundary while the app is open
    // (or after a system clock change) is reported correctly without relaunching.
    // Boundary semantics are inclusive: a key is expired once the current instant
    // reaches or passes `expirationDate` (`expirationDate <= now`). Keys without an
    // expiration date never expire. Revocation is tracked separately and is
    // independent of the clock.

    /// Whether the key is expired as of `now` (inclusive boundary).
    func isExpired(asOf now: Date) -> Bool {
        guard let expirationDate else { return false }
        return expirationDate <= now
    }

    /// Convenience evaluation against the current system time. Service and
    /// operation code should prefer ``isExpired(asOf:)`` with an injected clock.
    var isExpired: Bool { isExpired(asOf: Date()) }

    /// Whether the key is usable as an encryption recipient as of `now`.
    func isUsableForEncryption(asOf now: Date) -> Bool {
        !isExpired(asOf: now) && !isRevoked && canEncrypt
    }

    /// Whether the key is usable for signing as of `now`.
    func isUsableForSigning(asOf now: Date) -> Bool {
        isSecretKey && !isExpired(asOf: now) && !isRevoked && canSign
    }

    func daysUntilExpiration(asOf now: Date) -> Int? {
        guard let expDate = expirationDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let expirationDay = calendar.startOfDay(for: expDate)
        let components = calendar.dateComponents([.day], from: today, to: expirationDay)
        return components.day
    }

    var daysUntilExpiration: Int? { daysUntilExpiration(asOf: Date()) }

    func isExpiringSoon(asOf now: Date) -> Bool {
        guard let expirationDate, expirationDate > now else { return false }
        guard let days = daysUntilExpiration(asOf: now) else { return false }
        return days <= 30 && days >= 0
    }

    var isExpiringSoon: Bool { isExpiringSoon(asOf: Date()) }

    func expirationWarningLevel(asOf now: Date) -> ExpirationWarningLevel {
        if isExpired(asOf: now) {
            return .expired
        }

        guard let days = daysUntilExpiration(asOf: now) else {
            return .none
        }

        if days <= 7 {
            return .critical
        } else if days <= 30 {
            return .warning
        } else {
            return .none
        }
    }

    var expirationWarningLevel: ExpirationWarningLevel { expirationWarningLevel(asOf: Date()) }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PGPKeyModel, rhs: PGPKeyModel) -> Bool {
        lhs.id == rhs.id
    }

}

#if DEBUG
extension PGPKeyModel {
    /// SwiftUI preview fixture. DEBUG-only and never on a release-visible path;
    /// `try!` here surfaces a misconfigured preview environment immediately
    /// rather than masking it.
    static var preview: PGPKeyModel {
        let keyGenerator = KeyGenerator()
        let key = try! keyGenerator.generate(
            for: "preview@example.com",
            passphrase: "preview"
        )
        return PGPKeyModel(from: key)
    }
}
#endif
