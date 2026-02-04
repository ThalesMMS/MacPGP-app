import Foundation

enum KeyAlgorithm: String, CaseIterable, Identifiable {
    case rsa = "RSA"
    case ecdsa = "ECDSA"
    case eddsa = "EdDSA"
    case dsa = "DSA"
    case elgamal = "ElGamal"
    case unknown = "Unknown"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rsa: return "RSA"
        case .ecdsa: return "ECDSA (Elliptic Curve)"
        case .eddsa: return "EdDSA (Ed25519)"
        case .dsa: return "DSA"
        case .elgamal: return "ElGamal"
        case .unknown: return "Unknown"
        }
    }

    var supportedKeySizes: [Int] {
        switch self {
        case .rsa: return [2048, 3072, 4096]
        case .ecdsa: return [256, 384, 521]
        case .eddsa: return [256]
        case .dsa: return [1024, 2048, 3072]
        case .elgamal: return [2048, 3072, 4096]
        case .unknown: return []
        }
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

    var supportsEncryption: Bool {
        switch self {
        case .rsa, .elgamal: return true
        case .ecdsa, .eddsa, .dsa: return false
        case .unknown: return false
        }
    }

    var supportsSigning: Bool {
        switch self {
        case .rsa, .ecdsa, .eddsa, .dsa: return true
        case .elgamal: return false
        case .unknown: return false
        }
    }
}
