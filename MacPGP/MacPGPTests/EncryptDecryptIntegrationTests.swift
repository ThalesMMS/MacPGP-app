//
//  EncryptDecryptIntegrationTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 04/02/26.
//

import Testing
import Foundation
import ObjectivePGP
@testable import MacPGP

@Suite("Encrypt/Decrypt Integration Tests")
struct EncryptDecryptIntegrationTests {

    // MARK: - Test Helpers

    func createTestKeyPair(email: String, passphrase: String) -> PGPKeyModel {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: email, passphrase: passphrase)
        return PGPKeyModel(from: key)
    }

    func setupIntegrationEnvironment() -> (keyring: KeyringService, encryption: EncryptionService, alice: PGPKeyModel, bob: PGPKeyModel) {
        let keyring = KeyringService()
        let encryption = EncryptionService(keyringService: keyring)

        let alice = createTestKeyPair(email: "alice@test.local", passphrase: "alice-secret-pass")
        let bob = createTestKeyPair(email: "bob@test.local", passphrase: "bob-secret-pass")

        try? keyring.addKey(alice.rawKey)
        try? keyring.addKey(bob.rawKey)

        return (keyring, encryption, alice, bob)
    }

    func cleanupKeys(keyring: KeyringService, keys: [PGPKeyModel]) {
        for key in keys {
            try? keyring.deleteKey(key)
        }
    }

    // MARK: - Message Round-Trip Tests

    @Test("Alice encrypts message for Bob, Bob decrypts successfully")
    func testBasicMessageRoundTrip() throws {
        let (keyring, encryption, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "Hello Bob, this is a secret message from Alice!"

        // Alice encrypts message for Bob
        let encryptedMessage = try encryption.encrypt(
            message: originalMessage,
            for: [bob],
            armored: true
        )

        // Verify it's encrypted (armored format)
        #expect(encryptedMessage.contains("-----BEGIN PGP MESSAGE-----"))
        #expect(encryptedMessage.contains("-----END PGP MESSAGE-----"))
        #expect(encryptedMessage != originalMessage)

        // Bob decrypts the message
        let decryptedMessage = try encryption.decrypt(
            message: encryptedMessage,
            using: bob,
            passphrase: "bob-secret-pass"
        )

        #expect(decryptedMessage == originalMessage)
    }

    @Test("Round-trip with special characters and emoji")
    func testMessageRoundTripWithUnicode() throws {
        let (keyring, encryption, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "Test with emoji 🔐🚀💻 and special chars: !@#$%^&*()"

        let encrypted = try encryption.encrypt(message: originalMessage, for: [bob])
        let decrypted = try encryption.decrypt(message: encrypted, using: bob, passphrase: "bob-secret-pass")

        #expect(decrypted == originalMessage)
    }

    @Test("Round-trip with long message")
    func testLongMessageRoundTrip() throws {
        let (keyring, encryption, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = String(repeating: "This is a very long message that should still encrypt and decrypt correctly. ", count: 100)

        let encrypted = try encryption.encrypt(message: originalMessage, for: [bob])
        let decrypted = try encryption.decrypt(message: encrypted, using: bob, passphrase: "bob-secret-pass")

        #expect(decrypted == originalMessage)
    }

    @Test("Round-trip with multiline message")
    func testMultilineMessageRoundTrip() throws {
        let (keyring, encryption, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = """
        First line of the message.
        Second line with more text.
        Third line with special chars: <>&"'

        Fifth line after an empty line.
        """

        let encrypted = try encryption.encrypt(message: originalMessage, for: [bob])
        let decrypted = try encryption.decrypt(message: encrypted, using: bob, passphrase: "bob-secret-pass")

        #expect(decrypted == originalMessage)
    }

    // MARK: - Data Round-Trip Tests

    @Test("Binary data round-trip")
    func testDataRoundTrip() throws {
        let (keyring, encryption, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalData = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD, 0x7F, 0x80])

        let encrypted = try encryption.encrypt(data: originalData, for: [bob], armored: false)
        let decrypted = try encryption.decrypt(data: encrypted, using: bob, passphrase: "bob-secret-pass")

        #expect(decrypted == originalData)
    }

    @Test("Large binary data round-trip")
    func testLargeDataRoundTrip() throws {
        let (keyring, encryption, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        // Create 1MB of random data
        var originalData = Data(count: 1024 * 1024)
        originalData.withUnsafeMutableBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                arc4random_buf(baseAddress, buffer.count)
            }
        }

        let encrypted = try encryption.encrypt(data: originalData, for: [bob], armored: false)
        let decrypted = try encryption.decrypt(data: encrypted, using: bob, passphrase: "bob-secret-pass")

        #expect(decrypted == originalData)
    }

    // MARK: - File Round-Trip Tests

    @Test("File encryption and decryption round-trip")
    func testFileRoundTrip() throws {
        let (keyring, encryption, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("integration-test-\(UUID().uuidString).txt")
        let originalContent = "This is a test file for integration testing."
        try originalContent.write(to: originalFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: originalFile)
        }

        // Encrypt file
        let encryptedFile = try encryption.encrypt(file: originalFile, for: [bob], armored: true)
        defer {
            try? FileManager.default.removeItem(at: encryptedFile)
        }

        #expect(FileManager.default.fileExists(atPath: encryptedFile.path))
        #expect(encryptedFile.pathExtension == "asc")

        // Decrypt file
        let decryptedFile = try encryption.decrypt(
            file: encryptedFile,
            using: bob,
            passphrase: "bob-secret-pass"
        )
        defer {
            try? FileManager.default.removeItem(at: decryptedFile)
        }

        #expect(FileManager.default.fileExists(atPath: decryptedFile.path))

        let decryptedContent = try String(contentsOf: decryptedFile, encoding: .utf8)
        #expect(decryptedContent == originalContent)
    }

    @Test("Binary file round-trip")
    func testBinaryFileRoundTrip() throws {
        let (keyring, encryption, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("binary-test-\(UUID().uuidString).bin")

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

        let encryptedFile = try encryption.encrypt(file: originalFile, for: [bob], armored: false)
        defer {
            try? FileManager.default.removeItem(at: encryptedFile)
        }

        #expect(encryptedFile.pathExtension == "gpg")

        let decryptedFile = try encryption.decrypt(
            file: encryptedFile,
            using: bob,
            passphrase: "bob-secret-pass"
        )
        defer {
            try? FileManager.default.removeItem(at: decryptedFile)
        }

        let decryptedData = try Data(contentsOf: decryptedFile)
        #expect(decryptedData == binaryData)
    }

    // MARK: - Multiple Recipients Tests

    @Test("Alice encrypts for both Alice and Bob, both can decrypt")
    func testMultipleRecipientsRoundTrip() throws {
        let (keyring, encryption, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "This message is encrypted for both Alice and Bob"

        // Encrypt for both recipients
        let encrypted = try encryption.encrypt(
            message: originalMessage,
            for: [alice, bob],
            armored: true
        )

        // Both should be able to decrypt
        let aliceDecrypted = try encryption.decrypt(
            message: encrypted,
            using: alice,
            passphrase: "alice-secret-pass"
        )
        #expect(aliceDecrypted == originalMessage)

        let bobDecrypted = try encryption.decrypt(
            message: encrypted,
            using: bob,
            passphrase: "bob-secret-pass"
        )
        #expect(bobDecrypted == originalMessage)
    }

    // MARK: - Error Cases

    @Test("Wrong passphrase fails decryption")
    func testWrongPassphraseFailsDecryption() throws {
        let (keyring, encryption, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "Secret message"
        let encrypted = try encryption.encrypt(message: originalMessage, for: [bob])

        #expect(throws: OperationError.self) {
            try encryption.decrypt(message: encrypted, using: bob, passphrase: "wrong-password")
        }
    }

    @Test("Cannot decrypt with wrong recipient key")
    func testWrongRecipientFailsDecryption() throws {
        let (keyring, encryption, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "Message only for Bob"
        let encrypted = try encryption.encrypt(message: originalMessage, for: [bob])

        // Alice tries to decrypt Bob's message
        #expect(throws: OperationError.self) {
            try encryption.decrypt(message: encrypted, using: alice, passphrase: "alice-secret-pass")
        }
    }

    // MARK: - TryDecrypt Integration Test

    @Test("TryDecrypt automatically finds correct key")
    func testTryDecryptIntegration() throws {
        let (keyring, encryption, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "Message for Bob using tryDecrypt"
        let messageData = originalMessage.data(using: .utf8)!

        let encrypted = try encryption.encrypt(data: messageData, for: [bob], armored: false)

        // tryDecrypt should find Bob's key automatically
        let (decrypted, foundKey) = try encryption.tryDecrypt(
            data: encrypted,
            passphrase: "bob-secret-pass"
        )

        let decryptedMessage = String(data: decrypted, encoding: .utf8)
        #expect(decryptedMessage == originalMessage)
        #expect(foundKey.fingerprint == bob.fingerprint)
    }

    // MARK: - Armored vs Binary Format Tests

    @Test("Round-trip comparison: armored vs binary")
    func testArmoredVsBinaryRoundTrip() throws {
        let (keyring, encryption, alice, bob) = setupIntegrationEnvironment()
        defer { cleanupKeys(keyring: keyring, keys: [alice, bob]) }

        let originalMessage = "Testing armored vs binary format"

        // Encrypt with armor
        let armoredEncrypted = try encryption.encrypt(message: originalMessage, for: [bob], armored: true)
        #expect(armoredEncrypted.contains("-----BEGIN PGP MESSAGE-----"))

        // Encrypt without armor
        let binaryEncrypted = try encryption.encrypt(message: originalMessage, for: [bob], armored: false)
        #expect(!binaryEncrypted.contains("-----BEGIN PGP MESSAGE-----"))

        // Both should decrypt to the same message
        let armoredDecrypted = try encryption.decrypt(
            message: armoredEncrypted,
            using: bob,
            passphrase: "bob-secret-pass"
        )
        #expect(armoredDecrypted == originalMessage)

        // Binary format returns base64, need to decode first
        guard let binaryData = Data(base64Encoded: binaryEncrypted) else {
            throw OperationError.decryptionFailed(underlying: nil)
        }
        let binaryDecrypted = try encryption.decrypt(
            data: binaryData,
            using: bob,
            passphrase: "bob-secret-pass"
        )
        let binaryDecryptedString = String(data: binaryDecrypted, encoding: .utf8)
        #expect(binaryDecryptedString == originalMessage)
    }

    // MARK: - End-to-End Workflow Test

    @Test("Complete end-to-end workflow: generate, encrypt, decrypt")
    func testCompleteEndToEndWorkflow() throws {
        // Setup: Create fresh keyring and encryption service
        let keyring = KeyringService()
        let encryption = EncryptionService(keyringService: keyring)

        // Step 1: Generate keys for two users
        let sender = createTestKeyPair(email: "sender@example.com", passphrase: "sender123")
        let recipient = createTestKeyPair(email: "recipient@example.com", passphrase: "recipient456")

        // Step 2: Add keys to keyring
        try keyring.addKey(sender.rawKey)
        try keyring.addKey(recipient.rawKey)

        defer {
            cleanupKeys(keyring: keyring, keys: [sender, recipient])
        }

        // Step 3: Verify keys are in keyring
        let allKeys = keyring.keys
        #expect(allKeys.count >= 2)
        #expect(allKeys.contains(where: { $0.fingerprint == sender.fingerprint }))
        #expect(allKeys.contains(where: { $0.fingerprint == recipient.fingerprint }))

        // Step 4: Encrypt a message
        let secretMessage = "This is a complete end-to-end test message."
        let encryptedMessage = try encryption.encrypt(
            message: secretMessage,
            for: [recipient],
            armored: true
        )

        // Step 5: Verify encryption worked
        #expect(!encryptedMessage.isEmpty)
        #expect(encryptedMessage != secretMessage)
        #expect(encryptedMessage.contains("-----BEGIN PGP MESSAGE-----"))

        // Step 6: Decrypt the message
        let decryptedMessage = try encryption.decrypt(
            message: encryptedMessage,
            using: recipient,
            passphrase: "recipient456"
        )

        // Step 7: Verify decryption worked
        #expect(decryptedMessage == secretMessage)
    }
}
