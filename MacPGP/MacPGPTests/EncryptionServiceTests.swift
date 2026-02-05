//
//  EncryptionServiceTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 04/02/26.
//

import Testing
import Foundation
import ObjectivePGP
@testable import MacPGP

@Suite("EncryptionService Tests")
struct EncryptionServiceTests {

    // MARK: - Test Helpers

    func createTestKeyPair(email: String, passphrase: String) -> PGPKeyModel {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: email, passphrase: passphrase)
        return PGPKeyModel(from: key)
    }

    func setupTestEnvironment() -> (service: EncryptionService, keyring: KeyringService, recipientKey: PGPKeyModel, senderKey: PGPKeyModel) {
        let keyring = KeyringService()

        let recipientKey = createTestKeyPair(email: "recipient@test.local", passphrase: "recipient-pass")
        let senderKey = createTestKeyPair(email: "sender@test.local", passphrase: "sender-pass")

        try? keyring.addKey(recipientKey.rawKey)
        try? keyring.addKey(senderKey.rawKey)

        let service = EncryptionService(keyringService: keyring)

        return (service, keyring, recipientKey, senderKey)
    }

    func cleanupTestKeys(keyring: KeyringService, keys: [PGPKeyModel]) {
        for key in keys {
            try? keyring.deleteKey(key)
        }
    }

    // MARK: - Data Encryption Tests

    @Test("Encrypt data successfully")
    func testEncryptData() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let testData = "Hello, World!".data(using: .utf8)!

        let encryptedData = try service.encrypt(
            data: testData,
            for: [recipientKey],
            armored: true
        )

        #expect(!encryptedData.isEmpty)
        #expect(encryptedData != testData)

        if let armoredString = String(data: encryptedData, encoding: .utf8) {
            #expect(armoredString.contains("-----BEGIN PGP MESSAGE-----"))
        }
    }

    @Test("Encrypt data without armor")
    func testEncryptDataBinary() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let testData = "Binary test".data(using: .utf8)!

        let encryptedData = try service.encrypt(
            data: testData,
            for: [recipientKey],
            armored: false
        )

        #expect(!encryptedData.isEmpty)
        #expect(encryptedData != testData)

        let dataString = String(data: encryptedData, encoding: .utf8)
        #expect(dataString == nil || !dataString!.contains("-----BEGIN PGP"))
    }


    @Test("Encrypt data throws error with empty recipients")
    func testEncryptDataEmptyRecipients() {
        let keyring = KeyringService()
        let service = EncryptionService(keyringService: keyring)

        let testData = "Test".data(using: .utf8)!

        #expect(throws: OperationError.self) {
            try service.encrypt(data: testData, for: [])
        }
    }

    @Test("Encrypt data throws error with invalid recipient")
    func testEncryptDataInvalidRecipient() {
        let keyring = KeyringService()
        let service = EncryptionService(keyringService: keyring)

        let fakeKey = createTestKeyPair(email: "fake@test.local", passphrase: "pass")
        let testData = "Test".data(using: .utf8)!

        #expect(throws: OperationError.self) {
            try service.encrypt(data: testData, for: [fakeKey])
        }
    }


    // MARK: - Message Encryption Tests

    @Test("Encrypt message successfully")
    func testEncryptMessage() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let testMessage = "Secret message"

        let encryptedMessage = try service.encrypt(
            message: testMessage,
            for: [recipientKey],
            armored: true
        )

        #expect(!encryptedMessage.isEmpty)
        #expect(encryptedMessage != testMessage)
        #expect(encryptedMessage.contains("-----BEGIN PGP MESSAGE-----"))
    }

    @Test("Encrypt message without armor returns base64")
    func testEncryptMessageBinary() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let testMessage = "Binary message"

        let encryptedMessage = try service.encrypt(
            message: testMessage,
            for: [recipientKey],
            armored: false
        )

        #expect(!encryptedMessage.isEmpty)
        #expect(!encryptedMessage.contains("-----BEGIN PGP"))

        // Should be base64 encoded
        let decoded = Data(base64Encoded: encryptedMessage)
        #expect(decoded != nil)
    }


    // MARK: - File Encryption Tests

    @Test("Encrypt file successfully")
    func testEncryptFile() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-encrypt-\(UUID().uuidString).txt")
        let testContent = "File content to encrypt"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let outputFile = try service.encrypt(
            file: testFile,
            for: [recipientKey],
            armored: false
        )

        defer {
            try? FileManager.default.removeItem(at: outputFile)
        }

        #expect(FileManager.default.fileExists(atPath: outputFile.path))
        #expect(outputFile.pathExtension == "gpg")

        let encryptedData = try Data(contentsOf: outputFile)
        let originalData = try Data(contentsOf: testFile)
        #expect(encryptedData != originalData)
    }

    @Test("Encrypt file with armor")
    func testEncryptFileArmored() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-armor-\(UUID().uuidString).txt")
        let testContent = "Armored file content"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let outputFile = try service.encrypt(
            file: testFile,
            for: [recipientKey],
            armored: true
        )

        defer {
            try? FileManager.default.removeItem(at: outputFile)
        }

        #expect(FileManager.default.fileExists(atPath: outputFile.path))
        #expect(outputFile.pathExtension == "asc")

        let encryptedContent = try String(contentsOf: outputFile, encoding: .utf8)
        #expect(encryptedContent.contains("-----BEGIN PGP MESSAGE-----"))
    }

    @Test("Encrypt file with custom output path")
    func testEncryptFileCustomOutput() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-custom-\(UUID().uuidString).txt")
        let customOutput = tempDir.appendingPathComponent("custom-output-\(UUID().uuidString).encrypted")
        let testContent = "Custom output test"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
            try? FileManager.default.removeItem(at: customOutput)
        }

        let outputFile = try service.encrypt(
            file: testFile,
            for: [recipientKey],
            outputURL: customOutput,
            armored: false
        )

        #expect(outputFile == customOutput)
        #expect(FileManager.default.fileExists(atPath: outputFile.path))
    }


    // MARK: - Data Decryption Tests

    @Test("Decrypt data successfully")
    func testDecryptData() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let originalData = "Decrypt me!".data(using: .utf8)!

        let encryptedData = try service.encrypt(
            data: originalData,
            for: [recipientKey],
            armored: false
        )

        let decryptedData = try service.decrypt(
            data: encryptedData,
            using: recipientKey,
            passphrase: "recipient-pass"
        )

        #expect(decryptedData == originalData)
    }

    @Test("Decrypt armored data successfully")
    func testDecryptArmoredData() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let originalData = "Decrypt armored!".data(using: .utf8)!

        let encryptedData = try service.encrypt(
            data: originalData,
            for: [recipientKey],
            armored: true
        )

        let decryptedData = try service.decrypt(
            data: encryptedData,
            using: recipientKey,
            passphrase: "recipient-pass"
        )

        #expect(decryptedData == originalData)
    }

    @Test("Decrypt data throws error with wrong passphrase")
    func testDecryptDataWrongPassphrase() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let originalData = "Secret".data(using: .utf8)!

        let encryptedData = try service.encrypt(
            data: originalData,
            for: [recipientKey],
            armored: false
        )

        #expect(throws: OperationError.self) {
            try service.decrypt(
                data: encryptedData,
                using: recipientKey,
                passphrase: "wrong-passphrase"
            )
        }
    }

    @Test("Decrypt data throws error with missing key")
    func testDecryptDataMissingKey() throws {
        let keyring = KeyringService()
        let service = EncryptionService(keyringService: keyring)

        let recipientKey = createTestKeyPair(email: "temp@test.local", passphrase: "pass")
        try keyring.addKey(recipientKey.rawKey)

        let originalData = "Data".data(using: .utf8)!
        let encryptedData = try service.encrypt(data: originalData, for: [recipientKey], armored: false)

        try keyring.deleteKey(recipientKey)

        #expect(throws: OperationError.self) {
            try service.decrypt(
                data: encryptedData,
                using: recipientKey,
                passphrase: "pass"
            )
        }
    }


    // MARK: - Message Decryption Tests

    @Test("Decrypt message successfully")
    func testDecryptMessage() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let originalMessage = "Secret message to decrypt"

        let encryptedMessage = try service.encrypt(
            message: originalMessage,
            for: [recipientKey],
            armored: true
        )

        let decryptedMessage = try service.decrypt(
            message: encryptedMessage,
            using: recipientKey,
            passphrase: "recipient-pass"
        )

        #expect(decryptedMessage == originalMessage)
    }


    @Test("Decrypt message with wrong passphrase throws error")
    func testDecryptMessageWrongPassphrase() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let originalMessage = "Protected message"

        let encryptedMessage = try service.encrypt(
            message: originalMessage,
            for: [recipientKey],
            armored: true
        )

        #expect(throws: OperationError.self) {
            try service.decrypt(
                message: encryptedMessage,
                using: recipientKey,
                passphrase: "incorrect"
            )
        }
    }

    // MARK: - File Decryption Tests

    @Test("Decrypt file successfully")
    func testDecryptFile() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("decrypt-original-\(UUID().uuidString).txt")
        let originalContent = "File content to decrypt"
        try originalContent.write(to: originalFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: originalFile)
        }

        let encryptedFile = try service.encrypt(
            file: originalFile,
            for: [recipientKey],
            armored: false
        )

        defer {
            try? FileManager.default.removeItem(at: encryptedFile)
        }

        let decryptedFile = try service.decrypt(
            file: encryptedFile,
            using: recipientKey,
            passphrase: "recipient-pass"
        )

        defer {
            try? FileManager.default.removeItem(at: decryptedFile)
        }

        #expect(FileManager.default.fileExists(atPath: decryptedFile.path))

        let decryptedContent = try String(contentsOf: decryptedFile, encoding: .utf8)
        #expect(decryptedContent == originalContent)
    }

    @Test("Decrypt armored file successfully")
    func testDecryptArmoredFile() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("decrypt-armored-\(UUID().uuidString).txt")
        let originalContent = "Armored file content"
        try originalContent.write(to: originalFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: originalFile)
        }

        let encryptedFile = try service.encrypt(
            file: originalFile,
            for: [recipientKey],
            armored: true
        )

        defer {
            try? FileManager.default.removeItem(at: encryptedFile)
        }

        #expect(encryptedFile.pathExtension == "asc")

        let decryptedFile = try service.decrypt(
            file: encryptedFile,
            using: recipientKey,
            passphrase: "recipient-pass"
        )

        defer {
            try? FileManager.default.removeItem(at: decryptedFile)
        }

        let decryptedContent = try String(contentsOf: decryptedFile, encoding: .utf8)
        #expect(decryptedContent == originalContent)
    }

    @Test("Decrypt file with custom output")
    func testDecryptFileCustomOutput() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("custom-decrypt-\(UUID().uuidString).txt")
        let customOutput = tempDir.appendingPathComponent("custom-decrypted-\(UUID().uuidString).txt")
        let originalContent = "Custom decrypt output"
        try originalContent.write(to: originalFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: originalFile)
            try? FileManager.default.removeItem(at: customOutput)
        }

        let encryptedFile = try service.encrypt(
            file: originalFile,
            for: [recipientKey],
            armored: false
        )

        defer {
            try? FileManager.default.removeItem(at: encryptedFile)
        }

        let decryptedFile = try service.decrypt(
            file: encryptedFile,
            using: recipientKey,
            passphrase: "recipient-pass",
            outputURL: customOutput
        )

        #expect(decryptedFile == customOutput)
        #expect(FileManager.default.fileExists(atPath: decryptedFile.path))

        let decryptedContent = try String(contentsOf: decryptedFile, encoding: .utf8)
        #expect(decryptedContent == originalContent)
    }

    @Test("Decrypt file with wrong passphrase throws error")
    func testDecryptFileWrongPassphrase() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("wrong-pass-\(UUID().uuidString).txt")
        let originalContent = "Protected file"
        try originalContent.write(to: originalFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: originalFile)
        }

        let encryptedFile = try service.encrypt(
            file: originalFile,
            for: [recipientKey],
            armored: false
        )

        defer {
            try? FileManager.default.removeItem(at: encryptedFile)
        }

        #expect(throws: OperationError.self) {
            try service.decrypt(
                file: encryptedFile,
                using: recipientKey,
                passphrase: "wrong-pass"
            )
        }
    }

    // MARK: - TryDecrypt Tests

    @Test("TryDecrypt finds correct key and decrypts")
    func testTryDecrypt() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let originalData = "Try decrypt test".data(using: .utf8)!

        let encryptedData = try service.encrypt(
            data: originalData,
            for: [recipientKey],
            armored: false
        )

        let (decryptedData, foundKey) = try service.tryDecrypt(
            data: encryptedData,
            passphrase: "recipient-pass"
        )

        #expect(decryptedData == originalData)
        #expect(foundKey.fingerprint == recipientKey.fingerprint)
    }

    @Test("TryDecrypt throws error when no key works")
    func testTryDecryptNoValidKey() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let originalData = "No valid key".data(using: .utf8)!

        let encryptedData = try service.encrypt(
            data: originalData,
            for: [recipientKey],
            armored: false
        )

        #expect(throws: OperationError.self) {
            try service.tryDecrypt(data: encryptedData, passphrase: "wrong-passphrase")
        }
    }

    // MARK: - Round-trip Integration Tests

    @Test("Full encrypt-decrypt round trip for data")
    func testDataRoundTrip() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let originalData = "Round trip test data 🔐".data(using: .utf8)!

        let encrypted = try service.encrypt(data: originalData, for: [recipientKey])
        let decrypted = try service.decrypt(data: encrypted, using: recipientKey, passphrase: "recipient-pass")

        #expect(decrypted == originalData)
    }

    @Test("Full encrypt-decrypt round trip for message")
    func testMessageRoundTrip() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let originalMessage = "Round trip message with emoji 🚀"

        let encrypted = try service.encrypt(message: originalMessage, for: [recipientKey])
        let decrypted = try service.decrypt(message: encrypted, using: recipientKey, passphrase: "recipient-pass")

        #expect(decrypted == originalMessage)
    }

    @Test("Full encrypt-decrypt round trip for file")
    func testFileRoundTrip() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("roundtrip-\(UUID().uuidString).txt")
        let originalContent = "File round trip test 📁"
        try originalContent.write(to: originalFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: originalFile)
        }

        let encrypted = try service.encrypt(file: originalFile, for: [recipientKey], armored: true)
        defer { try? FileManager.default.removeItem(at: encrypted) }

        let decrypted = try service.decrypt(file: encrypted, using: recipientKey, passphrase: "recipient-pass")
        defer { try? FileManager.default.removeItem(at: decrypted) }

        let decryptedContent = try String(contentsOf: decrypted, encoding: .utf8)
        #expect(decryptedContent == originalContent)
    }

    @Test("Multiple recipients can decrypt same message")
    func testMultipleRecipients() throws {
        let keyring = KeyringService()
        let service = EncryptionService(keyringService: keyring)

        let recipient1 = createTestKeyPair(email: "recipient1@test.local", passphrase: "pass1")
        let recipient2 = createTestKeyPair(email: "recipient2@test.local", passphrase: "pass2")

        try keyring.addKey(recipient1.rawKey)
        try keyring.addKey(recipient2.rawKey)

        defer {
            cleanupTestKeys(keyring: keyring, keys: [recipient1, recipient2])
        }

        let originalMessage = "Message for multiple recipients"

        let encrypted = try service.encrypt(
            message: originalMessage,
            for: [recipient1, recipient2],
            armored: true
        )

        let decrypted1 = try service.decrypt(message: encrypted, using: recipient1, passphrase: "pass1")
        let decrypted2 = try service.decrypt(message: encrypted, using: recipient2, passphrase: "pass2")

        #expect(decrypted1 == originalMessage)
        #expect(decrypted2 == originalMessage)
    }

    // MARK: - Large File Encryption with Progress Tracking

    @Test("Encrypt large file with progress tracking")
    func testEncryptLargeFileWithProgress() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("large-file-\(UUID().uuidString).dat")

        let largeData = Data(repeating: 0x42, count: 1024 * 1024)
        try largeData.write(to: testFile)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        var progressValues: [Double] = []

        let outputFile = try service.encrypt(
            file: testFile,
            for: [recipientKey],
            armored: false,
            progressCallback: { progress in
                progressValues.append(progress)
            }
        )

        defer {
            try? FileManager.default.removeItem(at: outputFile)
        }

        #expect(FileManager.default.fileExists(atPath: outputFile.path))
        #expect(!progressValues.isEmpty)
        #expect(progressValues.first == 0.0)
        #expect(progressValues.last == 1.0)
        #expect(progressValues.contains(0.3))
        #expect(progressValues.contains(0.7))
    }

    @Test("Decrypt large file with progress tracking")
    func testDecryptLargeFileWithProgress() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("decrypt-large-\(UUID().uuidString).dat")

        let largeData = Data(repeating: 0x77, count: 1024 * 1024)
        try largeData.write(to: originalFile)

        defer {
            try? FileManager.default.removeItem(at: originalFile)
        }

        let encryptedFile = try service.encrypt(
            file: originalFile,
            for: [recipientKey],
            armored: false
        )

        defer {
            try? FileManager.default.removeItem(at: encryptedFile)
        }

        var progressValues: [Double] = []

        let decryptedFile = try service.decrypt(
            file: encryptedFile,
            using: recipientKey,
            passphrase: "recipient-pass",
            progressCallback: { progress in
                progressValues.append(progress)
            }
        )

        defer {
            try? FileManager.default.removeItem(at: decryptedFile)
        }

        #expect(FileManager.default.fileExists(atPath: decryptedFile.path))
        #expect(!progressValues.isEmpty)
        #expect(progressValues.first == 0.0)
        #expect(progressValues.last == 1.0)
        #expect(progressValues.contains(0.3))
        #expect(progressValues.contains(0.7))

        let decryptedData = try Data(contentsOf: decryptedFile)
        #expect(decryptedData == largeData)
    }

    @Test("Progress values are reported in correct order")
    func testProgressValuesInOrder() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("progress-order-\(UUID().uuidString).dat")

        let testData = Data(repeating: 0xAB, count: 512 * 1024)
        try testData.write(to: testFile)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        var progressValues: [Double] = []

        let outputFile = try service.encrypt(
            file: testFile,
            for: [recipientKey],
            armored: false,
            progressCallback: { progress in
                progressValues.append(progress)
            }
        )

        defer {
            try? FileManager.default.removeItem(at: outputFile)
        }

        #expect(progressValues.count >= 4)

        for i in 0..<progressValues.count - 1 {
            #expect(progressValues[i] <= progressValues[i + 1])
        }
    }

    @Test("Async encrypt large file with progress tracking")
    func testAsyncEncryptLargeFileWithProgress() async throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("async-large-\(UUID().uuidString).dat")

        let largeData = Data(repeating: 0xCD, count: 1024 * 1024)
        try largeData.write(to: testFile)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        var progressValues: [Double] = []

        let outputFile = try await service.encryptAsync(
            file: testFile,
            for: [recipientKey],
            armored: false,
            progressCallback: { progress in
                progressValues.append(progress)
            }
        )

        defer {
            try? FileManager.default.removeItem(at: outputFile)
        }

        #expect(FileManager.default.fileExists(atPath: outputFile.path))
        #expect(!progressValues.isEmpty)
        #expect(progressValues.contains(0.0))
        #expect(progressValues.contains(1.0))
    }

    @Test("Async decrypt large file with progress tracking")
    func testAsyncDecryptLargeFileWithProgress() async throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("async-decrypt-large-\(UUID().uuidString).dat")

        let largeData = Data(repeating: 0xEF, count: 1024 * 1024)
        try largeData.write(to: originalFile)

        defer {
            try? FileManager.default.removeItem(at: originalFile)
        }

        let encryptedFile = try service.encrypt(
            file: originalFile,
            for: [recipientKey],
            armored: false
        )

        defer {
            try? FileManager.default.removeItem(at: encryptedFile)
        }

        var progressValues: [Double] = []

        let decryptedFile = try await service.decryptAsync(
            file: encryptedFile,
            using: recipientKey,
            passphrase: "recipient-pass",
            progressCallback: { progress in
                progressValues.append(progress)
            }
        )

        defer {
            try? FileManager.default.removeItem(at: decryptedFile)
        }

        #expect(FileManager.default.fileExists(atPath: decryptedFile.path))
        #expect(!progressValues.isEmpty)
        #expect(progressValues.contains(0.0))
        #expect(progressValues.contains(1.0))

        let decryptedData = try Data(contentsOf: decryptedFile)
        #expect(decryptedData == largeData)
    }

}
