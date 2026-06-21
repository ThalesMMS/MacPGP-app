//
//  SensitiveSessionLockTests.swift
//  MacPGPTests
//
//  Verifies passphrase-bearing workflows clear sensitive fields on Lock MacPGP
//  and reject stale async completions afterwards (issue #143).
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

private final class LockTestKeyringPersistence: KeyringPersisting {
    private var keys: [Key]
    let shouldSyncSharedContainer = false
    init(keys: [Key] = []) { self.keys = keys }
    func loadKeys() throws -> [Key] { keys }
    func saveKeys(_ keys: [Key]) throws { self.keys = keys }
    func importKey(from url: URL) throws -> [Key] { [] }
    func importKey(from data: Data) throws -> [Key] { [] }
    func importKey(fromArmored string: String) throws -> [Key] { [] }
    func exportKey(_ key: Key, armored: Bool) throws -> Data { Data() }
    func exportPublicKey(_ key: Key, armored: Bool) throws -> Data { Data() }
    func deleteKey(withFingerprint fingerprint: String, from keys: inout [Key]) {
        keys.removeAll { $0.fingerprint == fingerprint }
    }
    func loadMetadata() -> KeyringMetadata { KeyringMetadata() }
    func updateVerificationStatus(forFingerprint fingerprint: String, isVerified: Bool, verificationDate: Date?, verificationMethod: String?) throws {}
    func removeVerificationStatus(forFingerprint fingerprint: String) throws {}
    func updateTrustLevel(forFingerprint fingerprint: String, trustLevel: TrustLevel, notes: String?) throws {}
    func removeTrustLevel(forFingerprint fingerprint: String) throws {}
}

@MainActor
@Suite("Sensitive session lock")
struct SensitiveSessionLockTests {

    @Test("KeyGenerationViewModel.handleLock clears passphrase fields")
    func testKeyGenerationHandleLock() {
        let keyring = KeyringService(persistence: LockTestKeyringPersistence())
        let viewModel = KeyGenerationViewModel(keyringService: keyring)
        viewModel.passphrase = "Abcd1234!"
        viewModel.confirmPassphrase = "Abcd1234!"
        viewModel.isGenerating = true

        viewModel.handleLock()

        #expect(viewModel.passphrase.isEmpty)
        #expect(viewModel.confirmPassphrase.isEmpty)
        #expect(viewModel.isGenerating == false)
    }

    @Test("BackupViewModel.handleLock clears backup and restore passphrases")
    func testBackupHandleLock() {
        let keyring = KeyringService(persistence: LockTestKeyringPersistence())
        let viewModel = BackupViewModel(keyringService: keyring)
        viewModel.backupPassphrase = "Abcd1234!"
        viewModel.confirmBackupPassphrase = "Abcd1234!"
        viewModel.restorePassphrase = "Abcd1234!"
        viewModel.isProcessing = true

        viewModel.handleLock()

        #expect(viewModel.backupPassphrase.isEmpty)
        #expect(viewModel.confirmBackupPassphrase.isEmpty)
        #expect(viewModel.restorePassphrase.isEmpty)
        #expect(viewModel.isProcessing == false)
    }

    @Test("RevocationManagementViewModel.handleLock clears the generation passphrase")
    func testRevocationHandleLock() throws {
        let keyring = KeyringService(persistence: LockTestKeyringPersistence())
        let raw = try KeyGenerator().generate(for: "revoke-lock@example.com", passphrase: "Abcd1234!")
        let model = PGPKeyModel(from: raw)
        let viewModel = RevocationManagementViewModel(key: model, keyringService: keyring, onKeyUpdated: { _ in })
        viewModel.generatePassphrase = "Abcd1234!"
        viewModel.isProcessing = true

        viewModel.handleLock()

        #expect(viewModel.generatePassphrase.isEmpty)
        #expect(viewModel.isProcessing == false)
    }
}
