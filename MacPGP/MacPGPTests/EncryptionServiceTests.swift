//
//  EncryptionServiceTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 04/02/26.
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

nonisolated private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func append(_ value: Double) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var snapshot: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

nonisolated private func waitForSemaphore(
    _ semaphore: DispatchSemaphore,
    timeout: DispatchTime
) -> DispatchTimeoutResult {
    semaphore.wait(timeout: timeout)
}

@MainActor
@Suite("EncryptionService Tests")
struct EncryptionServiceTests {

    // MARK: - Test Helpers

    func makeIsolatedKeyring() -> KeyringService {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncryptionServiceTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Keyring", isDirectory: true)

        return KeyringService(persistence: KeyringPersistence(directoryOverride: directory))
    }

    func createTestKeyPair(email: String, passphrase: String) -> PGPKeyModel {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: email, passphrase: passphrase)
        return PGPKeyModel(from: key)
    }

    func setupTestEnvironment() -> (service: EncryptionService, keyring: KeyringService, recipientKey: PGPKeyModel, senderKey: PGPKeyModel) {
        let keyring = makeIsolatedKeyring()

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
        let keyring = makeIsolatedKeyring()
        let service = EncryptionService(keyringService: keyring)

        let testData = "Test".data(using: .utf8)!

        #expect(throws: OperationError.self) {
            try service.encrypt(data: testData, for: [])
        }
    }

    @Test("Encrypt data throws error with invalid recipient")
    func testEncryptDataInvalidRecipient() {
        let keyring = makeIsolatedKeyring()
        let service = EncryptionService(keyringService: keyring)

        let fakeKey = createTestKeyPair(email: "fake@test.local", passphrase: "pass")
        let testData = "Test".data(using: .utf8)!

        #expect(throws: OperationError.self) {
            try service.encrypt(data: testData, for: [fakeKey])
        }
    }

    @Test("Encrypt data rejects a recipient currently marked never trusted")
    func testEncryptDataRejectsNeverTrustedRecipient() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        try keyring.updateTrustLevel(recipientKey, trustLevel: .never)
        let staleRecipient = PGPKeyModel(copying: recipientKey, trustLevel: .unknown)
        let testData = "Test".data(using: .utf8)!

        do {
            _ = try service.encrypt(data: testData, for: [staleRecipient])
            Issue.record("Expected encryption to reject a never-trusted recipient")
        } catch let error as OperationError {
            guard case .recipientKeyUntrusted(let keyID) = error else {
                Issue.record("Expected OperationError.recipientKeyUntrusted, got \(error)")
                return
            }

            #expect(keyID == recipientKey.shortKeyID)
        } catch {
            Issue.record("Expected OperationError.recipientKeyUntrusted, got \(error)")
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

    @Test("Encrypt file uses selected directory as output folder")
    func testEncryptFileDirectoryOutput() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let outputDirectory = tempDir.appendingPathComponent("encrypt-output-\(UUID().uuidString)", isDirectory: true)
        let testFile = tempDir.appendingPathComponent("test-directory-output-\(UUID().uuidString).txt")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try "Folder output test".write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        let outputFile = try service.encrypt(
            file: testFile,
            for: [recipientKey],
            outputURL: outputDirectory,
            armored: false
        )

        #expect(outputFile.deletingLastPathComponent() == outputDirectory)
        #expect(FileManager.default.fileExists(atPath: outputFile.path))
        #expect(outputFile.lastPathComponent.contains(testFile.lastPathComponent))
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
        let keyring = makeIsolatedKeyring()
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

        try FileManager.default.removeItem(at: originalFile)

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

        try FileManager.default.removeItem(at: originalFile)

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

    @Test("Decrypt file refuses to overwrite existing default output")
    func testDecryptFileRefusesExistingDefaultOutput() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("decrypt-existing-\(UUID().uuidString).txt")
        let originalContent = "Original decrypt content"
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

        let existingContent = "Existing user file"
        try existingContent.write(to: originalFile, atomically: true, encoding: .utf8)

        var didRefuseOverwrite = false
        do {
            _ = try service.decrypt(
                file: encryptedFile,
                using: recipientKey,
                passphrase: "recipient-pass"
            )
        } catch {
            didRefuseOverwrite = true
        }

        #expect(didRefuseOverwrite)
        #expect(try String(contentsOf: originalFile, encoding: .utf8) == existingContent)
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

    @Test("TryDecrypt file uses matching key and writes into selected directory")
    func testTryDecryptFileToDirectoryOutput() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let outputDirectory = tempDir.appendingPathComponent("decrypt-output-\(UUID().uuidString)", isDirectory: true)
        let originalFile = tempDir.appendingPathComponent("try-decrypt-\(UUID().uuidString).txt")
        let originalContent = "Decrypt into a selected folder"
        try originalContent.write(to: originalFile, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: originalFile)
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        let encryptedFile = try service.encrypt(file: originalFile, for: [recipientKey], armored: false)
        defer { try? FileManager.default.removeItem(at: encryptedFile) }

        let (decryptedFile, foundKey) = try service.tryDecrypt(
            file: encryptedFile,
            passphrase: "recipient-pass",
            outputURL: outputDirectory
        )

        #expect(foundKey.fingerprint == recipientKey.fingerprint)
        #expect(decryptedFile.deletingLastPathComponent() == outputDirectory)
        #expect(FileManager.default.fileExists(atPath: decryptedFile.path))
        let decryptedContent = try String(contentsOf: decryptedFile, encoding: .utf8)
        #expect(decryptedContent == originalContent)
    }

    @Test("TryDecrypt reports invalid passphrase when matching key rejects passphrase")
    func testTryDecryptInvalidPassphrase() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let originalData = "No valid key".data(using: .utf8)!

        let encryptedData = try service.encrypt(
            data: originalData,
            for: [recipientKey],
            armored: false
        )

        do {
            _ = try service.tryDecrypt(data: encryptedData, passphrase: "wrong-passphrase")
            Issue.record("Expected invalid passphrase")
        } catch OperationError.invalidPassphrase {
        } catch {
            Issue.record("Expected OperationError.invalidPassphrase, got \(error)")
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

        try FileManager.default.removeItem(at: originalFile)

        let decrypted = try service.decrypt(file: encrypted, using: recipientKey, passphrase: "recipient-pass")
        defer { try? FileManager.default.removeItem(at: decrypted) }

        let decryptedContent = try String(contentsOf: decrypted, encoding: .utf8)
        #expect(decryptedContent == originalContent)
    }

    @Test("Multiple recipients can decrypt same message")
    func testMultipleRecipients() throws {
        let keyring = makeIsolatedKeyring()
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
        // 0.7 is reported after the streamed output is written, before the (fast)
        // atomic promotion, so observers are not left stalled during the write.
        #expect(progressValues.contains(0.7))
        // File-mode crypto streams via librnp; progress is monotonic and only
        // reaches 1.0 after the output is durably written.
        for index in 0..<max(progressValues.count - 1, 0) {
            #expect(progressValues[index] <= progressValues[index + 1])
        }
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

        try FileManager.default.removeItem(at: originalFile)

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
        // 0.7 is reported after the streamed output is written, before the (fast)
        // atomic promotion, so observers are not left stalled during the write.
        #expect(progressValues.contains(0.7))
        // File-mode crypto streams via librnp; progress is monotonic and only
        // reaches 1.0 after the output is durably written.
        for index in 0..<max(progressValues.count - 1, 0) {
            #expect(progressValues[index] <= progressValues[index + 1])
        }

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

        #expect(progressValues.count >= 3)
        #expect(progressValues.first == 0.0)
        #expect(progressValues.last == 1.0)

        for i in 0..<progressValues.count - 1 {
            #expect(progressValues[i] <= progressValues[i + 1])
        }
    }

    @Test("Streaming round trip preserves armored file content")
    func testStreamingRoundTripArmored() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let original = tempDir.appendingPathComponent("stream-\(UUID().uuidString).bin")
        let content = Data((0..<(64 * 1024)).map { UInt8($0 & 0xFF) })
        try content.write(to: original)
        defer { try? FileManager.default.removeItem(at: original) }

        let encrypted = try service.encrypt(file: original, for: [recipientKey], armored: true)
        defer { try? FileManager.default.removeItem(at: encrypted) }
        #expect(encrypted.pathExtension == "asc")
        let armored = try Data(contentsOf: encrypted)
        #expect(String(data: armored.prefix(40), encoding: .utf8)?.contains("BEGIN PGP MESSAGE") == true)

        // Decrypt to an explicit fresh path so it does not collide with the still
        // present original (whose name the default derivation would reproduce).
        let decryptedOut = tempDir.appendingPathComponent("stream-dec-\(UUID().uuidString).bin")
        let decrypted = try service.decrypt(file: encrypted, using: recipientKey, passphrase: "recipient-pass", outputURL: decryptedOut)
        defer { try? FileManager.default.removeItem(at: decrypted) }
        #expect(try Data(contentsOf: decrypted) == content)
    }

    @Test("File encryption never overwrites an existing destination")
    func testEncryptDoesNotOverwriteExistingDestination() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let original = tempDir.appendingPathComponent("ow-\(UUID().uuidString).bin")
        try Data(repeating: 0x01, count: 4096).write(to: original)
        defer { try? FileManager.default.removeItem(at: original) }

        let first = try service.encrypt(file: original, for: [recipientKey], armored: false)
        defer { try? FileManager.default.removeItem(at: first) }
        let before = try Data(contentsOf: first)

        // Re-encrypting resolves to the same destination, which now exists.
        #expect(throws: (any Error).self) {
            _ = try service.encrypt(file: original, for: [recipientKey], armored: false)
        }
        #expect(try Data(contentsOf: first) == before)
    }

    @Test("Failed decryption leaves no partial or temp output")
    func testDecryptFailureLeavesNoPartialOutput() throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let original = tempDir.appendingPathComponent("fail-src-\(UUID().uuidString).bin")
        try Data(repeating: 0x09, count: 4096).write(to: original)
        defer { try? FileManager.default.removeItem(at: original) }

        let encrypted = try service.encrypt(file: original, for: [recipientKey], armored: false)
        defer { try? FileManager.default.removeItem(at: encrypted) }

        let outputDir = tempDir.appendingPathComponent("fail-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let output = outputDir.appendingPathComponent("out.dat")

        #expect(throws: (any Error).self) {
            _ = try service.decrypt(file: encrypted, using: recipientKey, passphrase: "WRONG-PASSPHRASE", outputURL: output)
        }
        // No final output, and no leftover temporary .part file.
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: outputDir.path)) ?? []
        #expect(remaining.isEmpty)
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

        let progressRecorder = ProgressRecorder()

        let outputFile = try await service.encryptAsync(
            file: testFile,
            for: [recipientKey],
            armored: false,
            progressCallback: { progress in
                progressRecorder.append(progress)
            }
        )

        defer {
            try? FileManager.default.removeItem(at: outputFile)
        }

        #expect(FileManager.default.fileExists(atPath: outputFile.path))
        let progressValues = progressRecorder.snapshot
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

        let progressRecorder = ProgressRecorder()

        try FileManager.default.removeItem(at: originalFile)

        let decryptedFile = try await service.decryptAsync(
            file: encryptedFile,
            using: recipientKey,
            passphrase: "recipient-pass",
            progressCallback: { progress in
                progressRecorder.append(progress)
            }
        )

        defer {
            try? FileManager.default.removeItem(at: decryptedFile)
        }

        #expect(FileManager.default.fileExists(atPath: decryptedFile.path))
        let progressValues = progressRecorder.snapshot
        #expect(!progressValues.isEmpty)
        #expect(progressValues.contains(0.0))
        #expect(progressValues.contains(1.0))

        let decryptedData = try Data(contentsOf: decryptedFile)
        #expect(decryptedData == largeData)
    }

    @Test("Try decrypt async uses key snapshot when keyring changes during file decrypt")
    func testTryDecryptAsyncUsesSnapshotWhenKeyringChangesDuringFileDecrypt() async throws {
        let (service, keyring, recipientKey, senderKey) = setupTestEnvironment()
        defer { cleanupTestKeys(keyring: keyring, keys: [recipientKey, senderKey]) }

        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("snapshot-decrypt-\(UUID().uuidString).txt")
        let outputDirectory = tempDir.appendingPathComponent("snapshot-decrypt-output-\(UUID().uuidString)", isDirectory: true)
        let originalContent = "Decrypt from the snapshot captured before the detached task reaches the keyring."
        try originalContent.write(to: originalFile, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: originalFile)
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        let encryptedFile = try service.encrypt(
            file: originalFile,
            for: [recipientKey],
            armored: false
        )

        defer {
            try? FileManager.default.removeItem(at: encryptedFile)
        }

        let deletionCompleted = DispatchSemaphore(value: 0)
        let (decryptedFile, decryptingKey) = try await service.tryDecryptAsync(
            file: encryptedFile,
            passphrase: "recipient-pass",
            outputURL: outputDirectory,
            progressCallback: { progress in
                if progress == 0.3 {
                    Task { @MainActor in
                        try? keyring.deleteKey(recipientKey)
                        deletionCompleted.signal()
                    }
                }
            }
        )

        let deletionResult = await Task.detached {
            waitForSemaphore(deletionCompleted, timeout: .now() + 5)
        }.value
        #expect(deletionResult == .success)
        #expect(keyring.key(withFingerprint: recipientKey.fingerprint) == nil)
        #expect(decryptingKey.fingerprint == recipientKey.fingerprint)
        #expect(try String(contentsOf: decryptedFile, encoding: .utf8) == originalContent)
    }

}
