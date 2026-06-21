//
//  CleartextSignatureTests.swift
//  MacPGPTests
//
//  Exercises librnp's native cleartext signing/verification: canonical
//  dash-escaping, line-ending handling, and the recovered-content contract
//  (issue #138).
//
//  Note: true cross-implementation fixtures (e.g. GnuPG-generated cleartext
//  signatures) must be added manually since `gpg` is not available in this
//  environment; record the generating tool/version with any such fixture.
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

private final class CleartextTestKeyringPersistence: KeyringPersisting {
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
@Suite("Cleartext signature interoperability")
struct CleartextSignatureTests {

    private static let passphrase = "cleartext-pass"

    private func makeService() -> (service: SigningService, model: PGPKeyModel) {
        let generator = KeyGenerator()
        generator.keyAlgorithm = .RSA
        generator.keyBitsLength = 2048
        let key = try! generator.generate(for: "cleartext-\(UUID().uuidString)@test.local", passphrase: Self.passphrase)
        let keyring = KeyringService(persistence: CleartextTestKeyringPersistence(keys: [key]))
        return (SigningService(keyringService: keyring), PGPKeyModel(from: key))
    }

    /// Content integrity independent of the trailing line ending and CRLF/LF.
    private func canonical(_ text: String?) -> String? {
        guard var t = text else { return nil }
        t = t.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        while t.hasSuffix("\n") { t.removeLast() }
        return t
    }

    private func sign(_ message: String, _ env: (service: SigningService, model: PGPKeyModel)) throws -> String {
        try env.service.sign(message: message, using: env.model, passphrase: Self.passphrase, cleartext: true, detached: false, armored: true)
    }

    @Test("Lines beginning with a hyphen are dash-escaped and restored")
    func testDashEscaping() throws {
        let env = makeService()
        let message = "- a line starting with a dash\nnormal line\n-another dash"

        let signed = try sign(message, env)

        // RFC 4880 §7.1 dash-escaping: a leading '-' becomes "- -".
        #expect(signed.contains("- - a line starting with a dash"))
        #expect(signed.contains("- -another dash"))

        let verified = try env.service.verify(message: signed)
        #expect(verified.isValid)
        // The recovered (unescaped) content matches the original.
        #expect(canonical(verified.originalMessage) == canonical(message))
    }

    @Test("CRLF source input verifies and recovers canonically")
    func testCRLFInput() throws {
        let env = makeService()
        let message = "line one\r\nline two\r\nline three"

        let signed = try sign(message, env)
        let verified = try env.service.verify(message: signed)

        #expect(verified.isValid)
        #expect(canonical(verified.originalMessage) == canonical(message))
    }

    @Test("LF source input verifies and recovers canonically")
    func testLFInput() throws {
        let env = makeService()
        let message = "line one\nline two\nline three"

        let signed = try sign(message, env)
        let verified = try env.service.verify(message: signed)

        #expect(verified.isValid)
        #expect(canonical(verified.originalMessage) == canonical(message))
    }

    @Test("Empty message signs and verifies")
    func testEmptyMessage() throws {
        let env = makeService()

        let signed = try sign("", env)
        #expect(signed.contains("-----BEGIN PGP SIGNED MESSAGE-----"))

        let verified = try env.service.verify(message: signed)
        #expect(verified.isValid)
    }

    @Test("Tampering the cleartext body invalidates the signature")
    func testTamperedCleartextInvalid() throws {
        let env = makeService()
        let signed = try sign("Authentic content", env)

        let tampered = signed.replacingOccurrences(of: "Authentic content", with: "Forged content")
        let verified = try env.service.verify(message: tampered)

        #expect(!verified.isValid)
        #expect(!verified.isError) // a cryptographic verdict, not an operational failure
    }

    @Test("Recovered cleartext content matches the signed content")
    func testRecoveredContentMatches() throws {
        let env = makeService()
        let signed = try sign("Hello", env)

        let verified = try env.service.verify(message: signed)
        #expect(verified.isValid)
        // The displayed original is librnp's recovered content (modulo the
        // canonical trailing line ending).
        #expect(canonical(verified.originalMessage) == "Hello")
    }

    @Test("Trailing whitespace is stripped per canonical cleartext rules")
    func testTrailingWhitespaceStripped() throws {
        let env = makeService()
        let signed = try sign("content with trailing spaces   ", env)

        let verified = try env.service.verify(message: signed)
        #expect(verified.isValid)
        // Canonical cleartext removes trailing whitespace, so the recovered
        // content no longer carries the trailing spaces.
        #expect(canonical(verified.originalMessage) == "content with trailing spaces")
    }
}
