import Foundation
import RNPKit

// MARK: - PGPKeyModel

struct PGPKeyModel: Identifiable, Hashable, PGPKeyCapabilityProviding {
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
    let canEncrypt: Bool
    let canSign: Bool
    let rawKey: Key

    init(from key: Key) {
        let derivedAlgorithm = KeyAlgorithm.from(publicKeyAlgorithm: key.metadata.primaryAlgorithm)

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
        self.canEncrypt = key.metadata.capabilities.canEncrypt
        self.canSign = key.metadata.capabilities.canSign

        self.userIDs = key.metadata.userIDs.compactMap { userID -> KeyIdentity? in
            guard !userID.isEmpty else { return nil }
            return KeyIdentity.parse(from: userID)
        }
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

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PGPKeyModel, rhs: PGPKeyModel) -> Bool {
        lhs.id == rhs.id
    }

}
