//
//  BackupOffMainActorTests.swift
//  MacPGPTests
//
//  Verifies backup work runs off the MainActor and that a run superseded by a
//  lock does not publish success or mutate state (issue #146).
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

/// Simple async gate: `wait()` suspends until `signal()` (does not block a thread).
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// Worker that blocks (by suspension, not thread-blocking) inside `makePayload`
/// until released, so a test can observe MainActor responsiveness and supersede
/// the run before it completes.
private actor SlowBackupWorker: BackupWorking {
    let entered = AsyncGate()
    let release = AsyncGate()

    func makePayload(
        exportedData: Data,
        keyFingerprints: [String],
        useEncryption: Bool,
        name: String?,
        description: String?,
        passphrase: String,
        createdAt: Date
    ) async throws -> Data {
        await entered.signal()
        await release.wait()
        return Data("payload".utf8)
    }

    func parse(data: Data, isEncrypted: Bool, passphrase: String) async throws -> BackupParseResult {
        await entered.signal()
        await release.wait()
        return BackupParseResult(backup: .preview, keyData: Data(), checksumMissing: false)
    }
}

private final class BackupTestKeyringPersistence: KeyringPersisting {
    private var keys: [Key]
    let shouldSyncSharedContainer = false
    init(keys: [Key]) { self.keys = keys }
    func loadKeys() throws -> [Key] { keys }
    func saveKeys(_ keys: [Key]) throws { self.keys = keys }
    func importKey(from url: URL) throws -> [Key] { [] }
    func importKey(from data: Data) throws -> [Key] { [] }
    func importKey(fromArmored string: String) throws -> [Key] { [] }
    func exportKey(_ key: Key, armored: Bool) throws -> Data { try key.export() }
    func exportPublicKey(_ key: Key, armored: Bool) throws -> Data { try key.export() }
    func deleteKey(withFingerprint fingerprint: String, from keys: inout [Key]) {}
    func loadMetadata() -> KeyringMetadata { KeyringMetadata() }
    func updateVerificationStatus(forFingerprint fingerprint: String, isVerified: Bool, verificationDate: Date?, verificationMethod: String?) throws {}
    func removeVerificationStatus(forFingerprint fingerprint: String) throws {}
    func updateTrustLevel(forFingerprint fingerprint: String, trustLevel: TrustLevel, notes: String?) throws {}
    func removeTrustLevel(forFingerprint fingerprint: String) throws {}
}

@MainActor
@Suite("Backup off the MainActor")
struct BackupOffMainActorTests {

    @Test("Backup stays responsive during work and a locked run publishes nothing")
    func testResponsiveAndStaleRejection() async throws {
        let generator = KeyGenerator()
        generator.keyBitsLength = 2048
        let key = try generator.generate(for: "backup-offmain@test.local", passphrase: "p")
        let keyring = KeyringService(persistence: BackupTestKeyringPersistence(keys: [key]))

        let worker = SlowBackupWorker()
        let viewModel = BackupViewModel(keyringService: keyring, backupReminderService: nil, worker: worker)
        viewModel.selectedKeys = [key.fingerprint]
        viewModel.useEncryption = true
        viewModel.backupPassphrase = "backup-pass"
        viewModel.confirmBackupPassphrase = "backup-pass"

        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("offmain-\(UUID().uuidString).macpgpbackup")
        defer { try? FileManager.default.removeItem(at: dest) }

        let task = Task { await viewModel.createBackup(destination: dest) }

        // The worker is now suspended off the MainActor; the MainActor must be free
        // to run other work promptly.
        await worker.entered.wait()
        var markerRan = false
        await MainActor.run { markerRan = true }
        #expect(markerRan)
        #expect(viewModel.isProcessing) // still in progress

        // Supersede the run with a lock, then let the worker finish.
        viewModel.handleLock()
        await worker.release.signal()
        await task.value

        // The superseded run published no success and wrote no file; the
        // passphrase was cleared by the lock.
        #expect(viewModel.successMessage == nil)
        #expect(FileManager.default.fileExists(atPath: dest.path) == false)
        #expect(viewModel.backupPassphrase.isEmpty)
    }
}
