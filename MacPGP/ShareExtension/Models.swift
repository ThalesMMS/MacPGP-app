import Foundation
import ObjectivePGP

// MARK: - KeyAlgorithm

enum KeyAlgorithm: String, Codable {
    case rsa = "RSA"
    case dsa = "DSA"
    case ecdsa = "ECDSA"
    case eddsa = "EdDSA"
    case elgamal = "ElGamal"
    case unknown = "Unknown"

    var displayName: String {
        rawValue
    }

    var defaultKeySize: Int {
        switch self {
        case .rsa: return 4096
        case .ecdsa: return 256
        case .eddsa: return 256
        case .dsa: return 2048
        case .elgamal: return 3072
        case .unknown: return 0
        }
    }
}

// MARK: - KeyIdentity

struct KeyIdentity: Codable, Hashable {
    let name: String
    let email: String?
    let comment: String?

    init(name: String, email: String? = nil, comment: String? = nil) {
        self.name = name
        self.email = email
        self.comment = comment
    }

    static func parse(from userID: String) -> KeyIdentity {
        // Parse "Name (Comment) <email@example.com>" format
        var name = ""
        var email: String? = nil
        var comment: String? = nil

        // Extract email
        if let emailStart = userID.firstIndex(of: "<"),
           let emailEnd = userID.firstIndex(of: ">") {
            email = String(userID[userID.index(after: emailStart)..<emailEnd])
        }

        // Extract comment
        if let commentStart = userID.firstIndex(of: "("),
           let commentEnd = userID.firstIndex(of: ")") {
            comment = String(userID[userID.index(after: commentStart)..<commentEnd])
        }

        // Extract name (everything before comment or email)
        let endIndex = userID.firstIndex(of: "(") ?? userID.firstIndex(of: "<") ?? userID.endIndex
        name = String(userID[..<endIndex]).trimmingCharacters(in: .whitespaces)

        return KeyIdentity(name: name.isEmpty ? "Unknown" : name, email: email, comment: comment)
    }

    var shortDisplayString: String {
        if let email = email, !name.isEmpty {
            return "\(name) <\(email)>"
        } else if !name.isEmpty {
            return name
        } else if let email = email {
            return email
        } else {
            return "Unknown"
        }
    }
}

// MARK: - PGPKeyModel

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
    let canEncrypt: Bool
    let canSign: Bool
    let rawKey: Key

    init(from key: Key) {
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
        stride(from: 0, to: fingerprint.count, by: 4).map { i -> String in
            let start = fingerprint.index(fingerprint.startIndex, offsetBy: i)
            let end = fingerprint.index(start, offsetBy: min(4, fingerprint.count - i))
            return String(fingerprint[start..<end])
        }.joined(separator: " ")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PGPKeyModel, rhs: PGPKeyModel) -> Bool {
        lhs.id == rhs.id
    }

    // Keep these packet metadata helpers in sync with the canonical implementation
    // in MacPGP/Core/Models/PGPKeyModel.swift. The Share extension defines its own
    // model copy and cannot import the app target directly, so this duplication
    // is intentional.
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
