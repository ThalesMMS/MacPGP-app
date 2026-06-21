//
//  EncryptedBackupEnvelopeTests.swift
//  MacPGPTests
//
//  Coverage for issue #127: versioned, self-describing, authenticated backup
//  envelope with V1 read-compatibility and bounded KDF parameters.
//

import Foundation
import Testing
import CryptoKit
@testable import MacPGP

@Suite("Encrypted Backup Envelope Tests")
struct EncryptedBackupEnvelopeTests {
    private let passphrase = "correct horse battery staple"
    private let plaintext = Data("-----BEGIN MACPGP BACKUP-----\nsecret keyring contents\n".utf8)

    private func fixedNonce() -> AES.GCM.Nonce {
        try! AES.GCM.Nonce(data: Data(repeating: 0x24, count: 12))
    }

    private func fixedSalt() -> Data {
        Data(repeating: 0x42, count: 16)
    }

    /// Assemble a V2 envelope from an explicit header and ciphertext body, used to
    /// exercise the open path with headers that `seal` would reject.
    private func makeV2Envelope(header: BackupEnvelopeHeader, combined: Data) throws -> Data {
        let headerData = try EncryptedBackupEnvelope.encodeHeader(header)
        var out = EncryptedBackupEnvelope.v2Magic
        let len = UInt32(headerData.count)
        out.append(contentsOf: [
            UInt8((len >> 24) & 0xFF), UInt8((len >> 16) & 0xFF),
            UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)
        ])
        out.append(headerData)
        out.append(combined)
        return out
    }

    private func validHeader(version: Int = 2, kdf: String? = nil, cipher: String? = nil, iterations: Int = 600_000) -> BackupEnvelopeHeader {
        BackupEnvelopeHeader(
            version: version,
            kdf: kdf ?? EncryptedBackupEnvelope.kdfPBKDF2HMACSHA256,
            kdfParams: BackupKDFParameters(iterations: iterations, keyLength: 32),
            salt: fixedSalt(),
            cipher: cipher ?? EncryptedBackupEnvelope.cipherAES256GCM,
            createdAt: nil
        )
    }

    // MARK: - Round trips

    @Test("V2 seal/open round trip")
    func testV2RoundTrip() throws {
        let sealed = try EncryptedBackupEnvelope.seal(plaintext, passphrase: passphrase)
        #expect(sealed.starts(with: EncryptedBackupEnvelope.v2Magic))
        #expect(EncryptedBackupEnvelope.detectedVersion(sealed) == 2)

        let opened = try EncryptedBackupEnvelope.open(sealed, passphrase: passphrase)
        #expect(opened == plaintext)
    }

    @Test("V1 legacy envelope still opens (read compatibility)")
    func testV1ReadCompatibility() throws {
        let sealedV1 = try EncryptedBackupEnvelope.sealV1(
            plaintext, passphrase: passphrase, salt: fixedSalt(), nonce: fixedNonce()
        )
        #expect(sealedV1.starts(with: EncryptedBackupEnvelope.v1Magic))
        #expect(EncryptedBackupEnvelope.detectedVersion(sealedV1) == 1)

        let opened = try EncryptedBackupEnvelope.open(sealedV1, passphrase: passphrase)
        #expect(opened == plaintext)
    }

    // MARK: - Deterministic test vector

    @Test("Deterministic V2 seal is byte-stable and self-describing")
    func testDeterministicVector() throws {
        let a = try EncryptedBackupEnvelope.sealV2(
            plaintext, passphrase: passphrase, salt: fixedSalt(), nonce: fixedNonce(),
            iterations: 600_000, createdAt: nil
        )
        let b = try EncryptedBackupEnvelope.sealV2(
            plaintext, passphrase: passphrase, salt: fixedSalt(), nonce: fixedNonce(),
            iterations: 600_000, createdAt: nil
        )
        #expect(a == b, "Identical inputs must produce identical envelopes")

        // The header is self-describing and decodes to the declared parameters.
        let magicEnd = EncryptedBackupEnvelope.v2Magic.count
        let headerLength = Int(a[magicEnd]) << 24 | Int(a[magicEnd + 1]) << 16
            | Int(a[magicEnd + 2]) << 8 | Int(a[magicEnd + 3])
        let headerData = a.subdata(in: (magicEnd + 4)..<(magicEnd + 4 + headerLength))
        let header = try EncryptedBackupEnvelope.decodeHeader(headerData)
        #expect(header.version == 2)
        #expect(header.kdf == EncryptedBackupEnvelope.kdfPBKDF2HMACSHA256)
        #expect(header.cipher == EncryptedBackupEnvelope.cipherAES256GCM)
        #expect(header.kdfParams.iterations == 600_000)
        #expect(header.kdfParams.keyLength == 32)
        #expect(header.salt == fixedSalt())

        #expect(try EncryptedBackupEnvelope.open(a, passphrase: passphrase) == plaintext)
    }

    // MARK: - Tampering

    @Test("Wrong passphrase fails authentication")
    func testWrongPassphrase() throws {
        let sealed = try EncryptedBackupEnvelope.seal(plaintext, passphrase: passphrase)
        #expect(throws: BackupEnvelopeError.authenticationFailed) {
            _ = try EncryptedBackupEnvelope.open(sealed, passphrase: "wrong passphrase")
        }
    }

    @Test("Tampering with the ciphertext or tag fails authentication")
    func testTamperedCiphertext() throws {
        var sealed = try EncryptedBackupEnvelope.seal(plaintext, passphrase: passphrase)
        sealed[sealed.count - 1] ^= 0xFF // flip a tag byte
        #expect(throws: BackupEnvelopeError.authenticationFailed) {
            _ = try EncryptedBackupEnvelope.open(sealed, passphrase: passphrase)
        }
    }

    @Test("Tampering with the authenticated header fails to open")
    func testTamperedHeader() throws {
        var sealed = try EncryptedBackupEnvelope.sealV2(
            plaintext, passphrase: passphrase, salt: fixedSalt(), nonce: fixedNonce(),
            iterations: 600_000, createdAt: nil
        )
        // Flip a byte inside the JSON header (just past the magic + length prefix).
        let headerByteIndex = EncryptedBackupEnvelope.v2Magic.count + 4 + 2
        sealed[headerByteIndex] ^= 0x01
        // Either the JSON no longer decodes (malformed) or the AAD no longer
        // authenticates — both are typed failures, never a crash.
        #expect(throws: BackupEnvelopeError.self) {
            _ = try EncryptedBackupEnvelope.open(sealed, passphrase: passphrase)
        }
    }

    @Test("Truncated envelope is rejected, not trapped")
    func testTruncated() throws {
        let sealed = try EncryptedBackupEnvelope.seal(plaintext, passphrase: passphrase)
        let truncated = sealed.prefix(EncryptedBackupEnvelope.v2Magic.count + 6)
        #expect(throws: BackupEnvelopeError.self) {
            _ = try EncryptedBackupEnvelope.open(Data(truncated), passphrase: passphrase)
        }
    }

    @Test("Non-envelope data is reported as malformed")
    func testNotAnEnvelope() {
        #expect(!EncryptedBackupEnvelope.isEncryptedBackup(Data("hello".utf8)))
        #expect(throws: BackupEnvelopeError.malformed) {
            _ = try EncryptedBackupEnvelope.open(Data("not an envelope at all".utf8), passphrase: passphrase)
        }
    }

    // MARK: - Unknown version / KDF / cipher

    @Test("Unknown envelope version is rejected with a typed error")
    func testUnsupportedVersion() throws {
        let envelope = try makeV2Envelope(header: validHeader(version: 3), combined: Data(repeating: 0, count: 40))
        #expect(throws: BackupEnvelopeError.unsupportedVersion(3)) {
            _ = try EncryptedBackupEnvelope.open(envelope, passphrase: passphrase)
        }
    }

    @Test("Unknown KDF identifier is rejected with a typed error")
    func testUnsupportedKDF() throws {
        let envelope = try makeV2Envelope(header: validHeader(kdf: "argon2id"), combined: Data(repeating: 0, count: 40))
        #expect(throws: BackupEnvelopeError.unsupportedKDF("argon2id")) {
            _ = try EncryptedBackupEnvelope.open(envelope, passphrase: passphrase)
        }
    }

    @Test("Unknown cipher identifier is rejected with a typed error")
    func testUnsupportedCipher() throws {
        let envelope = try makeV2Envelope(header: validHeader(cipher: "ChaCha20-Poly1305"), combined: Data(repeating: 0, count: 40))
        #expect(throws: BackupEnvelopeError.unsupportedCipher("ChaCha20-Poly1305")) {
            _ = try EncryptedBackupEnvelope.open(envelope, passphrase: passphrase)
        }
    }

    // MARK: - Parameter bounds

    @Test("KDF parameter bounds are enforced")
    func testKDFParameterBounds() {
        // Valid
        #expect(throws: Never.self) {
            try EncryptedBackupEnvelope.validateKDFParameters(iterations: 600_000, keyLength: 32, saltLength: 16)
        }
        // Too few iterations
        #expect(throws: BackupEnvelopeError.kdfParametersOutOfBounds) {
            try EncryptedBackupEnvelope.validateKDFParameters(iterations: 50_000, keyLength: 32, saltLength: 16)
        }
        // Too many iterations
        #expect(throws: BackupEnvelopeError.kdfParametersOutOfBounds) {
            try EncryptedBackupEnvelope.validateKDFParameters(iterations: 50_000_000, keyLength: 32, saltLength: 16)
        }
        // Wrong key length
        #expect(throws: BackupEnvelopeError.kdfParametersOutOfBounds) {
            try EncryptedBackupEnvelope.validateKDFParameters(iterations: 600_000, keyLength: 16, saltLength: 16)
        }
        // Salt too short / too long
        #expect(throws: BackupEnvelopeError.kdfParametersOutOfBounds) {
            try EncryptedBackupEnvelope.validateKDFParameters(iterations: 600_000, keyLength: 32, saltLength: 4)
        }
        #expect(throws: BackupEnvelopeError.kdfParametersOutOfBounds) {
            try EncryptedBackupEnvelope.validateKDFParameters(iterations: 600_000, keyLength: 32, saltLength: 128)
        }
    }

    @Test("Excessive declared KDF iterations are rejected before key derivation")
    func testRejectsExcessiveIterationsOnOpen() throws {
        // A header that declares an absurd iteration count must be rejected by the
        // bounds check before any expensive derivation runs.
        let envelope = try makeV2Envelope(
            header: validHeader(iterations: 2_000_000_000),
            combined: Data(repeating: 0, count: 40)
        )
        #expect(throws: BackupEnvelopeError.kdfParametersOutOfBounds) {
            _ = try EncryptedBackupEnvelope.open(envelope, passphrase: passphrase)
        }
    }
}
