import Foundation

public enum ObjectivePGP {
    public static func readKeys(from data: Data) throws -> [Key] {
        try RNP.readKeys(from: data)
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
        try RNP.encrypt(
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
            let inspection = try RNP.inspect(
                data,
                signature: nil,
                using: keys,
                passphraseForKey: passphraseForKey
            )
            guard let outputData = inspection.outputData else {
                throw ObjectivePGPError.missingDecryptedOutput
            }
            return outputData
        }

        return try RNP.decrypt(
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
        try RNP.sign(
            data,
            detached: detached,
            using: keys,
            passphraseForKey: passphraseForKey
        )
    }

    public static func verify(
        _ data: Data,
        withSignature signature: Data? = nil,
        using keys: [Key]
    ) throws {
        try RNP.verify(data, signature: signature, using: keys)
    }

    public static func inspect(
        _ data: Data,
        withSignature signature: Data? = nil,
        using keys: [Key] = [],
        passphraseForKey: ((Key) -> String?)? = nil
    ) throws -> MessageInspection {
        try RNP.inspect(
            data,
            signature: signature,
            using: keys,
            passphraseForKey: passphraseForKey
        )
    }
}
