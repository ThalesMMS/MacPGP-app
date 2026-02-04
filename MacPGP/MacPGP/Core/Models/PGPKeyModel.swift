import Foundation
import ObjectivePGP

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
    let rawKey: Key

    init(from key: Key) {
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
