import Foundation

enum PGPArmorBlock: CaseIterable {
    case message
    case signature
    case signedMessage
    case publicKey
    case privateKey

    fileprivate var header: String {
        switch self {
        case .message:
            return "-----BEGIN PGP MESSAGE-----"
        case .signature:
            return "-----BEGIN PGP SIGNATURE-----"
        case .signedMessage:
            return "-----BEGIN PGP SIGNED MESSAGE-----"
        case .publicKey:
            return "-----BEGIN PGP PUBLIC KEY BLOCK-----"
        case .privateKey:
            return "-----BEGIN PGP PRIVATE KEY BLOCK-----"
        }
    }
}

enum PGPArmorDetector {
    /// Armor must begin the payload after leading whitespace; embedded prose does not count as PGP armor.
    static func detectedBlock(in text: String) -> PGPArmorBlock? {
        detectedBlock(inNormalizedText: normalizedText(from: text))
    }

    static func normalizedArmoredText(from text: String) -> String? {
        let normalizedText = normalizedText(from: text)
        guard detectedBlock(inNormalizedText: normalizedText) != nil else {
            return nil
        }
        return normalizedText
    }

    private static func detectedBlock(inNormalizedText text: String) -> PGPArmorBlock? {
        PGPArmorBlock.allCases.first { text.hasPrefix($0.header) }
    }

    private static func normalizedText(from text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
