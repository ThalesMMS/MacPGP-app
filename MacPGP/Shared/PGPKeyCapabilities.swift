nonisolated protocol PGPKeyCapabilityProviding {
    var isSecretKey: Bool { get }
    var isExpired: Bool { get }
    var isRevoked: Bool { get }
    var canEncrypt: Bool { get }
    var canSign: Bool { get }
}

nonisolated extension PGPKeyCapabilityProviding {
    var isUsableForEncryption: Bool {
        !isExpired && !isRevoked && canEncrypt
    }

    var isUsableForSigning: Bool {
        isSecretKey && !isExpired && !isRevoked && canSign
    }
}
