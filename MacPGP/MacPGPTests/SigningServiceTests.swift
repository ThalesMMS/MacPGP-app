//
//  SigningServiceTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 04/02/26.
//

import Testing
import Foundation
import ObjectivePGP
@testable import MacPGP

@Suite("SigningService Tests")
struct SigningServiceTests {

    // MARK: - Test Helpers

    func createTestKeyPair(email: String, passphrase: String) -> PGPKeyModel {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: email, passphrase: passphrase)
        return PGPKeyModel(from: key)
    }

    func setupTestEnvironment() -> (service: SigningService, keyring: KeyringService, signerKey: PGPKeyModel) {
        let keyring = KeyringService()

        let signerKey = createTestKeyPair(email: "signer@test.local", passphrase: "signer-pass")

        try? keyring.addKey(signerKey.rawKey)

        let service = SigningService(keyringService: keyring)

        return (service, keyring, signerKey)
    }

    func cleanupTestKeys(keyring: KeyringService, keys: [PGPKeyModel]) {
        for key in keys {
            try? keyring.deleteKey(key)
        }
    }

    // MARK: - Data Signing Tests

    @Test("Sign data successfully with detached signature")
    func testSignDataDetached() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testData = "Hello, World!".data(using: .utf8)!

        let signedData = try service.sign(
            data: testData,
            using: signerKey,
            passphrase: "signer-pass",
            detached: true,
            armored: true
        )

        #expect(!signedData.isEmpty)
        #expect(signedData != testData)

        if let armoredString = String(data: signedData, encoding: .utf8) {
            #expect(armoredString.contains("-----BEGIN PGP SIGNATURE-----"))
        }
    }

    @Test("Sign data successfully with inline signature")
    func testSignDataInline() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testData = "Inline signature test".data(using: .utf8)!

        let signedData = try service.sign(
            data: testData,
            using: signerKey,
            passphrase: "signer-pass",
            detached: false,
            armored: true
        )

        #expect(!signedData.isEmpty)

        if let armoredString = String(data: signedData, encoding: .utf8) {
            #expect(armoredString.contains("-----BEGIN PGP MESSAGE-----"))
        }
    }

    @Test("Sign data without armor")
    func testSignDataBinary() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testData = "Binary signature".data(using: .utf8)!

        let signedData = try service.sign(
            data: testData,
            using: signerKey,
            passphrase: "signer-pass",
            detached: true,
            armored: false
        )

        #expect(!signedData.isEmpty)

        let dataString = String(data: signedData, encoding: .utf8)
        #expect(dataString == nil || !dataString!.contains("-----BEGIN PGP"))
    }

    @Test("Sign data throws error with wrong passphrase")
    func testSignDataWrongPassphrase() {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testData = "Test".data(using: .utf8)!

        #expect(throws: OperationError.self) {
            try service.sign(
                data: testData,
                using: signerKey,
                passphrase: "wrong-passphrase",
                detached: true
            )
        }
    }

    @Test("Sign data throws error with key not found")
    func testSignDataKeyNotFound() {
        let keyring = KeyringService()
        let service = SigningService(keyringService: keyring)

        let fakeKey = createTestKeyPair(email: "fake@test.local", passphrase: "pass")
        let testData = "Test".data(using: .utf8)!

        #expect(throws: OperationError.self) {
            try service.sign(
                data: testData,
                using: fakeKey,
                passphrase: "pass",
                detached: true
            )
        }
    }

    // MARK: - Message Signing Tests

    @Test("Sign message with cleartext signature")
    func testSignMessageCleartext() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testMessage = "This is a cleartext signed message"

        let signedMessage = try service.sign(
            message: testMessage,
            using: signerKey,
            passphrase: "signer-pass",
            cleartext: true,
            detached: false,
            armored: true
        )

        #expect(!signedMessage.isEmpty)
        #expect(signedMessage.contains("-----BEGIN PGP SIGNED MESSAGE-----"))
        #expect(signedMessage.contains("-----BEGIN PGP SIGNATURE-----"))
        #expect(signedMessage.contains(testMessage))
    }

    @Test("Sign message with inline signature")
    func testSignMessageInline() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testMessage = "Inline signed message"

        let signedMessage = try service.sign(
            message: testMessage,
            using: signerKey,
            passphrase: "signer-pass",
            cleartext: false,
            detached: false,
            armored: true
        )

        #expect(!signedMessage.isEmpty)
        #expect(signedMessage.contains("-----BEGIN PGP MESSAGE-----"))
    }

    @Test("Sign message with detached signature")
    func testSignMessageDetached() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testMessage = "Message with detached signature"

        let signature = try service.sign(
            message: testMessage,
            using: signerKey,
            passphrase: "signer-pass",
            cleartext: false,
            detached: true,
            armored: true
        )

        #expect(!signature.isEmpty)
        #expect(signature.contains("-----BEGIN PGP SIGNATURE-----"))
        #expect(!signature.contains(testMessage))
    }

    @Test("Sign message without armor returns base64")
    func testSignMessageBinary() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testMessage = "Binary message signature"

        let signature = try service.sign(
            message: testMessage,
            using: signerKey,
            passphrase: "signer-pass",
            cleartext: false,
            detached: true,
            armored: false
        )

        #expect(!signature.isEmpty)
        #expect(!signature.contains("-----BEGIN PGP"))

        let decoded = Data(base64Encoded: signature)
        #expect(decoded != nil)
    }

    @Test("Sign message with wrong passphrase throws error")
    func testSignMessageWrongPassphrase() {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testMessage = "Test message"

        #expect(throws: OperationError.self) {
            try service.sign(
                message: testMessage,
                using: signerKey,
                passphrase: "wrong-pass",
                cleartext: true
            )
        }
    }

    // MARK: - File Signing Tests

    @Test("Sign file with detached signature")
    func testSignFileDetached() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-sign-\(UUID().uuidString).txt")
        let testContent = "File content to sign"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let signatureFile = try service.sign(
            file: testFile,
            using: signerKey,
            passphrase: "signer-pass",
            detached: true,
            armored: true
        )

        defer {
            try? FileManager.default.removeItem(at: signatureFile)
        }

        #expect(FileManager.default.fileExists(atPath: signatureFile.path))
        #expect(signatureFile.pathExtension == "asc")

        let signatureContent = try String(contentsOf: signatureFile, encoding: .utf8)
        #expect(signatureContent.contains("-----BEGIN PGP SIGNATURE-----"))
    }

    @Test("Sign file with inline signature")
    func testSignFileInline() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-inline-\(UUID().uuidString).txt")
        let testContent = "Inline signed file"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let signedFile = try service.sign(
            file: testFile,
            using: signerKey,
            passphrase: "signer-pass",
            detached: false,
            armored: true
        )

        defer {
            try? FileManager.default.removeItem(at: signedFile)
        }

        #expect(FileManager.default.fileExists(atPath: signedFile.path))
        #expect(signedFile.pathExtension == "asc")

        let signedContent = try String(contentsOf: signedFile, encoding: .utf8)
        #expect(signedContent.contains("-----BEGIN PGP MESSAGE-----"))
    }

    @Test("Sign file with binary signature")
    func testSignFileBinary() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-binary-sig-\(UUID().uuidString).txt")
        let testContent = "Binary signature file"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let signatureFile = try service.sign(
            file: testFile,
            using: signerKey,
            passphrase: "signer-pass",
            detached: true,
            armored: false
        )

        defer {
            try? FileManager.default.removeItem(at: signatureFile)
        }

        #expect(FileManager.default.fileExists(atPath: signatureFile.path))
        #expect(signatureFile.pathExtension == "sig")
    }

    @Test("Sign file with custom output path")
    func testSignFileCustomOutput() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-custom-\(UUID().uuidString).txt")
        let customOutput = tempDir.appendingPathComponent("custom-signature-\(UUID().uuidString).sig")
        let testContent = "Custom output test"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
            try? FileManager.default.removeItem(at: customOutput)
        }

        let outputFile = try service.sign(
            file: testFile,
            using: signerKey,
            passphrase: "signer-pass",
            detached: true,
            outputURL: customOutput,
            armored: false
        )

        #expect(outputFile == customOutput)
        #expect(FileManager.default.fileExists(atPath: outputFile.path))
    }

    @Test("Sign file with wrong passphrase throws error")
    func testSignFileWrongPassphrase() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-wrong-pass-\(UUID().uuidString).txt")
        let testContent = "Test content"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        #expect(throws: OperationError.self) {
            try service.sign(
                file: testFile,
                using: signerKey,
                passphrase: "wrong-passphrase",
                detached: true
            )
        }
    }

    // MARK: - Data Verification Tests

    @Test("Verify signed data successfully")
    func testVerifyData() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testData = "Data to verify".data(using: .utf8)!

        let signedData = try service.sign(
            data: testData,
            using: signerKey,
            passphrase: "signer-pass",
            detached: false,
            armored: true
        )

        let result = try service.verify(data: signedData)

        #expect(result.isValid)
        #expect(result.message == "Signature is valid")
    }

    @Test("Verify detached signature successfully")
    func testVerifyDetachedSignature() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testData = "Data with detached signature".data(using: .utf8)!

        let signature = try service.sign(
            data: testData,
            using: signerKey,
            passphrase: "signer-pass",
            detached: true,
            armored: false
        )

        let result = try service.verify(data: testData, signature: signature)

        #expect(result.isValid)
    }

    @Test("Verify unsigned data returns invalid")
    func testVerifyUnsignedData() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let unsignedData = "This is just plain text, not signed".data(using: .utf8)!

        let result = try service.verify(data: unsignedData)

        #expect(!result.isValid)
    }

    @Test("Verify invalid signature returns invalid")
    func testVerifyInvalidSignature() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testData = "Original data".data(using: .utf8)!
        let tamperedData = "Tampered data".data(using: .utf8)!

        let signature = try service.sign(
            data: testData,
            using: signerKey,
            passphrase: "signer-pass",
            detached: true,
            armored: false
        )

        let result = try service.verify(data: tamperedData, signature: signature)

        #expect(!result.isValid)
    }

    // MARK: - Message Verification Tests

    @Test("Verify cleartext signed message successfully")
    func testVerifyCleartextMessage() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testMessage = "Cleartext message to verify"

        let signedMessage = try service.sign(
            message: testMessage,
            using: signerKey,
            passphrase: "signer-pass",
            cleartext: true,
            detached: false,
            armored: true
        )

        let result = try service.verify(message: signedMessage)

        #expect(result.isValid)
        #expect(result.originalMessage == testMessage)
    }

    @Test("Verify inline signed message successfully")
    func testVerifyInlineMessage() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testMessage = "Inline signed message"

        let signedMessage = try service.sign(
            message: testMessage,
            using: signerKey,
            passphrase: "signer-pass",
            cleartext: false,
            detached: false,
            armored: true
        )

        let result = try service.verify(message: signedMessage)

        #expect(result.isValid)
    }

    @Test("Verify message with detached signature successfully")
    func testVerifyMessageDetachedSignature() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testMessage = "Message for detached verification"

        let signature = try service.sign(
            message: testMessage,
            using: signerKey,
            passphrase: "signer-pass",
            cleartext: false,
            detached: true,
            armored: true
        )

        let result = try service.verify(message: testMessage, signature: signature)

        #expect(result.isValid)
    }

    @Test("Verify tampered cleartext message returns invalid")
    func testVerifyTamperedCleartextMessage() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let testMessage = "Original message"

        let signedMessage = try service.sign(
            message: testMessage,
            using: signerKey,
            passphrase: "signer-pass",
            cleartext: true,
            detached: false,
            armored: true
        )

        let tamperedMessage = signedMessage.replacingOccurrences(of: "Original message", with: "Tampered message")

        let result = try service.verify(message: tamperedMessage)

        #expect(!result.isValid)
    }

    // MARK: - File Verification Tests

    @Test("Verify signed file successfully")
    func testVerifyFile() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("verify-file-\(UUID().uuidString).txt")
        let testContent = "File to verify"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let signatureFile = try service.sign(
            file: testFile,
            using: signerKey,
            passphrase: "signer-pass",
            detached: true,
            armored: true
        )

        defer {
            try? FileManager.default.removeItem(at: signatureFile)
        }

        let result = try service.verify(file: testFile, signatureFile: signatureFile)

        #expect(result.isValid)
    }

    @Test("Verify inline signed file successfully")
    func testVerifyInlineSignedFile() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("inline-verify-\(UUID().uuidString).txt")
        let testContent = "Inline signed file content"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let signedFile = try service.sign(
            file: testFile,
            using: signerKey,
            passphrase: "signer-pass",
            detached: false,
            armored: true
        )

        defer {
            try? FileManager.default.removeItem(at: signedFile)
        }

        let result = try service.verify(file: signedFile)

        #expect(result.isValid)
    }

    @Test("Verify tampered file returns invalid")
    func testVerifyTamperedFile() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("tampered-\(UUID().uuidString).txt")
        let testContent = "Original file content"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let signatureFile = try service.sign(
            file: testFile,
            using: signerKey,
            passphrase: "signer-pass",
            detached: true,
            armored: true
        )

        defer {
            try? FileManager.default.removeItem(at: signatureFile)
        }

        let tamperedContent = "Tampered file content"
        try tamperedContent.write(to: testFile, atomically: true, encoding: .utf8)

        let result = try service.verify(file: testFile, signatureFile: signatureFile)

        #expect(!result.isValid)
    }

    // MARK: - Round-trip Integration Tests

    @Test("Full sign-verify round trip for data")
    func testDataSignVerifyRoundTrip() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let originalData = "Round trip test data 🔐".data(using: .utf8)!

        let signed = try service.sign(
            data: originalData,
            using: signerKey,
            passphrase: "signer-pass",
            detached: false,
            armored: true
        )

        let verified = try service.verify(data: signed)

        #expect(verified.isValid)
        #expect(verified.message == "Signature is valid")
    }

    @Test("Full sign-verify round trip for cleartext message")
    func testCleartextMessageRoundTrip() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let originalMessage = "Round trip cleartext message 📝"

        let signed = try service.sign(
            message: originalMessage,
            using: signerKey,
            passphrase: "signer-pass",
            cleartext: true
        )

        let verified = try service.verify(message: signed)

        #expect(verified.isValid)
        #expect(verified.originalMessage == originalMessage)
    }

    @Test("Full sign-verify round trip for file")
    func testFileSignVerifyRoundTrip() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("roundtrip-\(UUID().uuidString).txt")
        let testContent = "File round trip test 📁"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let signatureFile = try service.sign(
            file: testFile,
            using: signerKey,
            passphrase: "signer-pass",
            detached: true,
            armored: true
        )

        defer {
            try? FileManager.default.removeItem(at: signatureFile)
        }

        let verified = try service.verify(file: testFile, signatureFile: signatureFile)

        #expect(verified.isValid)
    }

    @Test("Detached signature round trip for data")
    func testDetachedSignatureRoundTrip() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let originalData = "Detached signature test".data(using: .utf8)!

        let signature = try service.sign(
            data: originalData,
            using: signerKey,
            passphrase: "signer-pass",
            detached: true,
            armored: false
        )

        let verified = try service.verify(data: originalData, signature: signature)

        #expect(verified.isValid)
    }

    @Test("Detached signature round trip for message")
    func testDetachedMessageSignatureRoundTrip() throws {
        let (service, keyring, signerKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [signerKey]) }

        let originalMessage = "Message with detached sig"

        let signature = try service.sign(
            message: originalMessage,
            using: signerKey,
            passphrase: "signer-pass",
            cleartext: false,
            detached: true,
            armored: true
        )

        let verified = try service.verify(message: originalMessage, signature: signature)

        #expect(verified.isValid)
    }
}
