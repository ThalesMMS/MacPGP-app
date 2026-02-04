import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case keyring = "Keyring"
    case encrypt = "Encrypt"
    case decrypt = "Decrypt"
    case sign = "Sign"
    case verify = "Verify"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .keyring: return "key.fill"
        case .encrypt: return "lock.fill"
        case .decrypt: return "lock.open.fill"
        case .sign: return "signature"
        case .verify: return "checkmark.seal.fill"
        }
    }

    var description: String {
        switch self {
        case .keyring: return "Manage your PGP keys"
        case .encrypt: return "Encrypt messages or files"
        case .decrypt: return "Decrypt messages or files"
        case .sign: return "Sign messages or files"
        case .verify: return "Verify signatures"
        }
    }
}
