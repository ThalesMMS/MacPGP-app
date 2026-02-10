//
//  BackupServiceTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 10/02/26.
//

import Testing
import Foundation
import ObjectivePGP
@testable import MacPGP

@Suite("BackupService Tests")
struct BackupServiceTests {

    // MARK: - Encryption/Decryption Tests

    @Test("Encrypt backup creates encrypted data")
    @MainActor
    func testEncryptBackup() async throws {
        let keyringService = KeyringService()
        let viewModel = BackupViewModel(keyringService: keyringService, notificationService: nil, backupReminderService: nil)

        let testData = "Test backup data".data(using: .utf8)!
        let passphrase = "test123"

        let encryptedData = try viewModel.encryptBackup(data: testData, passphrase: passphrase)

        #expect(!encryptedData.isEmpty)
        #expect(encryptedData != testData)

        // Verify encryption header
        if let header = String(data: encryptedData.prefix(14), encoding: .utf8) {
            #expect(header == "MACPGP-ENC-V1\n")
        }
    }

    @Test("Encrypt backup throws error with empty passphrase")
    @MainActor
    func testEncryptBackupEmptyPassphrase() async throws {
        let keyringService = KeyringService()
        let viewModel = BackupViewModel(keyringService: keyringService, notificationService: nil, backupReminderService: nil)

        let testData = "Test backup data".data(using: .utf8)!

        #expect(throws: OperationError.self) {
            try viewModel.encryptBackup(data: testData, passphrase: "")
        }
    }

    // MARK: - Validation Tests

    @Test("Validate unencrypted backup")
    @MainActor
    func testValidateUnencryptedBackup() async throws {
        let keyringService = KeyringService()
        let viewModel = BackupViewModel(keyringService: keyringService, notificationService: nil, backupReminderService: nil)

        // Create a test backup file
        let tempDir = FileManager.default.temporaryDirectory
        let backupFile = tempDir.appendingPathComponent(UUID().uuidString + ".macpgp")

        let backupFormat = BackupFormat(
            keyFingerprints: ["ABC123DEF456"],
            encryptionType: .none,
            createdBy: "test@example.com"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let metadataJSON = try encoder.encode(backupFormat)

        var backupData = Data()
        backupData.append("-----BEGIN MACPGP BACKUP-----\n".data(using: .utf8)!)
        backupData.append(metadataJSON)
        backupData.append("\n-----END MACPGP BACKUP METADATA-----\n".data(using: .utf8)!)
        backupData.append("Test key data".data(using: .utf8)!)
        backupData.append("-----END MACPGP BACKUP-----\n".data(using: .utf8)!)

        try backupData.write(to: backupFile)

        // Validate backup
        await viewModel.validateBackup(url: backupFile)

        #expect(!viewModel.isProcessing)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.validatedBackup != nil)
        #expect(viewModel.validatedBackup?.isEncrypted == false)
        #expect(viewModel.previewKeys.count == 1)
        #expect(viewModel.previewKeys.first == "ABC123DEF456")

        // Cleanup
        try? FileManager.default.removeItem(at: backupFile)
    }

    @Test("Validate encrypted backup")
    @MainActor
    func testValidateEncryptedBackup() async throws {
        let keyringService = KeyringService()
        let viewModel = BackupViewModel(keyringService: keyringService, notificationService: nil, backupReminderService: nil)

        // Create an encrypted test backup file
        let tempDir = FileManager.default.temporaryDirectory
        let backupFile = tempDir.appendingPathComponent(UUID().uuidString + ".macpgp")

        let testData = "Test encrypted backup".data(using: .utf8)!
        let encryptedData = try viewModel.encryptBackup(data: testData, passphrase: "test123")

        try encryptedData.write(to: backupFile)

        // Validate backup
        await viewModel.validateBackup(url: backupFile)

        #expect(!viewModel.isProcessing)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.validatedBackup != nil)
        #expect(viewModel.validatedBackup?.isEncrypted == true)
        #expect(viewModel.successMessage?.contains("Encrypted backup detected") == true)

        // Cleanup
        try? FileManager.default.removeItem(at: backupFile)
    }

    @Test("Validate invalid backup file")
    @MainActor
    func testValidateInvalidBackup() async throws {
        let keyringService = KeyringService()
        let viewModel = BackupViewModel(keyringService: keyringService, notificationService: nil, backupReminderService: nil)

        // Create an invalid backup file
        let tempDir = FileManager.default.temporaryDirectory
        let backupFile = tempDir.appendingPathComponent(UUID().uuidString + ".macpgp")

        let invalidData = "This is not a valid backup file".data(using: .utf8)!
        try invalidData.write(to: backupFile)

        // Validate backup
        await viewModel.validateBackup(url: backupFile)

        #expect(!viewModel.isProcessing)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.validatedBackup == nil)

        // Cleanup
        try? FileManager.default.removeItem(at: backupFile)
    }

    // MARK: - Integration Tests

    @Test("Create unencrypted backup workflow")
    @MainActor
    func testCreateUnencryptedBackup() async throws {
        let keyringService = KeyringService()
        let viewModel = BackupViewModel(keyringService: keyringService, notificationService: nil, backupReminderService: nil)

        // Clean up any test keys
        let existingKeys = keyringService.keys.filter { $0.email == "test-backup@example.com" }
        for key in existingKeys {
            try? keyringService.deleteKey(key)
        }

        // Create a test key
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let testKey = keyGen.generate(for: "test-backup@example.com", passphrase: "test")
        try keyringService.addKey(testKey)

        guard let addedKey = keyringService.keys.first(where: { $0.email == "test-backup@example.com" }) else {
            Issue.record("Test key not found")
            return
        }

        // Configure backup
        viewModel.toggleKeySelection(addedKey.fingerprint)
        viewModel.useEncryption = false

        let isValid = viewModel.isBackupValid
        #expect(isValid == true)

        // Create backup
        let tempDir = FileManager.default.temporaryDirectory
        let backupFile = tempDir.appendingPathComponent(UUID().uuidString + ".macpgp")

        await viewModel.createBackup(destination: backupFile)

        #expect(!viewModel.isProcessing)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.successMessage != nil)
        #expect(FileManager.default.fileExists(atPath: backupFile.path))

        // Verify backup content
        let backupData = try Data(contentsOf: backupFile)
        let backupString = String(data: backupData, encoding: .utf8)!
        #expect(backupString.contains("-----BEGIN MACPGP BACKUP-----"))
        #expect(backupString.contains("-----END MACPGP BACKUP-----"))

        // Cleanup
        try? FileManager.default.removeItem(at: backupFile)
        try? keyringService.deleteKey(addedKey)
    }

    @Test("Create encrypted backup workflow")
    @MainActor
    func testCreateEncryptedBackup() async throws {
        let keyringService = KeyringService()
        let viewModel = BackupViewModel(keyringService: keyringService, notificationService: nil, backupReminderService: nil)

        // Clean up any test keys
        let existingKeys = keyringService.keys.filter { $0.email == "test-encrypted@example.com" }
        for key in existingKeys {
            try? keyringService.deleteKey(key)
        }

        // Create a test key
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let testKey = keyGen.generate(for: "test-encrypted@example.com", passphrase: "test")
        try keyringService.addKey(testKey)

        guard let addedKey = keyringService.keys.first(where: { $0.email == "test-encrypted@example.com" }) else {
            Issue.record("Test key not found")
            return
        }

        // Configure backup with encryption
        viewModel.toggleKeySelection(addedKey.fingerprint)
        viewModel.useEncryption = true
        viewModel.backupPassphrase = "backup123"
        viewModel.confirmBackupPassphrase = "backup123"

        let isValid = viewModel.isBackupValid
        #expect(isValid == true)

        // Create backup
        let tempDir = FileManager.default.temporaryDirectory
        let backupFile = tempDir.appendingPathComponent(UUID().uuidString + ".macpgp")

        await viewModel.createBackup(destination: backupFile)

        #expect(!viewModel.isProcessing)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.successMessage != nil)
        #expect(FileManager.default.fileExists(atPath: backupFile.path))

        // Verify backup is encrypted
        let backupData = try Data(contentsOf: backupFile)
        if let header = String(data: backupData.prefix(14), encoding: .utf8) {
            #expect(header == "MACPGP-ENC-V1\n")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: backupFile)
        try? keyringService.deleteKey(addedKey)
    }
}
