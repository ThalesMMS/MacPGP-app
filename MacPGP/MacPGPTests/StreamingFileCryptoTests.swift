//
//  StreamingFileCryptoTests.swift
//  MacPGPTests
//
//  Coverage for the streaming/path-based file flows from issue #142:
//  auto-detect file decryption (which must stream and still report the key that
//  succeeded) and path-based file verification. These exercise the behavior the
//  scripts/check-streaming-file-paths.sh guard protects.
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

@MainActor
@Suite("Streaming File Crypto Tests (#142)")
struct StreamingFileCryptoTests {

    // MARK: - Helpers

    private func createTestKeyPair(email: String, passphrase: String) -> PGPKeyModel {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: email, passphrase: passphrase)
        return PGPKeyModel(from: key)
    }

    private func makeEnvironment() -> (KeyringService, EncryptionService, SigningService, VerificationService, PGPKeyModel, PGPKeyModel) {
        let keyring = KeyringService()
        let encryption = EncryptionService(keyringService: keyring)
        let signing = SigningService(keyringService: keyring)
        let verification = VerificationService(keyringService: keyring)
        let alice = createTestKeyPair(email: "alice@stream.local", passphrase: "alice-secret-pass")
        let bob = createTestKeyPair(email: "bob@stream.local", passphrase: "bob-secret-pass")
        try? keyring.addKey(alice.rawKey)
        try? keyring.addKey(bob.rawKey)
        return (keyring, encryption, signing, verification, alice, bob)
    }

    private func cleanup(_ keyring: KeyringService, _ keys: [PGPKeyModel], _ files: [URL]) {
        for key in keys { try? keyring.deleteKey(key) }
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    private func writeTempFile(_ content: Data, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stream-\(UUID().uuidString).\(ext)")
        try content.write(to: url)
        return url
    }

    private func fileSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    // MARK: - Auto-detect streaming decryption

    @Test("Auto-detect file decryption attributes the correct key among several")
    func testTryDecryptFileAttributesCorrectKey() throws {
        let (keyring, encryption, _, _, alice, bob) = makeEnvironment()
        let plaintext = "Auto-detect streaming decryption attributes the recipient."
        let plainFile = try writeTempFile(Data(plaintext.utf8), ext: "txt")

        // Encrypt to Bob only; keyring holds both Alice and Bob secret keys.
        let encryptedFile = try encryption.encrypt(file: plainFile, for: [bob], armored: false)
        try? FileManager.default.removeItem(at: plainFile)

        let (outputURL, foundKey) = try encryption.tryDecrypt(
            file: encryptedFile,
            passphrase: "bob-secret-pass"
        )
        defer { cleanup(keyring, [alice, bob], [encryptedFile, outputURL]) }

        #expect(foundKey.fingerprint == bob.fingerprint)
        let decrypted = try Data(contentsOf: outputURL)
        #expect(String(data: decrypted, encoding: .utf8) == plaintext)
    }

    @Test("Auto-detect async file decryption attributes the correct key")
    func testTryDecryptAsyncFileAttributesCorrectKey() async throws {
        let (keyring, encryption, _, _, alice, bob) = makeEnvironment()
        let plaintext = "Async streaming auto-detect decryption."
        let plainFile = try writeTempFile(Data(plaintext.utf8), ext: "txt")

        let encryptedFile = try encryption.encrypt(file: plainFile, for: [bob], armored: true)
        try? FileManager.default.removeItem(at: plainFile)

        let (outputURL, foundKey) = try await encryption.tryDecryptAsync(
            file: encryptedFile,
            passphrase: "bob-secret-pass"
        )
        defer { cleanup(keyring, [alice, bob], [encryptedFile, outputURL]) }

        #expect(foundKey.fingerprint == bob.fingerprint)
        let decrypted = try Data(contentsOf: outputURL)
        #expect(String(data: decrypted, encoding: .utf8) == plaintext)
    }

    @Test("Auto-detect file decryption with the wrong passphrase throws")
    func testTryDecryptFileWrongPassphraseThrows() throws {
        let (keyring, encryption, _, _, alice, bob) = makeEnvironment()
        let plainFile = try writeTempFile(Data("secret".utf8), ext: "txt")
        let encryptedFile = try encryption.encrypt(file: plainFile, for: [bob], armored: false)
        try? FileManager.default.removeItem(at: plainFile)
        defer { cleanup(keyring, [alice, bob], [encryptedFile]) }

        #expect(throws: OperationError.self) {
            _ = try encryption.tryDecrypt(file: encryptedFile, passphrase: "wrong-pass")
        }
    }

    @Test("Auto-detect streaming preserves a multi-megabyte binary file")
    func testTryDecryptStreamsLargeBinaryFile() async throws {
        let (keyring, encryption, _, _, alice, bob) = makeEnvironment()

        // 4 MiB of random data exercises the streaming path (no fixture stored).
        var payload = Data(count: 4 * 1024 * 1024)
        payload.withUnsafeMutableBytes { buffer in
            if let base = buffer.baseAddress { arc4random_buf(base, buffer.count) }
        }
        let plainFile = try writeTempFile(payload, ext: "bin")
        let encryptedFile = try encryption.encrypt(file: plainFile, for: [bob], armored: false)
        try? FileManager.default.removeItem(at: plainFile)

        let (outputURL, foundKey) = try await encryption.tryDecryptAsync(
            file: encryptedFile,
            passphrase: "bob-secret-pass"
        )
        defer { cleanup(keyring, [alice, bob], [encryptedFile, outputURL]) }

        #expect(foundKey.fingerprint == bob.fingerprint)
        #expect(try Data(contentsOf: outputURL) == payload)
    }

    // MARK: - Path-based verification

    @Test("Path-based async detached verification is valid for an untampered file")
    func testVerifyAsyncDetachedValid() async throws {
        let (keyring, _, signing, verification, alice, bob) = makeEnvironment()
        let content = "Detached path-based verification content."
        let originalFile = try writeTempFile(Data(content.utf8), ext: "txt")

        let signatureFile = try signing.sign(
            file: originalFile,
            using: alice,
            passphrase: "alice-secret-pass",
            detached: true,
            armored: true
        )
        defer { cleanup(keyring, [alice, bob], [originalFile, signatureFile]) }

        let result = try await verification.verifyAsync(file: originalFile, signatureFile: signatureFile)
        #expect(result.isValid)
        #expect(result.signerKey?.fingerprint == alice.fingerprint)
    }

    @Test("Path-based async detached verification fails when the file is tampered")
    func testVerifyAsyncDetachedTamperedFails() async throws {
        let (keyring, _, signing, verification, alice, bob) = makeEnvironment()
        let originalFile = try writeTempFile(Data("original content".utf8), ext: "txt")

        let signatureFile = try signing.sign(
            file: originalFile,
            using: alice,
            passphrase: "alice-secret-pass",
            detached: true,
            armored: true
        )
        // Tamper with the signed content after signing.
        try Data("tampered content!".utf8).write(to: originalFile)
        defer { cleanup(keyring, [alice, bob], [originalFile, signatureFile]) }

        let result = try await verification.verifyAsync(file: originalFile, signatureFile: signatureFile)
        #expect(result.isValid == false)
    }

    // MARK: - Bounded Quick Look metadata

    @Test("Quick Look metadata for a large file reports recipients and the real size from a bounded read")
    func testMetadataBoundedForLargeFile() throws {
        let (keyring, encryption, _, _, alice, bob) = makeEnvironment()

        // 4 MiB > the 512 KiB header limit, so extraction must take the bounded
        // path and still report the true file size and recipients.
        var payload = Data(count: 4 * 1024 * 1024)
        payload.withUnsafeMutableBytes { buffer in
            if let base = buffer.baseAddress { arc4random_buf(base, buffer.count) }
        }
        let plainFile = try writeTempFile(payload, ext: "bin")
        let encryptedFile = try encryption.encrypt(file: plainFile, for: [bob], armored: false)
        try? FileManager.default.removeItem(at: plainFile)
        defer { cleanup(keyring, [alice, bob], [encryptedFile]) }

        let onDiskSize = fileSize(of: encryptedFile)
        #expect(onDiskSize > Int64(PGPMetadataExtractor.defaultMetadataHeaderByteLimit))

        let metadata = try PGPMetadataExtractor().extractMetadata(from: encryptedFile)
        #expect(!metadata.recipientKeyIDs.isEmpty)
        // Reports the real file size, not the bounded prefix length.
        #expect(metadata.fileSize == onDiskSize)
        #expect(metadata.fileSize > Int64(PGPMetadataExtractor.defaultMetadataHeaderByteLimit))
    }

    @Test("Quick Look metadata for a small file still extracts recipients")
    func testMetadataSmallFile() throws {
        let (keyring, encryption, _, _, alice, bob) = makeEnvironment()
        let plainFile = try writeTempFile(Data("small payload".utf8), ext: "txt")
        let encryptedFile = try encryption.encrypt(file: plainFile, for: [bob], armored: false)
        try? FileManager.default.removeItem(at: plainFile)
        defer { cleanup(keyring, [alice, bob], [encryptedFile]) }

        let metadata = try PGPMetadataExtractor().extractMetadata(from: encryptedFile)
        #expect(!metadata.recipientKeyIDs.isEmpty)
        #expect(metadata.fileSize == fileSize(of: encryptedFile))
    }
}
