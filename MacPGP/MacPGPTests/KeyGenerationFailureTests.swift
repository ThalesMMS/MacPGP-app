//
//  KeyGenerationFailureTests.swift
//  MacPGPTests
//
//  Verifies key generation surfaces recoverable errors instead of trapping
//  the process with preconditionFailure (issue #140).
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

private struct FakeBackendError: Error, Equatable {}

/// Minimal in-memory keyring persistence so the view-model failure path can be
/// asserted without disk I/O.
private final class FailureTestKeyringPersistence: KeyringPersisting {
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

@Suite("Key generation failure handling")
struct KeyGenerationFailureTests {

    private func failingGenerator() -> KeyGenerator {
        KeyGenerator(backend: { _, _, _, _ in throw FakeBackendError() })
    }

    // MARK: - RNPKit throwing/typed contract

    @Test("KeyGenerator.generate throws a typed error and preserves the underlying failure")
    func testGeneratorThrowsBackendFailure() {
        do {
            _ = try failingGenerator().generate(for: "x@example.com", passphrase: "pp")
            Issue.record("Expected generate() to throw")
        } catch let error as KeyGenerationError {
            guard case .backendFailure(let underlying) = error else {
                Issue.record("Expected .backendFailure, got \(error)")
                return
            }
            #expect(underlying is FakeBackendError)
        } catch {
            Issue.record("Expected KeyGenerationError, got \(error)")
        }
    }

    // MARK: - Service propagation

    @Test("KeyGenerationService.generateKey propagates the typed backend failure")
    func testServiceSyncPropagatesTypedError() {
        let service = KeyGenerationService(makeGenerator: { KeyGenerator(backend: { _, _, _, _ in throw FakeBackendError() }) })
        let params = KeyGenerationParameters(name: "T", email: "t@example.com", passphrase: "Abcd1234!", expirationMonths: nil)

        do {
            _ = try service.generateKey(with: params)
            Issue.record("Expected generateKey to throw")
        } catch is KeyGenerationError {
            // expected
        } catch {
            Issue.record("Expected KeyGenerationError, got \(error)")
        }
    }

    @Test("KeyGenerationService.generateKeyAsync maps failures to OperationError")
    func testServiceAsyncMapsToOperationError() async {
        let service = KeyGenerationService(makeGenerator: { KeyGenerator(backend: { _, _, _, _ in throw FakeBackendError() }) })
        let params = KeyGenerationParameters(name: "T", email: "t@example.com", passphrase: "Abcd1234!", expirationMonths: nil)

        do {
            _ = try await service.generateKeyAsync(with: params)
            Issue.record("Expected generateKeyAsync to throw")
        } catch let error as OperationError {
            guard case .keyGenerationFailed = error else {
                Issue.record("Expected .keyGenerationFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected OperationError, got \(error)")
        }
    }

    // MARK: - View model failure path

    @MainActor
    @Test("Failed generation resets state and does not persist a key or passphrase")
    func testViewModelFailureDoesNotPersist() async {
        let keyring = KeyringService(persistence: FailureTestKeyringPersistence())
        let failingService = KeyGenerationService(makeGenerator: { KeyGenerator(backend: { _, _, _, _ in throw FakeBackendError() }) })
        let viewModel = KeyGenerationViewModel(keyringService: keyring, generationService: failingService)

        viewModel.name = "Test User"
        viewModel.email = "test@example.com"
        viewModel.passphrase = "Abcd1234!"
        viewModel.confirmPassphrase = "Abcd1234!"
        viewModel.storeInKeychain = true

        await viewModel.generate()

        #expect(viewModel.isGenerating == false)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.generatedKey == nil)
        #expect(keyring.keys.isEmpty)
    }
}
