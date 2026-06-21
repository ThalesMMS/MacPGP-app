import Foundation
import SwiftUI
import CryptoKit

@MainActor
@Observable
final class BackupViewModel: SensitiveSessionState {
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
    var warningMessage: String?

    // Restore-specific properties
    var restoreFileURL: URL?
    var restorePassphrase: String = ""
    var validatedBackup: BackupFormat?
    var previewKeys: [String] = []
    var restoreContentsValidated = false

    private let keyringService: KeyringService
    private let backupReminderService: BackupReminderService?
    private let preferences = PreferencesManager.shared
    private let worker: BackupWorking

    /// Operation generation. Bumped at the start of each backup/restore and on
    /// lock, so only the newest run can publish state and a stale async
    /// completion (superseded run or post-lock) is rejected.
    private var lockGeneration = 0

    init(
        keyringService: KeyringService,
        backupReminderService: BackupReminderService? = nil,
        worker: BackupWorking = BackupWorker()
    ) {
        self.keyringService = keyringService
        self.backupReminderService = backupReminderService ?? BackupReminderService()
        self.worker = worker
    }

    /// Starts a new operation generation, superseding any in-flight run.
    private func beginOperation() -> Int {
        lockGeneration &+= 1
        return lockGeneration
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == lockGeneration
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
        restoreContentsValidated &&
        (!validatedBackup!.isEncrypted || !restorePassphrase.isEmpty)
    }

    // MARK: - Backup Creation

    func createBackup(destination: URL) async {
        guard isBackupValid else { return }

        let generation = beginOperation()
        isProcessing = true
        progress = 0
        errorMessage = nil
        successMessage = nil
        warningMessage = nil

        // Capture immutable inputs on the MainActor.
        let useEncryption = self.useEncryption
        let passphrase = self.backupPassphrase
        let name = backupName.isEmpty ? nil : backupName
        let description = backupDescription.isEmpty ? nil : backupDescription

        do {
            // Key export reads the keyring; keep it on the MainActor.
            let keysToBackup = try gatherKeysForBackup()
            let exportedData = try exportKeys(keysToBackup)
            let fingerprints = keysToBackup.map { $0.fingerprint }
            progress = 0.4

            // KDF (PBKDF2), AES-GCM, JSON serialization, and the file write all
            // run off the MainActor.
            let finalData = try await worker.makePayload(
                exportedData: exportedData,
                keyFingerprints: fingerprints,
                useEncryption: useEncryption,
                name: name,
                description: description,
                passphrase: passphrase,
                createdAt: Date()
            )
            guard isCurrent(generation) else { return }
            progress = 0.8

            try await Task.detached(priority: .userInitiated) {
                try SecureScopedFileAccess.writeData(finalData, to: destination, options: .atomic)
            }.value
            guard isCurrent(generation) else { return }
            progress = 1.0

            preferences.lastBackupDate = Date()
            backupReminderService?.updateReminderSchedule()

            successMessage = "Backup created successfully"
            backupPassphrase = ""
            confirmBackupPassphrase = ""
        } catch {
            guard isCurrent(generation) else { return }
            errorMessage = "Backup failed: \(error.userFacingMessage)"
        }

        guard isCurrent(generation) else { return }
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

    /// Encrypts backup `data` into the current self-describing V2 envelope
    /// (`EncryptedBackupEnvelope`). The KDF, parameters, salt, and cipher are
    /// serialized and authenticated; see `docs/BACKUP_FORMAT.md`.
    nonisolated func encryptBackup(data: Data, passphrase: String) throws -> Data {
        try EncryptedBackupEnvelope.seal(data, passphrase: passphrase, createdAt: Date())
    }

    /// Validates a backup file located at the provided URL and updates restore-related state.
    /// 
    /// If the file is detected as an encrypted backup, marks the backup as encrypted and prompts for a passphrase.
    /// If the file is unencrypted and contains valid metadata, populates `validatedBackup`, `previewKeys`, and marks the restore contents as validated.
    /// On failure sets `errorMessage`.
    /// - Parameters:
    ///   - url: File URL of the backup to validate. The file is read and its format inspected.

    func validateBackup(url: URL) async {
        let generation = beginOperation()
        isProcessing = true
        errorMessage = nil
        successMessage = nil
        warningMessage = nil
        validatedBackup = nil
        previewKeys = []
        restoreContentsValidated = false
        restoreFileURL = url

        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try SecureScopedFileAccess.readData(from: url)
            }.value
            guard isCurrent(generation) else { return }

            // Check if encrypted (legacy V1 or current V2 envelope)
            if EncryptedBackupEnvelope.isEncryptedBackup(data) {
                // Encrypted backup - we'll validate format but need passphrase to decrypt
                validatedBackup = BackupFormat(
                    keyFingerprints: [],
                    encryptionType: .aes256,
                    createdBy: "Unknown (encrypted)"
                )
                successMessage = "Encrypted backup detected. Enter passphrase to decrypt."
            } else {
                // Unencrypted backup - parse/validate off the MainActor.
                let result = try await worker.parse(data: data, isEncrypted: false, passphrase: "")
                guard isCurrent(generation) else { return }
                validatedBackup = result.backup
                previewKeys = result.backup.keyFingerprints
                restoreContentsValidated = true
                if result.checksumMissing { warningMessage = Self.checksumMissingWarning }
                successMessage = "Backup validated: \(result.backup.keyCount) key(s) found"
            }
        } catch {
            guard isCurrent(generation) else { return }
            errorMessage = "Invalid backup file: \(error.userFacingMessage)"
        }

