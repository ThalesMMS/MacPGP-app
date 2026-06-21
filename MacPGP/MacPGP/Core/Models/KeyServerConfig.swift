import Foundation

nonisolated enum KeyServerProtocol: String, Codable {
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

nonisolated struct KeyServerConfig: Identifiable, Codable, Hashable {
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

    /// The URL used for actual network loading. The logical `hkp`/`hkps` schemes
    /// are mapped to the `http`/`https` transport `URLSession` understands, while
    /// the configured host and port are preserved. The insecure-transport policy
    /// is enforced separately at the service boundary (see
    /// `KeyServerService.ensureTransportAllowed`); this mapping does not relax it.
    var transportURL: URL? {
        var components = URLComponents()
        components.scheme = isSecure ? "https" : "http"
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

    /// True when this server uses a plaintext transport (HKP/HTTP) that requires
    /// an explicit, informed opt-in before MacPGP will contact it.
    var requiresInsecureOptIn: Bool {
        !isSecure
    }

    /// Returns a copy of this configuration with `allowInsecure` overridden. Used
    /// to carry the user's persisted insecure-transport opt-in into the effective
    /// configuration handed to `KeyServerService`.
    func withAllowInsecure(_ allow: Bool) -> KeyServerConfig {
        KeyServerConfig(
            id: id,
            name: name,
            hostname: hostname,
            port: port,
            protocol: `protocol`,
            isEnabled: isEnabled,
            timeout: timeout,
            allowInsecure: allow
        )
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

    @MainActor
    static var enabledServers: [KeyServerConfig] {
        enabledServers(using: PreferencesManager.shared)
    }

    /// Returns the enabled key servers from preferences, applying insecure transport opt-in settings.
    ///
    /// Insecure servers are only returned if the user has explicitly allowed insecure connections for that server's hostname.
    ///
    /// - Returns: An array of `KeyServerConfig` instances.
    @MainActor
    static func enabledServers(using preferences: PreferencesManager) -> [KeyServerConfig] {
        let enabledHostnames = Set(preferences.enabledKeyServers)
        let servers = defaults.filter { enabledHostnames.contains($0.hostname) }
        let resolved = servers.isEmpty ? defaults.filter(\.isEnabled) : servers
        // Carry the user's explicit insecure-transport opt-in into the effective
        // configuration so the service boundary can enforce it. Secure servers are
        // returned unchanged; insecure servers are only marked usable when opted in.
        return resolved.map { server in
            server.isSecure
                ? server
                : server.withAllowInsecure(preferences.isInsecureKeyServerAllowed(server.hostname))
        }
    }

    /// Retrieves the default key server configuration.
    ///
    /// Prioritizes the user-configured default server if enabled, falls back to the first secure
    /// server from the enabled list, or `keysOpenpgp` if no secure server is available.
    /// - Parameter preferences: The preferences manager to use. If `nil`, uses the shared instance.
    /// - Returns: The selected `KeyServerConfig`.
    @MainActor
    static func defaultServer(using preferences: PreferencesManager? = nil) -> KeyServerConfig {
        let preferences = preferences ?? .shared
        let enabledServers = enabledServers(using: preferences)
        if let chosen = enabledServers.first(where: { $0.hostname == preferences.defaultKeyServer }) {
            return chosen
        }
        // Never silently fall back to an insecure server: prefer a secure one.
        return enabledServers.first(where: { $0.isSecure }) ?? .keysOpenpgp
    }

    static var preview: KeyServerConfig {
        .keysOpenpgp
    }
}
