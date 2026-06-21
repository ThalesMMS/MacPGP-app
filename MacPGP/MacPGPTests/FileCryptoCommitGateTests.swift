//
//  FileCryptoCommitGateTests.swift
//  MacPGPTests
//
//  Verifies that file crypto outputs are not promoted after a cancel or Lock
//  MacPGP that occurred while the blocking backend was still running (issue
//  #141): the authorization gate is re-checked immediately before atomic
//  promotion, the temporary file is removed, and pre-existing destinations are
//  never modified.
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

private final class GateTestKeyringPersistence: KeyringPersisting {
    private var keys: [Key]
    let shouldSyncSharedContainer = false
    init(keys: [Key]) { self.keys = keys }
    func loadKeys() throws -> [Key] { keys }
    func saveKeys(_ keys: [Key]) throws { self.keys = keys }
    func importKey(from url: URL) throws -> [Key] { [] }
    func importKey(from data: Data) throws -> [Key] { [] }
    func importKey(fromArmored string: String) throws -> [Key] { [] }
    func exportKey(_ key: Key, armored: Bool) throws -> Data { Data() }
    func exportPublicKey(_ key: Key, armored: Bool) throws -> Data { Data() }
    func deleteKey(withFingerprint fingerprint: String, from keys: inout [Key]) {}
    func loadMetadata() -> KeyringMetadata { KeyringMetadata() }
    func updateVerificationStatus(forFingerprint fingerprint: String, isVerified: Bool, verificationDate: Date?, verificationMethod: String?) throws {}
    func removeVerificationStatus(forFingerprint fingerprint: String) throws {}
    func updateTrustLevel(forFingerprint fingerprint: String, trustLevel: TrustLevel, notes: String?) throws {}
    func removeTrustLevel(forFingerprint fingerprint: String) throws {}
}

@MainActor
@Suite("File crypto commit gate")
struct FileCryptoCommitGateTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macpgp-commit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Primitive: blocking backend cancelled before commit

    @Test("Output is not promoted and the temp file is removed when the gate is invalidated mid-write")
    func testGateBlocksPromotionMidWrite() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("out.txt")

        let gate = FileCommitGate()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var caught: Error?

        // Run the (blocking) write off the test thread, like the backend would.
        DispatchQueue.global().async {
            do {
                try SecureScopedFileAccess.writeFileWithoutOverwriting(
                    finalOutput: output,
                    scopedBy: nil,
                    canCommit: { gate.isAuthorized }
                ) { tempPath in
                    // Simulate librnp writing the output to the temp file, then
                    // blocking (still "running") until the test releases it.
                    FileManager.default.createFile(atPath: tempPath, contents: Data("decrypted-payload".utf8))
                    entered.signal()
                    release.wait()
                }
            } catch {
                caught = error
            }
            done.signal()
        }

        entered.wait()        // backend has written the temp file
        gate.invalidate()     // user cancels or locks while it was running
        release.signal()      // backend returns
        done.wait()

        #expect(caught is SecureScopedFileAccess.CommitCancelledError)
        #expect(FileManager.default.fileExists(atPath: output.path) == false)
        // No leftover .part temp files.
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        #expect(leftovers.contains { $0.hasSuffix(".part") } == false)
    }

    @Test("An authorized gate promotes the output normally")
    func testAuthorizedGatePromotes() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("ok.txt")

        try SecureScopedFileAccess.writeFileWithoutOverwriting(finalOutput: output, scopedBy: nil) { tempPath in
            FileManager.default.createFile(atPath: tempPath, contents: Data("payload".utf8))
        }

        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test("A pre-existing destination is never modified when the gate blocks the commit")
    func testPreExistingDestinationPreserved() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("existing.txt")
        FileManager.default.createFile(atPath: output.path, contents: Data("ORIGINAL".utf8))

        let gate = FileCommitGate()
        gate.invalidate()

        #expect(throws: SecureScopedFileAccess.CommitCancelledError.self) {
            try SecureScopedFileAccess.writeFileWithoutOverwriting(
                finalOutput: output,
                scopedBy: nil,
                overwrite: true,
                canCommit: { gate.isAuthorized }
            ) { tempPath in
                FileManager.default.createFile(atPath: tempPath, contents: Data("NEW".utf8))
            }
        }

        let contents = try String(contentsOf: output, encoding: .utf8)
        #expect(contents == "ORIGINAL")
    }

    // MARK: - Service paths

    private func makeKey() throws -> Key {
        let generator = KeyGenerator()
        generator.keyAlgorithm = .RSA
        generator.keyBitsLength = 2048
        return try generator.generate(for: "commit-gate-\(UUID().uuidString)@test.local", passphrase: "p")
    }

    @Test("Encrypt does not leave output when the gate is already invalidated")
    func testEncryptGateBlocksOutput() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("plain.txt")
        FileManager.default.createFile(atPath: input.path, contents: Data("hello".utf8))

        let key = try makeKey()
        let service = EncryptionService(keyringService: KeyringService(persistence: GateTestKeyringPersistence(keys: [key])))
        let recipient = PGPKeyModel(from: key)
        let gate = FileCommitGate()
        gate.invalidate()

        let expectedOutput = input.appendingPathExtension("gpg")
        await #expect(throws: SecureScopedFileAccess.CommitCancelledError.self) {
            _ = try await service.encryptAsync(file: input, for: [recipient], outputURL: nil, armored: false, commitGate: gate)
        }
        #expect(FileManager.default.fileExists(atPath: expectedOutput.path) == false)
    }

    @Test("Auto-detect decrypt leaves no plaintext when the gate is already invalidated")
    func testDecryptGateBlocksPlaintext() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("secret.txt")
        FileManager.default.createFile(atPath: input.path, contents: Data("top secret".utf8))

        let key = try makeKey()
        let service = EncryptionService(keyringService: KeyringService(persistence: GateTestKeyringPersistence(keys: [key])))
        let recipient = PGPKeyModel(from: key)

        // Encrypt (authorized) into a separate directory so the decrypted output
        // cannot collide with the original input file.
        let cipherDir = try tempDir()
        defer { try? FileManager.default.removeItem(at: cipherDir) }
        let encrypted = try await service.encryptAsync(file: input, for: [recipient], outputURL: cipherDir, armored: false, commitGate: FileCommitGate())

        // Snapshot the directory, then decrypt with a pre-invalidated gate: the
        // cancelled decrypt must add no plaintext (and leave no temp) file.
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: cipherDir.path)) ?? [])
        let gate = FileCommitGate()
        gate.invalidate()
        await #expect(throws: SecureScopedFileAccess.CommitCancelledError.self) {
            _ = try await service.tryDecryptAsync(file: encrypted, passphrase: "p", outputURL: cipherDir, commitGate: gate)
        }
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: cipherDir.path)) ?? [])
        #expect(after == before)
    }
}
