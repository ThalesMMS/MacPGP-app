import Foundation
import CryptoKit
import CommonCrypto

/// Errors produced while sealing or opening an encrypted backup envelope.
///
/// Every failure maps to a specific, recoverable case. Wrong passphrase, tampered
/// header/salt, truncated body, and a modified authentication tag are all reported
/// as typed errors and never trap.
nonisolated enum BackupEnvelopeError: LocalizedError, Equatable {
    case passphraseRequired
    case malformed
    case truncated
    case unsupportedVersion(Int)
    case unsupportedKDF(String)
    case unsupportedCipher(String)
    case kdfParametersOutOfBounds
    /// AES-GCM authentication failed: wrong passphrase, or the header/ciphertext/tag was modified.
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .passphraseRequired:
            return NSLocalizedString("error.backup_envelope.passphrase_required", comment: "Encrypted backup requires a passphrase")
        case .malformed:
            return NSLocalizedString("error.backup_envelope.malformed", comment: "Encrypted backup header is malformed")
        case .truncated:
            return NSLocalizedString("error.backup_envelope.truncated", comment: "Encrypted backup file is incomplete or truncated")
        case .unsupportedVersion(let version):
            return String(format: NSLocalizedString("error.backup_envelope.unsupported_version", comment: "Encrypted backup uses an unsupported envelope version"), version)
        case .unsupportedKDF(let kdf):
            return String(format: NSLocalizedString("error.backup_envelope.unsupported_kdf", comment: "Encrypted backup uses an unsupported key-derivation function"), kdf)
        case .unsupportedCipher(let cipher):
            return String(format: NSLocalizedString("error.backup_envelope.unsupported_cipher", comment: "Encrypted backup uses an unsupported cipher"), cipher)
        case .kdfParametersOutOfBounds:
            return NSLocalizedString("error.backup_envelope.kdf_parameters_out_of_bounds", comment: "Encrypted backup declares key-derivation parameters outside the allowed range")
        case .authenticationFailed:
            return NSLocalizedString("error.backup_envelope.authentication_failed", comment: "Encrypted backup could not be authenticated: wrong passphrase or the file was modified")
        }
    }
}

/// Serialized key-derivation parameters carried in a V2 envelope header.
nonisolated struct BackupKDFParameters: Codable, Equatable {
    let iterations: Int
    let keyLength: Int
}

/// The self-describing, authenticated header of a V2 encrypted backup envelope.
///
/// The whole header is serialized into the envelope and authenticated as AES-GCM
/// associated data, so tampering with the version, KDF, parameters, salt, or
/// cipher fails authentication instead of silently downgrading security.
nonisolated struct BackupEnvelopeHeader: Codable, Equatable {
    let version: Int
    let kdf: String
    let kdfParams: BackupKDFParameters
    let salt: Data
    let cipher: String
    let createdAt: Date?
}

