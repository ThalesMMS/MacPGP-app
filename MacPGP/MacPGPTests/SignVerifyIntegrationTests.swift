//
//  SignVerifyIntegrationTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 04/02/26.
//

import Testing
import Foundation
import ObjectivePGP
@testable import MacPGP

@Suite("Sign/Verify Integration Tests")
struct SignVerifyIntegrationTests {

    // MARK: - Test Helpers

    func createTestKeyPair(email: String, passphrase: String) -> PGPKeyModel {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: email, passphrase: passphrase)
        return PGPKeyModel(from: key)
    }

    func setupIntegrationEnvironment() -> (keyring: KeyringService, signing: SigningService, alice: PGPKeyModel, bob: PGPKeyModel) {
        let keyring = KeyringService()
        let signing = SigningService(keyringService: keyring)

        let alice = createTestKeyPair(email: "alice@test.local", passphrase: "alice-secret-pass")
        let bob = createTestKeyPair(email: "bob@test.local", passphrase: "bob-secret-pass")

        try? keyring.addKey(alice.rawKey)
        try? keyring.addKey(bob.rawKey)

        return (keyring, signing, alice, bob)
    }

    func cleanupKeys(keyring: KeyringService, keys: [PGPKeyModel]) {
        for key in keys {
            try? keyring.deleteKey(key)
        }
    }

    // MARK: - Cleartext Message Round-Trip Tests

    @Test("Alice signs cleartext message, Bob verifies successfully")
    func testBasicCleartextMessageRoundTrip() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "Hello Bob, this is a signed message from Alice!"

        // Alice signs message
        let signedMessage = try signing.sign(
            message: originalMessage,
            using: alice,
            passphrase: "alice-secret-pass",
            cleartext: true,
            detached: false,
            armored: true
        )

        // Verify it's signed (cleartext format)
        #expect(signedMessage.contains("-----BEGIN PGP SIGNED MESSAGE-----"))
        #expect(signedMessage.contains("-----BEGIN PGP SIGNATURE-----"))
        #expect(signedMessage.contains("-----END PGP SIGNATURE-----"))
        #expect(signedMessage.contains(originalMessage))

        // Bob verifies the signature
        let result = try signing.verify(message: signedMessage)

        #expect(result.isValid)
        #expect(result.message == "Signature is valid")
        #expect(result.originalMessage == originalMessage)
    }

    @Test("Round-trip with special characters and emoji")
    func testCleartextMessageWithUnicode() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "Test with emoji 🔐🚀💻 and special chars: !@#$%^&*()"

        let signed = try signing.sign(
            message: originalMessage,
            using: alice,
            passphrase: "alice-secret-pass",
            cleartext: true
        )

        let verified = try signing.verify(message: signed)

        #expect(verified.isValid)
        #expect(verified.originalMessage == originalMessage)
    }

    @Test("Round-trip with long message")
    func testLongCleartextMessageRoundTrip() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = String(repeating: "This is a very long message that should still sign and verify correctly. ", count: 100)

        let signed = try signing.sign(
            message: originalMessage,
            using: alice,
            passphrase: "alice-secret-pass",
            cleartext: true
        )

        let verified = try signing.verify(message: signed)

        #expect(verified.isValid)
        #expect(verified.originalMessage == originalMessage)
    }

    @Test("Round-trip with multiline message")
    func testMultilineCleartextMessageRoundTrip() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = """
        First line of the message.
        Second line with more text.
        Third line with special chars: <>&"'

        Fifth line after an empty line.
        """

        let signed = try signing.sign(
            message: originalMessage,
            using: alice,
            passphrase: "alice-secret-pass",
            cleartext: true
        )

        let verified = try signing.verify(message: signed)

        #expect(verified.isValid)
        #expect(verified.originalMessage == originalMessage)
    }

    // MARK: - Inline Signature Round-Trip Tests

    @Test("Inline signature round-trip for message")
    func testInlineSignatureMessageRoundTrip() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "This is an inline signed message"

        let signed = try signing.sign(
            message: originalMessage,
            using: alice,
            passphrase: "alice-secret-pass",
            cleartext: false,
            detached: false,
            armored: true
        )

        #expect(signed.contains("-----BEGIN PGP MESSAGE-----"))
        #expect(signed.contains("-----END PGP MESSAGE-----"))
        #expect(!signed.contains(originalMessage))

        let verified = try signing.verify(message: signed)

        #expect(verified.isValid)
    }

    @Test("Inline signature with binary data")
    func testInlineSignatureDataRoundTrip() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalData = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD, 0x7F, 0x80])

        let signed = try signing.sign(
            data: originalData,
            using: alice,
            passphrase: "alice-secret-pass",
            detached: false,
            armored: false
        )

        let verified = try signing.verify(data: signed)

        #expect(verified.isValid)
    }

    // MARK: - Detached Signature Round-Trip Tests

    @Test("Detached signature round-trip for message")
    func testDetachedSignatureMessageRoundTrip() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "Message with detached signature"

        let signature = try signing.sign(
            message: originalMessage,
            using: alice,
            passphrase: "alice-secret-pass",
            cleartext: false,
            detached: true,
            armored: true
        )

        #expect(signature.contains("-----BEGIN PGP SIGNATURE-----"))
        #expect(!signature.contains(originalMessage))

        let verified = try signing.verify(message: originalMessage, signature: signature)

        #expect(verified.isValid)
    }

    @Test("Detached signature round-trip for data")
    func testDetachedSignatureDataRoundTrip() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalData = "Detached signature test data".data(using: .utf8)!

        let signature = try signing.sign(
            data: originalData,
            using: alice,
            passphrase: "alice-secret-pass",
            detached: true,
            armored: false
        )

        #expect(!signature.isEmpty)
        #expect(signature != originalData)

        let verified = try signing.verify(data: originalData, signature: signature)

        #expect(verified.isValid)
    }

    @Test("Detached signature with large data")
    func testDetachedSignatureLargeData() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        // Create 1MB of random data
        var originalData = Data(count: 1024 * 1024)
        originalData.withUnsafeMutableBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                arc4random_buf(baseAddress, buffer.count)
            }
        }

        let signature = try signing.sign(
            data: originalData,
            using: alice,
            passphrase: "alice-secret-pass",
            detached: true,
            armored: false
        )

        let verified = try signing.verify(data: originalData, signature: signature)

        #expect(verified.isValid)
    }

    // MARK: - File Round-Trip Tests

    @Test("File signing and verification with detached signature")
    func testFileDetachedSignatureRoundTrip() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("sign-verify-test-\(UUID().uuidString).txt")
        let originalContent = "This is a test file for sign/verify integration testing."
        try originalContent.write(to: originalFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: originalFile)
        }

        // Sign file
        let signatureFile = try signing.sign(
            file: originalFile,
            using: alice,
            passphrase: "alice-secret-pass",
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

        // Verify file
        let result = try signing.verify(file: originalFile, signatureFile: signatureFile)

        #expect(result.isValid)
        #expect(result.message == "Signature is valid")
    }

    @Test("File signing with inline signature")
    func testFileInlineSignatureRoundTrip() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("inline-sign-test-\(UUID().uuidString).txt")
        let originalContent = "Inline signed file content"
        try originalContent.write(to: originalFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: originalFile)
        }

        let signedFile = try signing.sign(
            file: originalFile,
            using: alice,
            passphrase: "alice-secret-pass",
            detached: false,
            armored: true
        )
        defer {
            try? FileManager.default.removeItem(at: signedFile)
        }

        #expect(FileManager.default.fileExists(atPath: signedFile.path))

        let result = try signing.verify(file: signedFile)

        #expect(result.isValid)
    }

    @Test("Binary file round-trip with detached signature")
    func testBinaryFileRoundTrip() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("binary-sign-test-\(UUID().uuidString).bin")

        // Create binary data
        var binaryData = Data(count: 1024)
        binaryData.withUnsafeMutableBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                arc4random_buf(baseAddress, buffer.count)
            }
        }
        try binaryData.write(to: originalFile)

        defer {
            try? FileManager.default.removeItem(at: originalFile)
        }

        let signatureFile = try signing.sign(
            file: originalFile,
            using: alice,
            passphrase: "alice-secret-pass",
            detached: true,
            armored: false
        )
        defer {
            try? FileManager.default.removeItem(at: signatureFile)
        }

        #expect(signatureFile.pathExtension == "sig")

        let result = try signing.verify(file: originalFile, signatureFile: signatureFile)

        #expect(result.isValid)
    }

    // MARK: - Error Cases

    @Test("Tampered cleartext message fails verification")
    func testTamperedCleartextMessageFailsVerification() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "Original message"

        let signed = try signing.sign(
            message: originalMessage,
            using: alice,
            passphrase: "alice-secret-pass",
            cleartext: true
        )

        // Tamper with the message
        let tampered = signed.replacingOccurrences(of: "Original message", with: "Tampered message")

        let result = try signing.verify(message: tampered)

        #expect(!result.isValid)
    }

    @Test("Tampered detached signature fails verification")
    func testTamperedDetachedSignatureFailsVerification() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "Original data"
        let tamperedMessage = "Tampered data"

        let signature = try signing.sign(
            message: originalMessage,
            using: alice,
            passphrase: "alice-secret-pass",
            cleartext: false,
            detached: true,
            armored: true
        )

        let result = try signing.verify(message: tamperedMessage, signature: signature)

        #expect(!result.isValid)
    }

    @Test("Tampered file fails verification")
    func testTamperedFileFailsVerification() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("tamper-test-\(UUID().uuidString).txt")
        let originalContent = "Original file content"
        try originalContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let signatureFile = try signing.sign(
            file: testFile,
            using: alice,
            passphrase: "alice-secret-pass",
            detached: true,
            armored: true
        )
        defer {
            try? FileManager.default.removeItem(at: signatureFile)
        }

        // Tamper with file content
        let tamperedContent = "Tampered file content"
        try tamperedContent.write(to: testFile, atomically: true, encoding: .utf8)

        let result = try signing.verify(file: testFile, signatureFile: signatureFile)

        #expect(!result.isValid)
    }

    @Test("Unsigned message fails verification")
    func testUnsignedMessageFailsVerification() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let unsignedMessage = "This is just plain text, not signed"

        let result = try signing.verify(message: unsignedMessage)

        #expect(!result.isValid)
    }

    @Test("Verification with no keys in keyring")
    func testVerificationWithoutKeys() throws {
        let keyring = KeyringService()
        let signing = SigningService(keyringService: keyring)

        let alice = createTestKeyPair(email: "alice@test.local", passphrase: "alice-secret-pass")

        // Add alice to keyring temporarily for signing
        try keyring.addKey(alice.rawKey)

        // Sign with alice
        let signedMessage = try signing.sign(
            message: "Test message",
            using: alice,
            passphrase: "alice-secret-pass",
            cleartext: true
        )

        // Remove ALL keys from keyring before verification
        let allKeys = keyring.keys
        for key in allKeys {
            try keyring.deleteKey(key)
        }

        // Verify keyring is truly empty
        #expect(keyring.keys.isEmpty)

        // Now try to verify without any keys in keyring
        let result = try signing.verify(message: signedMessage)

        #expect(!result.isValid)
        #expect(result.message == "No keys available for verification")
    }

    // MARK: - Armored vs Binary Format Tests

    @Test("Round-trip comparison: armored vs binary detached signatures")
    func testArmoredVsBinaryDetachedSignature() throws {
        let (keyring, signing, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "Testing armored vs binary signature format"

        // Sign with armored signature
        let armoredSignature = try signing.sign(
            message: originalMessage,
            using: alice,
            passphrase: "alice-secret-pass",
            cleartext: false,
            detached: true,
            armored: true
        )
        #expect(armoredSignature.contains("-----BEGIN PGP SIGNATURE-----"))

        // Sign with binary signature
        let binarySignature = try signing.sign(
            message: originalMessage,
            using: alice,
            passphrase: "alice-secret-pass",
            cleartext: false,
            detached: true,
            armored: false
        )
        #expect(!binarySignature.contains("-----BEGIN PGP SIGNATURE-----"))

        // Both should verify successfully
        let armoredVerified = try signing.verify(message: originalMessage, signature: armoredSignature)
        #expect(armoredVerified.isValid)

        let binaryVerified = try signing.verify(message: originalMessage, signature: binarySignature)
        #expect(binaryVerified.isValid)
    }

    // MARK: - End-to-End Workflow Test

    @Test("Complete end-to-end workflow: generate, sign, verify")
    func testCompleteEndToEndWorkflow() throws {
        // Setup: Create fresh keyring and signing service
        let keyring = KeyringService()
        let signing = SigningService(keyringService: keyring)

        // Step 1: Generate key for signer
        let signer = createTestKeyPair(email: "signer@example.com", passphrase: "signer123")

        // Step 2: Add key to keyring
        try keyring.addKey(signer.rawKey)

        defer {
            cleanupKeys(keyring: keyring, keys: [signer])
        }

        // Step 3: Verify key is in keyring
        let allKeys = keyring.keys
        #expect(allKeys.count >= 1)
        #expect(allKeys.contains(where: { $0.fingerprint == signer.fingerprint }))

        // Step 4: Sign a message
        let secretMessage = "This is a complete end-to-end test message for signing."
        let signedMessage = try signing.sign(
            message: secretMessage,
            using: signer,
            passphrase: "signer123",
            cleartext: true,
            detached: false,
            armored: true
        )

        // Step 5: Verify signing worked
        #expect(!signedMessage.isEmpty)
        #expect(signedMessage != secretMessage)
        #expect(signedMessage.contains("-----BEGIN PGP SIGNED MESSAGE-----"))
        #expect(signedMessage.contains(secretMessage))

        // Step 6: Verify the signature
        let verificationResult = try signing.verify(message: signedMessage)

        // Step 7: Verify verification worked
        #expect(verificationResult.isValid)
        #expect(verificationResult.message == "Signature is valid")
        #expect(verificationResult.originalMessage == secretMessage)
    }

    // MARK: - Cross-User Workflow Test

    @Test("Alice signs, Bob verifies with Alice's public key")
    func testCrossUserSignVerifyWorkflow() throws {
        let keyring = KeyringService()
        let signing = SigningService(keyringService: keyring)

        // Alice generates her keypair
        let alice = createTestKeyPair(email: "alice@example.com", passphrase: "alice-pass")

        // Alice adds her key to her keyring
        try keyring.addKey(alice.rawKey)

        defer {
            cleanupKeys(keyring: keyring, keys: [alice])
        }

        // Alice signs a message
        let message = "Alice's signed message for Bob"
        let signedMessage = try signing.sign(
            message: message,
            using: alice,
            passphrase: "alice-pass",
            cleartext: true
        )

        // Bob receives the signed message
        // Bob's keyring already has Alice's public key (from earlier step)
        // Bob verifies the signature
        let result = try signing.verify(message: signedMessage)

        #expect(result.isValid)
        #expect(result.originalMessage == message)
    }
}
