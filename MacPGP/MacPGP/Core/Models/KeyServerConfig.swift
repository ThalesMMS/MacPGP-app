import Foundation

enum KeyServerProtocol: String, Codable {
    case hkp = "hkp"
    case hkps = "hkps"
    case http = "http"
    case https = "https"

    var displayName: String {
        switch self {
        case .hkp:
            return "HKP (HTTP)"
        case .hkps:
            return "HKPS (HTTPS)"
        case .http:
            return "HTTP"
        case .https:
            return "HTTPS"
        }
    }

    var defaultPort: Int {
        switch self {
        case .hkp, .http:
            return 11371
        case .hkps, .https:
            return 443
        }
    }
}

struct KeyServerConfig: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let hostname: String
    let port: Int
    let `protocol`: KeyServerProtocol
    let isEnabled: Bool
    let timeout: TimeInterval
    let allowInsecure: Bool

    init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: Int? = nil,
        protocol: KeyServerProtocol = .hkps,
        isEnabled: Bool = true,
        timeout: TimeInterval = 30,
        allowInsecure: Bool = false
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port ?? `protocol`.defaultPort
        self.protocol = `protocol`
        self.isEnabled = isEnabled
        self.timeout = timeout
        self.allowInsecure = allowInsecure
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = `protocol`.rawValue
        components.host = hostname
        components.port = port
        return components.url
    }

    var displayURL: String {
        "\(`protocol`.rawValue)://\(hostname):\(port)"
    }

    var isSecure: Bool {
        `protocol` == .hkps || `protocol` == .https
    }

    var statusDescription: String {
        if isEnabled {
            return isSecure ? "Enabled (Secure)" : "Enabled (Insecure)"
        } else {
            return "Disabled"
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: KeyServerConfig, rhs: KeyServerConfig) -> Bool {
        lhs.id == rhs.id
    }
}

extension KeyServerConfig {
    static let keysOpenpgp = KeyServerConfig(
        name: "keys.openpgp.org",
        hostname: "keys.openpgp.org",
        protocol: .hkps
    )

    static let ubuntuKeyserver = KeyServerConfig(
        name: "Ubuntu Keyserver",
        hostname: "keyserver.ubuntu.com",
        protocol: .hkps
    )

    static let mitKeyserver = KeyServerConfig(
        name: "MIT PGP Keyserver",
        hostname: "pgp.mit.edu",
        port: 11371,
        protocol: .hkp,
        isEnabled: false
    )

    static let defaults: [KeyServerConfig] = [
        .keysOpenpgp,
        .ubuntuKeyserver,
        .mitKeyserver
    ]

    static var preview: KeyServerConfig {
        .keysOpenpgp
    }
}
