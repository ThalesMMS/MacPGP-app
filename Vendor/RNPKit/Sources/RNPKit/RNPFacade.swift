import Foundation

public enum RNP {
    public static func readKeys(from data: Data) throws -> [Key] {
        try RNPBackend.readKeys(from: data)
    }

    public static func readKeys(fromPath path: String) throws -> [Key] {
        try readKeys(from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    public static func encrypt(
        _ data: Data,
        addSignature: Bool,
        using keys: [Key],
        passphraseForKey: ((Key) -> String?)? = nil
    ) throws -> Data {
        try RNPBackend.encrypt(
            data,
            addSignature: addSignature,
            using: keys,
            passphraseForKey: passphraseForKey
        )
    }

    public static func decrypt(
        _ data: Data,
        andVerifySignature: Bool,
        using keys: [Key],
        passphraseForKey: ((Key) -> String?)? = nil
    ) throws -> Data {
        if andVerifySignature {
            let inspection = try RNPBackend.inspect(
                data,
                signature: nil,
                using: keys,
                passphraseForKey: passphraseForKey
            )
            guard let outputData = inspection.outputData else {
                throw RNPError.missingDecryptedOutput
            }
            return outputData
        }

        return try RNPBackend.decrypt(
            data,
            using: keys,
            passphraseForKey: passphraseForKey
        )
    }

    public static func sign(
        _ data: Data,
        detached: Bool,
        using keys: [Key],
        passphraseForKey: ((Key) -> String?)? = nil
    ) throws -> Data {
        try RNPBackend.sign(
            data,
            detached: detached,
            using: keys,
            passphraseForKey: passphraseForKey
        )
    }

    /// Produces a cleartext-signed message using librnp's native cleartext
    /// operation (canonical dash-escaping and line-ending normalization). The
    /// returned data is the armored cleartext framework.
    public static func signCleartext(
        _ data: Data,
        using keys: [Key],
        passphraseForKey: ((Key) -> String?)? = nil
    ) throws -> Data {
        try RNPBackend.signCleartext(
            data,
            using: keys,
            passphraseForKey: passphraseForKey
        )
    }

    public static func verify(
        _ data: Data,
        withSignature signature: Data? = nil,
        using keys: [Key]
    ) throws {
        try RNPBackend.verify(data, signature: signature, using: keys)
    }

    // MARK: - Streaming file operations
    //
    // These stream directly between file paths via librnp, so the full plaintext
    // and ciphertext are never materialized in memory at once. Use them for file
    // mode; keep the Data APIs above for text and small in-memory callers.

    public static func encryptFile(
        inputPath: String,
        outputPath: String,
        armored: Bool,
        addSignature: Bool,
        using keys: [Key],
        passphraseForKey: ((Key) -> String?)? = nil
    ) throws {
        try RNPBackend.encryptFile(
            inputPath: inputPath,
            outputPath: outputPath,
            armored: armored,
            addSignature: addSignature,
            using: keys,
            passphraseForKey: passphraseForKey
        )
    }

    public static func decryptFile(
        inputPath: String,
        outputPath: String,
        using keys: [Key],
        passphraseForKey: ((Key) -> String?)? = nil
    ) throws {
        try RNPBackend.decryptFile(
            inputPath: inputPath,
            outputPath: outputPath,
            using: keys,
            passphraseForKey: passphraseForKey
        )
    }

    public static func signFile(
        inputPath: String,
        outputPath: String,
        detached: Bool,
        armored: Bool,
        using keys: [Key],
        passphraseForKey: ((Key) -> String?)? = nil
    ) throws {
        try RNPBackend.signFile(
            inputPath: inputPath,
            outputPath: outputPath,
            detached: detached,
            armored: armored,
            using: keys,
            passphraseForKey: passphraseForKey
        )
    }

    /// Streams auto-detect decryption from `inputPath` to `outputPath`, trying all
    /// supplied secret keys, and returns the *primary-key fingerprint* of the key
    /// librnp used (nil when the recipient cannot be attributed — the decryption
    /// still succeeded). Neither the ciphertext nor the plaintext is fully
    /// buffered in memory.
    public static func decryptFileTryingKeys(
        inputPath: String,
        outputPath: String,
        using keys: [Key],
        passphraseForKey: ((Key) -> String?)? = nil
    ) throws -> String? {
        try RNPBackend.decryptFileTryingKeys(
            inputPath: inputPath,
            outputPath: outputPath,
            using: keys,
            passphraseForKey: passphraseForKey
        )
    }

    /// Path-based signature verification. The signed content streams from
    /// `inputPath`; inline-signed content is recovered to a null sink (never
    /// buffered) and detached signatures come from `signaturePath`. Returns the
    /// per-signature verdicts.
    public static func verifyFile(
        inputPath: String,
        signaturePath: String? = nil,
        using keys: [Key]
    ) throws -> [VerifiedSignature] {
        try RNPBackend.verifyFile(
            inputPath: inputPath,
            signaturePath: signaturePath,
            using: keys
        )
    }

    public static func inspect(
        _ data: Data,
        withSignature signature: Data? = nil,
        using keys: [Key] = [],
        passphraseForKey: ((Key) -> String?)? = nil
    ) throws -> MessageInspection {
        try RNPBackend.inspect(
            data,
            signature: signature,
            using: keys,
            passphraseForKey: passphraseForKey
        )
    }
}