/// Versioned encrypted-backup envelope.
///
/// - V2 (current): `MACPGP-ENC-V2\n` magic, a big-endian `UInt32` header length, a
///   JSON header (`BackupEnvelopeHeader`) that is authenticated as AES-GCM
///   associated data, then the AES-256-GCM sealed box (`nonce || ciphertext || tag`).
///   KDF is PBKDF2-HMAC-SHA256 with a serialized, bounds-checked iteration count.
/// - V1 (legacy, read-only): `MACPGP-ENC-V1\n` magic, a 16-byte salt, then an
///   AES-256-GCM sealed box with PBKDF2-HMAC-SHA256 at a fixed 100k iterations and
///   no associated data. Retained so existing backups still restore.
///
/// See `docs/BACKUP_FORMAT.md` for the format specification, migration policy, and
/// security rationale.
nonisolated enum EncryptedBackupEnvelope {
    // MARK: - Constants

    static let v1Magic = Data("MACPGP-ENC-V1\n".utf8)
    static let v2Magic = Data("MACPGP-ENC-V2\n".utf8)

    static let kdfPBKDF2HMACSHA256 = "PBKDF2-HMAC-SHA256"
    static let cipherAES256GCM = "AES-256-GCM"

    /// Calibrated PBKDF2-HMAC-SHA256 work factor for new (V2) backups. 600k matches
    /// the OWASP 2023 recommendation for PBKDF2-HMAC-SHA256 and is comfortably fast
    /// on supported Apple Silicon Macs. See `docs/BACKUP_FORMAT.md`.
    static let defaultIterations = 600_000
    static let keyLength = 32
    static let v2SaltLength = 16

    /// Bounds on attacker-controlled KDF parameters, enforced before any expensive
    /// derivation or large allocation.
    static let minIterations = 100_000
    static let maxIterations = 10_000_000
    static let minSaltLength = 8
    static let maxSaltLength = 64
    static let maxHeaderLength = 64 * 1024

    private static let v1Iterations = 100_000
    private static let v1SaltLength = 16
    private static let gcmNonceLength = 12
    private static let gcmTagLength = 16

    // MARK: - Detection

    static func isEncryptedBackup(_ data: Data) -> Bool {
        detectedVersion(data) != nil
    }

    static func detectedVersion(_ data: Data) -> Int? {
        if data.starts(with: v2Magic) { return 2 }
        if data.starts(with: v1Magic) { return 1 }
        return nil
    }

    // MARK: - Seal (V2)

    /// Seals `plaintext` into a current V2 envelope with a random salt and nonce.
    static func seal(_ plaintext: Data, passphrase: String, createdAt: Date? = nil) throws -> Data {
        let salt = Data((0..<v2SaltLength).map { _ in UInt8.random(in: 0...255) })
        return try sealV2(
            plaintext,
            passphrase: passphrase,
            salt: salt,
            nonce: AES.GCM.Nonce(),
            iterations: defaultIterations,
            createdAt: createdAt
        )
    }

    /// Deterministic V2 seal with explicit salt/nonce/iterations. Used by `seal` and
    /// by tests/fixtures.
    static func sealV2(
        _ plaintext: Data,
        passphrase: String,
        salt: Data,
        nonce: AES.GCM.Nonce,
        iterations: Int,
        createdAt: Date?
    ) throws -> Data {
        guard !passphrase.isEmpty else { throw BackupEnvelopeError.passphraseRequired }
        try validateKDFParameters(iterations: iterations, keyLength: keyLength, saltLength: salt.count)

        let header = BackupEnvelopeHeader(
            version: 2,
            kdf: kdfPBKDF2HMACSHA256,
            kdfParams: BackupKDFParameters(iterations: iterations, keyLength: keyLength),
            salt: salt,
            cipher: cipherAES256GCM,
            createdAt: createdAt
        )
        let headerData = try encodeHeader(header)
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations, keyLength: keyLength)
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: headerData)
        guard let combined = sealedBox.combined else { throw BackupEnvelopeError.malformed }

        var output = Data()
        output.append(v2Magic)
        output.append(bigEndianLength(headerData.count))
        output.append(headerData)
        output.append(combined)
        return output
    }

    /// Legacy V1 seal (no associated data, fixed 100k iterations). Retained only so
    /// V1 read-compatibility can be exercised with deterministic fixtures.
    static func sealV1(_ plaintext: Data, passphrase: String, salt: Data, nonce: AES.GCM.Nonce) throws -> Data {
        guard !passphrase.isEmpty else { throw BackupEnvelopeError.passphraseRequired }
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: v1Iterations, keyLength: keyLength)
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        guard let combined = sealedBox.combined else { throw BackupEnvelopeError.malformed }

        var output = Data()
        output.append(v1Magic)
        output.append(salt)
        output.append(combined)
        return output
    }

    // MARK: - Open (V1 + V2)

    static func open(_ data: Data, passphrase: String) throws -> Data {
        guard !passphrase.isEmpty else { throw BackupEnvelopeError.passphraseRequired }
        switch detectedVersion(data) {
        case 2: return try openV2(data, passphrase: passphrase)
        case 1: return try openV1(data, passphrase: passphrase)
        default: throw BackupEnvelopeError.malformed
        }
    }

    private static func openV2(_ data: Data, passphrase: String) throws -> Data {
        let bytes = Data(data) // normalize indices to 0-based
        let magicEnd = v2Magic.count
        guard bytes.count >= magicEnd + 4 else { throw BackupEnvelopeError.truncated }

        let headerLength = Int(bytes[magicEnd]) << 24
            | Int(bytes[magicEnd + 1]) << 16
            | Int(bytes[magicEnd + 2]) << 8
            | Int(bytes[magicEnd + 3])
        guard headerLength > 0, headerLength <= maxHeaderLength else { throw BackupEnvelopeError.malformed }

        let headerStart = magicEnd + 4
        let headerEnd = headerStart + headerLength
        guard bytes.count >= headerEnd + gcmNonceLength + gcmTagLength else { throw BackupEnvelopeError.truncated }

        let headerData = bytes.subdata(in: headerStart..<headerEnd)
        let combined = bytes.subdata(in: headerEnd..<bytes.count)

        let header = try decodeHeader(headerData)
        guard header.version == 2 else { throw BackupEnvelopeError.unsupportedVersion(header.version) }
        guard header.kdf == kdfPBKDF2HMACSHA256 else { throw BackupEnvelopeError.unsupportedKDF(header.kdf) }
        guard header.cipher == cipherAES256GCM else { throw BackupEnvelopeError.unsupportedCipher(header.cipher) }
        try validateKDFParameters(
            iterations: header.kdfParams.iterations,
            keyLength: header.kdfParams.keyLength,
            saltLength: header.salt.count
        )

        let key = try deriveKey(
            passphrase: passphrase,
            salt: header.salt,
            iterations: header.kdfParams.iterations,
            keyLength: header.kdfParams.keyLength
        )

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: combined)
        } catch {
            throw BackupEnvelopeError.malformed
        }
        do {
            return try AES.GCM.open(sealedBox, using: key, authenticating: headerData)
        } catch {
            throw BackupEnvelopeError.authenticationFailed
        }
    }

    private static func openV1(_ data: Data, passphrase: String) throws -> Data {
        let bytes = Data(data)
        let headerLength = v1Magic.count
        let minimumTotal = headerLength + v1SaltLength + gcmNonceLength + gcmTagLength
        guard bytes.count >= minimumTotal else { throw BackupEnvelopeError.truncated }

        let salt = bytes.subdata(in: headerLength..<(headerLength + v1SaltLength))
        let combined = bytes.subdata(in: (headerLength + v1SaltLength)..<bytes.count)

        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: v1Iterations, keyLength: keyLength)

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: combined)
        } catch {
            throw BackupEnvelopeError.malformed
        }
        do {
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw BackupEnvelopeError.authenticationFailed
        }
    }

    // MARK: - Parameter validation

    static func validateKDFParameters(iterations: Int, keyLength: Int, saltLength: Int) throws {
        guard iterations >= minIterations, iterations <= maxIterations else {
            throw BackupEnvelopeError.kdfParametersOutOfBounds
        }
        guard keyLength == self.keyLength else {
            throw BackupEnvelopeError.kdfParametersOutOfBounds
        }
        guard saltLength >= minSaltLength, saltLength <= maxSaltLength else {
            throw BackupEnvelopeError.kdfParametersOutOfBounds
        }
    }

    // MARK: - Header encoding

    static func encodeHeader(_ header: BackupEnvelopeHeader) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(header)
    }

    static func decodeHeader(_ data: Data) throws -> BackupEnvelopeHeader {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(BackupEnvelopeHeader.self, from: data)
        } catch {
            throw BackupEnvelopeError.malformed
        }
    }

    private static func bigEndianLength(_ value: Int) -> Data {
        let v = UInt32(value)
        return Data([
            UInt8((v >> 24) & 0xFF),
            UInt8((v >> 16) & 0xFF),
            UInt8((v >> 8) & 0xFF),
            UInt8(v & 0xFF)
        ])
    }

    // MARK: - PBKDF2

    static func deriveKey(passphrase: String, salt: Data, iterations: Int, keyLength: Int) throws -> SymmetricKey {
        guard let passphraseData = passphrase.data(using: .utf8) else {
            throw BackupEnvelopeError.malformed
        }
        let keyData = try pbkdf2(password: passphraseData, salt: salt, iterations: iterations, keyLength: keyLength)
        return SymmetricKey(data: keyData)
    }

    private static func pbkdf2(password: Data, salt: Data, iterations: Int, keyLength: Int) throws -> Data {
        var derivedKey = Data(repeating: 0, count: keyLength)
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw BackupEnvelopeError.malformed
        }
        return derivedKey
    }
}
