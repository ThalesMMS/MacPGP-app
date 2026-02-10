import Foundation
import SwiftUI
import CryptoKit
import CommonCrypto

@MainActor
@Observable
final class BackupViewModel {
    var selectedKeys: Set<String> = []
    var backupPassphrase: String = ""
    var confirmBackupPassphrase: String = ""
    var useEncryption: Bool = true
    var backupName: String = ""
    var backupDescription: String = ""

    var isProcessing: Bool = false
    var progress: Double = 0
    var errorMessage: String?
    var successMessage: String?

    // Restore-specific properties
    var restoreFileURL: URL?
    var restorePassphrase: String = ""
    var validatedBackup: BackupFormat?
    var previewKeys: [String] = []

    private let keyringService: KeyringService
    private let notificationService: NotificationService?
    private let backupReminderService: BackupReminderService?
    private let preferences = PreferencesManager.shared

    init(keyringService: KeyringService, notificationService: NotificationService? = nil, backupReminderService: BackupReminderService? = nil) {
        self.keyringService = keyringService
        self.notificationService = notificationService ?? NotificationService()
        self.backupReminderService = backupReminderService ?? BackupReminderService()
    }

    var availableKeys: [PGPKeyModel] {
        keyringService.secretKeys()
    }

    var isBackupValid: Bool {
        !selectedKeys.isEmpty &&
        (!useEncryption || (passphraseMatch && !backupPassphrase.isEmpty))
    }

    var passphraseMatch: Bool {
        backupPassphrase == confirmBackupPassphrase
    }

    var selectedKeyCount: Int {
        selectedKeys.count
    }

    var isRestoreValid: Bool {
        restoreFileURL != nil &&
        validatedBackup != nil &&
        (!validatedBackup!.isEncrypted || !restorePassphrase.isEmpty)
    }

    // MARK: - Backup Creation