        guard isCurrent(generation) else { return }
        isProcessing = false
    }

    private static let checksumMissingWarning = "Backup checksum is missing. This backup may be from an older MacPGP version; integrity could not be verified."

    /// Decrypts the selected backup file using the current restore passphrase and validates its metadata.
    /// 
    /// On success this updates `validatedBackup`, `previewKeys`, `restoreContentsValidated`, and `successMessage`. On failure this sets `errorMessage`. The method also manages `isProcessing` and clears prior preview/validation state at start.
    /// - Returns: `true` if decryption and metadata validation succeed, `false` otherwise.
    func decryptAndValidateBackup() async -> Bool {
        successMessage = nil
        warningMessage = nil
        validatedBackup = nil
        previewKeys = []
        restoreContentsValidated = false

        guard let restoreFileURL else {
            errorMessage = "Select a backup file first"
            return false
        }

        guard !restorePassphrase.isEmpty else {
            errorMessage = "Passphrase is required"
            return false
        }

        let generation = beginOperation()
        isProcessing = true
        errorMessage = nil

        let passphrase = restorePassphrase
        let url = restoreFileURL

        do {
            let encryptedData = try await Task.detached(priority: .userInitiated) {
                try SecureScopedFileAccess.readData(from: url)
            }.value
            guard isCurrent(generation) else { return false }

            // Decrypt (KDF/AES) and parse/validate off the MainActor.
            let result = try await worker.parse(data: encryptedData, isEncrypted: true, passphrase: passphrase)
            guard isCurrent(generation) else { return false }

            validatedBackup = result.backup
            previewKeys = result.backup.keyFingerprints
            restoreContentsValidated = true
            if result.checksumMissing { warningMessage = Self.checksumMissingWarning }
            successMessage = "Backup decrypted and validated: \(result.backup.keyCount) key(s) found"
            isProcessing = false
            return true
        } catch {
            guard isCurrent(generation) else { return false }
            errorMessage = "Unable to decrypt backup: \(error.userFacingMessage)"
            isProcessing = false
            return false
        }
    }


    // MARK: - Backup Restore

    func restoreBackup() async {
        guard isRestoreValid, let url = restoreFileURL else { return }

        let generation = beginOperation()
        isProcessing = true
        progress = 0
        errorMessage = nil
        successMessage = nil
        warningMessage = nil

        let isEncrypted = validatedBackup?.isEncrypted == true
        let passphrase = restorePassphrase

        do {
            // Read + decrypt + parse + checksum off the MainActor.
            let data = try await Task.detached(priority: .userInitiated) {
                try SecureScopedFileAccess.readData(from: url)
            }.value
            guard isCurrent(generation) else { return }
            progress = 0.3

            let result = try await worker.parse(data: data, isEncrypted: isEncrypted, passphrase: passphrase)
            guard isCurrent(generation) else { return }
            validatedBackup = result.backup
            previewKeys = result.backup.keyFingerprints
            if result.checksumMissing { warningMessage = Self.checksumMissingWarning }
            progress = 0.6

            // Keyring mutation is the final commit; perform it on the MainActor
            // only after the generation is confirmed current (a cancelled/locked
            // restore does not partially import keys).
            let importedKeys = try keyringService.importKey(from: result.keyData)
            progress = 0.8
            try keyringService.saveKeys()
            progress = 1.0

            successMessage = "Successfully restored \(importedKeys.count) key(s)"
            restorePassphrase = ""
        } catch {
            guard isCurrent(generation) else { return }
            errorMessage = "Restore failed: \(error.userFacingMessage)"
        }

        guard isCurrent(generation) else { return }
        isProcessing = false
    }

    // Backup payload serialization, parsing, and checksum verification now live
    // in BackupPayloadCodec and run off the MainActor via BackupWorker.

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
        warningMessage = nil
        progress = 0
    }

    /// Resets all restore-related inputs and validation state to their defaults.
    /// - Details: Clears the selected restore file and passphrase, removes any validated backup metadata and previewed keys, marks restore contents as not validated, clears success/error messages, and resets progress to 0.
    func resetRestore() {
        restoreFileURL = nil
        restorePassphrase = ""
        validatedBackup = nil
        previewKeys = []
        restoreContentsValidated = false
        errorMessage = nil
        successMessage = nil
        warningMessage = nil
        progress = 0
    }

    /// Clears every backup and restore passphrase field and invalidates any
    /// in-flight create/restore on **Lock MacPGP**. Persisted keyring and
    /// Keychain data are not touched.
    func handleLock() {
        lockGeneration &+= 1
        backupPassphrase = ""
        confirmBackupPassphrase = ""
        restorePassphrase = ""
        isProcessing = false
        progress = 0
    }
}
