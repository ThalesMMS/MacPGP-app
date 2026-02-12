import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case keyring
    case webOfTrust
    case encrypt
    case decrypt
    case sign
    case verify

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keyring: return String(localized: "sidebar.keyring", defaultValue: "Keyring", comment: "Sidebar navigation item for keyring")
        case .webOfTrust: return String(localized: "sidebar.web_of_trust", defaultValue: "Web of Trust", comment: "Sidebar navigation item for web of trust")
        case .encrypt: return String(localized: "sidebar.encrypt", defaultValue: "Encrypt", comment: "Sidebar navigation item for encryption")
        case .decrypt: return String(localized: "sidebar.decrypt", defaultValue: "Decrypt", comment: "Sidebar navigation item for decryption")
        case .sign: return String(localized: "sidebar.sign", defaultValue: "Sign", comment: "Sidebar navigation item for signing")
        case .verify: return String(localized: "sidebar.verify", defaultValue: "Verify", comment: "Sidebar navigation item for verification")
        }
    }

    var iconName: String {
        switch self {
        case .keyring: return "key.fill"
        case .webOfTrust: return "network"
        case .encrypt: return "lock.fill"
        case .decrypt: return "lock.open.fill"
        case .sign: return "signature"
        case .verify: return "checkmark.seal.fill"
        }
    }

    var description: String {
        switch self {
        case .keyring: return String(localized: "sidebar.keyring.description", defaultValue: "Manage your PGP keys", comment: "Description for keyring sidebar item")
        case .webOfTrust: return String(localized: "sidebar.web_of_trust.description", defaultValue: "Visualize trust relationships", comment: "Description for web of trust sidebar item")
        case .encrypt: return String(localized: "sidebar.encrypt.description", defaultValue: "Encrypt messages or files", comment: "Description for encrypt sidebar item")
        case .decrypt: return String(localized: "sidebar.decrypt.description", defaultValue: "Decrypt messages or files", comment: "Description for decrypt sidebar item")
        case .sign: return String(localized: "sidebar.sign.description", defaultValue: "Sign messages or files", comment: "Description for sign sidebar item")
        case .verify: return String(localized: "sidebar.verify.description", defaultValue: "Verify signatures", comment: "Description for verify sidebar item")
        }
    }
}