    func createBackup(destination: URL) async {
        guard isBackupValid else { return }

        isProcessing = true
        progress = 0
        errorMessage = nil
        successMessage = nil

        do {
            // Step 1: Gather keys to backup (20%)
            let keysToBackup = try gatherKeysForBackup()
            progress = 0.2

            // Step 2: Export keys to armored format (40%)
            let exportedData = try exportKeys(keysToBackup)
            progress = 0.4

            // Step 3: Create backup format with metadata (60%)
            let backupData = try createBackupData(
                exportedData: exportedData,
                keyFingerprints: keysToBackup.map { $0.fingerprint }
            )
            progress = 0.6

            // Step 4: Encrypt if needed (80%)
            let finalData: Data
            if useEncryption {
                finalData = try encryptBackup(data: backupData, passphrase: backupPassphrase)
            } else {
                finalData = backupData
            }
            progress = 0.8

            // Step 5: Write to destination (100%)
            try finalData.write(to: destination, options: .atomic)
            progress = 1.0

            // Update last backup date and reschedule reminder
            preferences.lastBackupDate = Date()
            backupReminderService?.updateReminderSchedule()

            successMessage = "Backup created successfully"
            notificationService?.showBackupSuccess(
                title: "Backup Complete",
                message: "Successfully backed up \(selectedKeyCount) key(s)"
            )
        } catch {
            errorMessage = "Backup failed: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    private func gatherKeysForBackup() throws -> [PGPKeyModel] {
        var keys: [PGPKeyModel] = []

        for fingerprint in selectedKeys {
            guard let key = keyringService.key(withFingerprint: fingerprint) else {
                throw OperationError.keyNotFound(keyID: fingerprint)
            }
            keys.append(key)
        }

        return keys
    }

    private func exportKeys(_ keys: [PGPKeyModel]) throws -> Data {
        var exportedData = Data()

        for key in keys {
            let keyData = try keyringService.exportKey(key, includeSecretKey: true, armored: true)
            exportedData.append(keyData)
            exportedData.append("\n".data(using: .utf8)!)
        }

        return exportedData
    }

    private func createBackupData(exportedData: Data, keyFingerprints: [String]) throws -> Data {
        let backupFormat = BackupFormat(
            keyFingerprints: keyFingerprints,
            encryptionType: useEncryption ? .aes256 : .none,
            createdBy: NSFullUserName(),
            metadata: BackupMetadata(
                name: backupName.isEmpty ? nil : backupName,
                description: backupDescription.isEmpty ? nil : backupDescription
            )
        )

        // Calculate checksum of exported data
        let checksum = SHA256.hash(data: exportedData)
        let checksumString = checksum.compactMap { String(format: "%02x", $0) }.joined()
        let backupWithChecksum = backupFormat.withChecksum(checksumString)

        // Create JSON structure: metadata + keys
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        let metadataJSON = try encoder.encode(backupWithChecksum)

        // Combine metadata and key data
        var combinedData = Data()
        combinedData.append("-----BEGIN MACPGP BACKUP-----\n".data(using: .utf8)!)
        combinedData.append(metadataJSON)
        combinedData.append("\n-----END MACPGP BACKUP METADATA-----\n".data(using: .utf8)!)
        combinedData.append(exportedData)
        combinedData.append("-----END MACPGP BACKUP-----\n".data(using: .utf8)!)

        return combinedData
    }

    nonisolated func encryptBackup(data: Data, passphrase: String) throws -> Data {
        guard !passphrase.isEmpty else {
            throw OperationError.passphraseRequired
        }

        // Derive encryption key from passphrase using PBKDF2
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let key = try deriveKey(from: passphrase, salt: salt)

        // Encrypt using AES-256-GCM
        let nonce = try AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        guard let combinedData = sealedBox.combined else {
            throw OperationError.encryptionFailed(underlying: nil)
        }

        // Prepend salt and version marker
        var encryptedData = Data()
        encryptedData.append("MACPGP-ENC-V1\n".data(using: .utf8)!)
        encryptedData.append(salt)
        encryptedData.append(combinedData)

        return encryptedData
    }

    nonisolated private func deriveKey(from passphrase: String, salt: Data) throws -> SymmetricKey {
        guard let passphraseData = passphrase.data(using: .utf8) else {
            throw OperationError.invalidPassphrase
        }

        // Use PBKDF2 with 100,000 iterations for key derivation
        let iterations = 100_000
        let keyData = try Self.pbkdf2(
            password: passphraseData,
            salt: salt,
            iterations: iterations,
            keyLength: 32 // 256 bits for AES-256
        )

        return SymmetricKey(data: keyData)
    }

    nonisolated private static func pbkdf2(password: Data, salt: Data, iterations: Int, keyLength: Int) throws -> Data {
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
            throw OperationError.encryptionFailed(underlying: nil)
        }

        return derivedKey
    }

    // MARK: - Backup Validation

