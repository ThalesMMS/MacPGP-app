//
//  KeyExpirationClockTests.swift
//  MacPGPTests
//
//  Verifies that key expiration is recomputed against the current time at the
//  operation boundary (issue #147) rather than cached when the model is built.
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

private final class ClockTestBundleToken: NSObject {}

/// Pattern-match `ExpirationWarningLevel` without its `Equatable` witness, which
/// is main-actor-isolated under the project's default isolation.
private func isLevel(_ actual: ExpirationWarningLevel, _ expected: ExpirationWarningLevel) -> Bool {
    switch (actual, expected) {
    case (.none, .none), (.warning, .warning), (.critical, .critical), (.expired, .expired):
        return true
    default:
        return false
    }
}

/// Controllable clock so expiration boundaries can be crossed deterministically.
private final class MutableDateProvider: DateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ now: Date) { current = now }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock(); current += interval; lock.unlock()
    }
}

/// Minimal in-memory keyring persistence returning a fixed key set so the
/// service-level expiration filtering can be exercised without disk I/O.
private final class InMemoryKeyringPersistence: KeyringPersisting {
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
@Suite("Key expiration clock recomputation")
struct KeyExpirationClockTests {

    private func makeSecretKey(expiringAt expiration: Date) throws -> Key {
        let passphrase = "TestPassword123!"
        let generator = KeyGenerator()
        generator.keyAlgorithm = .RSA
        generator.keyBitsLength = 2048
        let key = try! generator.generate(
            for: "expiration-clock-\(UUID().uuidString)@example.com",
            passphrase: passphrase
        )
        return try key.setExpiration(expiration, passphraseForKey: { _ in passphrase })
    }

    // MARK: - Required regression scenario (#147)

    @Test("Key valid one second before expiry becomes expired after the clock advances")
    func testModelExpiresWhenClockCrossesBoundary() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let base = try makeSecretKey(expiringAt: now.addingTimeInterval(3600))
        // Override expiration to one second after `now` without recreating the model.
        let model = PGPKeyModel(copying: PGPKeyModel(from: base), expirationDate: now.addingTimeInterval(1))

        // 1. Initially selectable.
        #expect(model.isExpired(asOf: now) == false)
        #expect(model.isUsableForEncryption(asOf: now) == true)
        #expect(model.isUsableForSigning(asOf: now) == true)
        #expect(isLevel(model.expirationWarningLevel(asOf: now), .critical))

        // 2. Advance the clock beyond the boundary on the same model instance.
        let later = now.addingTimeInterval(2)

        #expect(model.isExpired(asOf: later) == true)
        #expect(model.isUsableForEncryption(asOf: later) == false)
        #expect(model.isUsableForSigning(asOf: later) == false)
        #expect(isLevel(model.expirationWarningLevel(asOf: later), .expired))
    }

    @Test("Inclusive boundary: a key is expired at exactly its expiration instant")
    func testInclusiveBoundary() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let base = try makeSecretKey(expiringAt: now.addingTimeInterval(3600))
        let model = PGPKeyModel(copying: PGPKeyModel(from: base), expirationDate: now)

        #expect(model.isExpired(asOf: now) == true)
        #expect(model.isExpired(asOf: now.addingTimeInterval(-1)) == false)
    }

    @Test("Key without expiration never expires")
    func testNoExpirationNeverExpires() throws {
        // The EdDSA fixture has no expiration date (generated keys carry librnp's
        // default expiration, so a fixture is used for the no-expiration case).
        let bundle = Bundle(for: ClockTestBundleToken.self)
        guard let url = bundle.url(forResource: "eddsa_testkey", withExtension: "asc", subdirectory: "Resources")
            ?? bundle.url(forResource: "eddsa_testkey", withExtension: "asc") else {
            Issue.record("Missing eddsa_testkey fixture")
            return
        }
        let keys = try RNP.readKeys(from: Data(contentsOf: url))
        guard let raw = keys.first else {
            Issue.record("Empty eddsa_testkey fixture")
            return
        }
        let model = PGPKeyModel(from: raw)

        #expect(model.expirationDate == nil)
        #expect(model.isExpired(asOf: Date(timeIntervalSince1970: 4_000_000_000)) == false)
        #expect(model.daysUntilExpiration(asOf: Date()) == nil)
    }

    // MARK: - Service validation uses the injected clock

    @Test("TrustService validation flips when the clock crosses the boundary")
    func testTrustServiceUsesClock() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = MutableDateProvider(now)
        let keyringService = KeyringService(persistence: InMemoryKeyringPersistence(keys: []))
        let trustService = TrustService(keyringService: keyringService, clock: clock)

        let base = try makeSecretKey(expiringAt: now.addingTimeInterval(3600))
        // Fully trusted so the only warning under test is expiration.
        let trusted = PGPKeyModel(
            from: base,
            isVerified: true,
            verificationDate: now,
            verificationMethod: .trusted,
            trustLevel: .full
        )
        let model = PGPKeyModel(copying: trusted, expirationDate: now.addingTimeInterval(1))

        #expect(trustService.isKeyValidForEncryption(model) == true)
        #expect(trustService.getTrustWarning(for: model) == nil)

        clock.advance(by: 2)

        #expect(trustService.isKeyValidForEncryption(model) == false)
        #expect(trustService.getTrustWarning(for: model)?.contains("expired") == true)
    }

    @Test("EncryptionService rejects a recipient that expires while the app is open")
    func testEncryptionServiceRejectsExpiredRecipient() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = MutableDateProvider(now)
        let keyringService = KeyringService(persistence: InMemoryKeyringPersistence(keys: []))
        let encryptionService = EncryptionService(keyringService: keyringService, clock: clock)

        let base = try makeSecretKey(expiringAt: now.addingTimeInterval(3600))
        let recipient = PGPKeyModel(copying: PGPKeyModel(from: base), expirationDate: now.addingTimeInterval(1))

        clock.advance(by: 2)

        do {
            _ = try encryptionService.encrypt(data: Data("hello".utf8), for: [recipient])
            Issue.record("Expected encryption to reject the expired recipient")
        } catch let error as OperationError {
            guard case .keyExpired = error else {
                Issue.record("Expected .keyExpired, got \(error)")
                return
            }
        }
    }

    // MARK: - Picker filtering uses the injected time (keyring level)

    @Test("KeyringService.publicKeys/signingKeys filter by the supplied instant")
    func testKeyringFilteringUsesSuppliedInstant() throws {
        let now = Date()
        let expiring = try makeSecretKey(expiringAt: now.addingTimeInterval(3600))
        let keyringService = KeyringService(persistence: InMemoryKeyringPersistence(keys: [expiring]))

        let fingerprint = expiring.fingerprint

        // Before expiry the key is offered for encryption and signing.
        #expect(keyringService.publicKeys(asOf: now).contains { $0.fingerprint == fingerprint })
        #expect(keyringService.signingKeys(asOf: now).contains { $0.fingerprint == fingerprint })

        // Two hours later it is filtered out without reloading the keyring.
        let later = now.addingTimeInterval(7200)
        #expect(keyringService.publicKeys(asOf: later).contains { $0.fingerprint == fingerprint } == false)
        #expect(keyringService.signingKeys(asOf: later).contains { $0.fingerprint == fingerprint } == false)
    }
}
