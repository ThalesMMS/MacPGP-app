//
//  VerificationStatusTests.swift
//  MacPGPTests
//
//  Verifies that verification outcome and signer attribution are derived from
//  librnp's verified-signature status, not throw/no-throw, packet-declared
//  issuer metadata, or localized error text (issue #137).
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

private final class StatusTestKeyringPersistence: KeyringPersisting {
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
@Suite("Verification status derivation")
struct VerificationStatusTests {

    private func makeKey(_ email: String, _ passphrase: String) -> Key {
        let generator = KeyGenerator()
        generator.keyAlgorithm = .RSA
        generator.keyBitsLength = 2048
        return try! generator.generate(for: email, passphrase: passphrase)
    }

    private func keyring(_ keys: [Key]) -> KeyringService {
        KeyringService(persistence: StatusTestKeyringPersistence(keys: keys))
    }

    // MARK: - Valid + attribution + date

    @Test("Valid signature attributes to the verified key and populates the date")
    func testValidSignatureAttribution() throws {
        let alice = makeKey("alice-status@test.local", "alice-pass")
        let service = SigningService(keyringService: keyring([alice]))

        let signed = try service.sign(data: Data("hello".utf8), using: PGPKeyModel(from: alice), passphrase: "alice-pass", detached: false, armored: false)
        let result = try service.verify(data: signed)

        #expect(result.outcome == .valid)
        #expect(result.isValid)
        #expect(result.signerKey?.fingerprint == alice.fingerprint)
        #expect(result.signatureDate != nil)
    }

    @Test("Attribution comes from the verified key, not another key in the ring")
    func testAttributionUsesVerifiedKey() throws {
        // Alice signs; both Alice and Bob are in the ring. The verified key is
        // Alice's, so the signer must be Alice — never Bob. Because attribution
        // is taken from librnp's verified key (not the packet's Issuer Key ID),
        // packet-declared metadata cannot redirect it.
        let alice = makeKey("alice-attr@test.local", "alice-pass")
        let bob = makeKey("bob-attr@test.local", "bob-pass")
        let service = SigningService(keyringService: keyring([alice, bob]))

        let signed = try service.sign(data: Data("hi".utf8), using: PGPKeyModel(from: alice), passphrase: "alice-pass", detached: false, armored: false)
        let result = try service.verify(data: signed)

        #expect(result.outcome == .valid)
        #expect(result.signerKey?.fingerprint == alice.fingerprint)
        #expect(result.signerKey?.fingerprint != bob.fingerprint)
    }

    // MARK: - Cryptographic verdicts

    @Test("Tampered content is invalid with no attributed signer")
    func testTamperedContentInvalid() throws {
        let alice = makeKey("alice-tamper@test.local", "alice-pass")
        let service = SigningService(keyringService: keyring([alice]))

        let signature = try service.sign(data: Data("original".utf8), using: PGPKeyModel(from: alice), passphrase: "alice-pass", detached: true, armored: false)
        let result = try service.verify(data: Data("tampered".utf8), signature: signature)

        #expect(result.outcome == .invalidSignature)
        #expect(!result.isValid)
        #expect(!result.isError) // cryptographic verdict, not an operational failure
        #expect(result.signerKey == nil)
    }

    @Test("A signature whose signer key is absent reports missing key")
    func testMissingKey() throws {
        let alice = makeKey("alice-missing@test.local", "alice-pass")
        let bob = makeKey("bob-missing@test.local", "bob-pass")

        // Alice signs (detached), but the verifying ring contains only Bob.
        let signService = SigningService(keyringService: keyring([alice]))
        let signature = try signService.sign(data: Data("data".utf8), using: PGPKeyModel(from: alice), passphrase: "alice-pass", detached: true, armored: false)

        let verifyService = SigningService(keyringService: keyring([bob]))
        let result = try verifyService.verify(data: Data("data".utf8), signature: signature)

        #expect(result.outcome == .missingKey)
        #expect(!result.isValid)
        #expect(result.signerKey == nil)
    }

    @Test("Multiple signatures with one verifiable and one missing key is mixed")
    func testMixedSignatures() throws {
        let alice = makeKey("alice-mixed@test.local", "alice-pass")
        let bob = makeKey("bob-mixed@test.local", "bob-pass")
        let payload = Data("multi".utf8)

        // The backend signs with a single key, so build a two-signature detached
        // blob by concatenating Alice's and Bob's detached signature packets.
        let sigAlice = try SigningService(keyringService: keyring([alice]))
            .sign(data: payload, using: PGPKeyModel(from: alice), passphrase: "alice-pass", detached: true, armored: false)
        let sigBob = try SigningService(keyringService: keyring([bob]))
            .sign(data: payload, using: PGPKeyModel(from: bob), passphrase: "bob-pass", detached: true, armored: false)
        let combined = sigAlice + sigBob

        // Verify with a ring that has Alice but not Bob: Alice's signature is
        // valid, Bob's cannot be verified -> mixed.
        let service = SigningService(keyringService: keyring([alice]))
        let result = try service.verify(data: payload, signature: combined)

        #expect(result.outcome == .mixed)
        #expect(!result.isValid)
        // The attributed signer is the one that actually verified (Alice).
        #expect(result.signerKey?.fingerprint == alice.fingerprint)
    }

    @Test("Unknown librnp status fails closed to a non-valid outcome")
    func testUnknownStatusFailsClosed() {
        // VerifiedSignature with an unrecognized code maps to .unknown, which the
        // policy treats as not valid.
        #expect(VerifiedSignature(keyID: nil, fingerprint: nil, creationDate: nil, expiresAfter: nil, statusCode: 0x7FFF_FFFF, isValid: false).status == .unknown)
    }
}
