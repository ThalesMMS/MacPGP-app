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
    let rawKey: Key

    init(from key: Key) {
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
        self.isRevoked = false

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