    func validateBackup(url: URL) async {
        isProcessing = true
        errorMessage = nil
        validatedBackup = nil
        previewKeys = []
        restoreFileURL = url

        do {
            let data = try Data(contentsOf: url)

            // Check if encrypted
            if let header = String(data: data.prefix(14), encoding: .utf8), header == "MACPGP-ENC-V1\n" {
                // Encrypted backup - we'll validate format but need passphrase to decrypt
                validatedBackup = BackupFormat(
                    keyFingerprints: [],
                    encryptionType: .aes256,
                    createdBy: "Unknown (encrypted)"
                )
                successMessage = "Encrypted backup detected. Enter passphrase to decrypt."
            } else {
                // Unencrypted backup - parse metadata
                let backup = try parseBackupMetadata(from: data)
                validatedBackup = backup
                previewKeys = backup.keyFingerprints
                successMessage = "Backup validated: \(backup.keyCount) key(s) found"
            }
        } catch {
            errorMessage = "Invalid backup file: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    private func parseBackupMetadata(from data: Data) throws -> BackupFormat {
        guard let content = String(data: data, encoding: .utf8) else {
            throw OperationError.invalidKeyData
        }

        // Extract metadata JSON between markers
        guard let metadataStart = content.range(of: "-----BEGIN MACPGP BACKUP-----\n"),
              let metadataEnd = content.range(of: "\n-----END MACPGP BACKUP METADATA-----\n") else {
            throw OperationError.invalidKeyData
        }

        let metadataString = String(content[metadataStart.upperBound..<metadataEnd.lowerBound])
        guard let metadataData = metadataString.data(using: .utf8) else {
            throw OperationError.invalidKeyData
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupFormat.self, from: metadataData)

        return backup
    }

    // MARK: - Backup Restore

    func restoreBackup() async {
        guard isRestoreValid, let url = restoreFileURL else { return }

        isProcessing = true
        progress = 0
        errorMessage = nil
        successMessage = nil

        do {
            // Step 1: Read backup file (20%)
            var data = try Data(contentsOf: url)
            progress = 0.2

            // Step 2: Decrypt if encrypted (40%)
            if validatedBackup?.isEncrypted == true {
                data = try decryptBackup(data: data, passphrase: restorePassphrase)
            }
            progress = 0.4

            // Step 3: Extract keys from backup (60%)
            let keyData = try extractKeysFromBackup(data)
            progress = 0.6

            // Step 4: Import keys (80%)
            let importedKeys = try keyringService.importKey(from: keyData)
            progress = 0.8

            // Step 5: Save keyring (100%)
            try keyringService.saveKeys()
            progress = 1.0

            successMessage = "Successfully restored \(importedKeys.count) key(s)"
            notificationService?.showRestoreSuccess(
                title: "Restore Complete",
                message: "Successfully restored \(importedKeys.count) key(s)"
            )
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    nonisolated private func decryptBackup(data: Data, passphrase: String) throws -> Data {
        guard !passphrase.isEmpty else {
            throw OperationError.passphraseRequired
        }

        // Extract header
        guard let header = String(data: data.prefix(14), encoding: .utf8), header == "MACPGP-ENC-V1\n" else {
            throw OperationError.decryptionFailed(underlying: nil)
        }

        // Extract salt (16 bytes after header)
        let headerLength = 14
        let saltLength = 16
        let salt = data.subdata(in: headerLength..<(headerLength + saltLength))

        // Extract encrypted data (everything after salt)
        let encryptedData = data.subdata(in: (headerLength + saltLength)..<data.count)

        // Derive decryption key
        let key = try deriveKey(from: passphrase, salt: salt)

        // Decrypt using AES-256-GCM
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        return decryptedData
    }

    private func extractKeysFromBackup(_ data: Data) throws -> Data {
        guard let content = String(data: data, encoding: .utf8) else {
            throw OperationError.invalidKeyData
        }

        // Extract key data between metadata and end markers
        guard let keysStart = content.range(of: "-----END MACPGP BACKUP METADATA-----\n"),
              let keysEnd = content.range(of: "-----END MACPGP BACKUP-----\n") else {
            throw OperationError.invalidKeyData
        }

        let keysString = String(content[keysStart.upperBound..<keysEnd.lowerBound])
        guard let keysData = keysString.data(using: .utf8) else {
            throw OperationError.invalidKeyData
        }

        return keysData
    }

    // MARK: - Helper Methods

    func toggleKeySelection(_ fingerprint: String) {
        if selectedKeys.contains(fingerprint) {
            selectedKeys.remove(fingerprint)
        } else {
            selectedKeys.insert(fingerprint)
        }
    }

    func selectAllKeys() {
        selectedKeys = Set(availableKeys.map { $0.fingerprint })
    }

    func deselectAllKeys() {
        selectedKeys.removeAll()
    }

    func reset() {
        selectedKeys.removeAll()
        backupPassphrase = ""
        confirmBackupPassphrase = ""
        useEncryption = true
        backupName = ""
        backupDescription = ""
        errorMessage = nil
        successMessage = nil
        progress = 0
    }

    func resetRestore() {
        restoreFileURL = nil
        restorePassphrase = ""
        validatedBackup = nil
        previewKeys = []
        errorMessage = nil
        successMessage = nil
        progress = 0
    }
}
