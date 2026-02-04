import Foundation

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    var isPGPArmored: Bool {
        guard let string = String(data: self, encoding: .utf8) else {
            return false
        }
        return string.contains("-----BEGIN PGP")
    }

    var pgpArmorType: PGPArmorBlockType? {
        guard let string = String(data: self, encoding: .utf8) else {
            return nil
        }

        if string.contains("-----BEGIN PGP PUBLIC KEY BLOCK-----") {
            return .publicKey
        } else if string.contains("-----BEGIN PGP PRIVATE KEY BLOCK-----") ||
                  string.contains("-----BEGIN PGP SECRET KEY BLOCK-----") {
            return .secretKey
        } else if string.contains("-----BEGIN PGP MESSAGE-----") {
            return .message
        } else if string.contains("-----BEGIN PGP SIGNATURE-----") {
            return .signature
        } else if string.contains("-----BEGIN PGP SIGNED MESSAGE-----") {
            return .signedMessage
        }

        return nil
    }
}

enum PGPArmorBlockType {
    case publicKey
    case secretKey
    case message
    case signature
    case signedMessage
}
