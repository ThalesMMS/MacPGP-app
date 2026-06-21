import Foundation

nonisolated enum PGPFileExtensions {
    static let asciiArmored = "asc"
    static let binaryMessage = "gpg"
    static let pgp = "pgp"
    static let binarySignature = "sig"
    static let decryptedFallback = "decrypted"

    static let all: Set<String> = [
        asciiArmored,
        binaryMessage,
        pgp
    ]

    static func isPGPFileExtension(_ pathExtension: String) -> Bool {
        all.contains(pathExtension.lowercased())
    }

    static func encryptedOutputExtension(armored: Bool) -> String {
        armored ? asciiArmored : binaryMessage
    }

    static func signedOutputExtension(detached: Bool, armored: Bool) -> String {
        if armored {
            return asciiArmored
        }
        return detached ? binarySignature : binaryMessage
    }

    static func defaultDecryptedOutputURL(for file: URL) -> URL {
        if isPGPFileExtension(file.pathExtension) {
            return file.deletingPathExtension()
        }

        return file.appendingPathExtension(decryptedFallback)
    }
}
