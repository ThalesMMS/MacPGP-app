//
//  TrustServiceTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 10/02/26.
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

@Suite("TrustService Tests")
struct TrustServiceTests {

    // MARK: - Helper Methods

    /// Create a mock key model with specified trust level
    private func createMockKey(
        email: String,
        trustLevel: TrustLevel,
        isSecret: Bool = false,
        isExpired: Bool = false,
        isRevoked: Bool = false
    ) -> PGPKeyModel {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let rawKey = keyGen.generate(for: email, passphrase: "test")

        let key = PGPKeyModel(
            from: rawKey,
            isVerified: trustLevel != .unknown,
            verificationDate: trustLevel != .unknown ? Date() : nil,
            verificationMethod: trustLevel != .unknown ? .trusted : nil,
            trustLevel: trustLevel
        )

        if isExpired || isRevoked {
            return PGPKeyModel(copying: key, isExpired: isExpired, isRevoked: isRevoked)
        }

        return key
    }

    // MARK: - Helper Method Tests

    @Test("Get certifying keys filters by trust level")
    func testGetCertifyingKeys() {
        let keyringService = KeyringService()
        let trustService = TrustService(keyringService: keyringService)

        let certifyingKeys = trustService.getCertifyingKeys()

        // Certifying keys must have full or ultimate trust
        for key in certifyingKeys {
            #expect(key.trustLevel == .full || key.trustLevel == .ultimate)
        }

        // All certifying keys should have canCertify == true
        for key in certifyingKeys {
            #expect(key.trustLevel.canCertify == true)
        }
    }

    @Test("Is key valid for encryption - valid key")
    func testIsKeyValidForEncryptionValid() {
        let keyringService = KeyringService()
        let trustService = TrustService(keyringService: keyringService)

        let validKey = createMockKey(email: "valid@test.com", trustLevel: .full)

        let isValid = trustService.isKeyValidForEncryption(validKey)

        #expect(isValid == true)
    }

    @Test("Is key valid for encryption - never trust key")
    func testIsKeyValidForEncryptionNever() {
        let keyringService = KeyringService()
        let trustService = TrustService(keyringService: keyringService)

        let neverKey = createMockKey(email: "never@test.com", trustLevel: .never)

        let isValid = trustService.isKeyValidForEncryption(neverKey)

        #expect(isValid == false)
    }

    @Test("Is key valid for encryption - expired key")
    func testIsKeyValidForEncryptionExpired() {
        let keyringService = KeyringService()
        let trustService = TrustService(keyringService: keyringService)

        let expiredKey = createMockKey(email: "expired@test.com", trustLevel: .full, isExpired: true)

        let isValid = trustService.isKeyValidForEncryption(expiredKey)

        #expect(isValid == false)
    }

    @Test("Is key valid for encryption - revoked key")
    func testIsKeyValidForEncryptionRevoked() {
        let keyringService = KeyringService()
        let trustService = TrustService(keyringService: keyringService)

        let revokedKey = createMockKey(email: "revoked@test.com", trustLevel: .full, isRevoked: true)

        let isValid = trustService.isKeyValidForEncryption(revokedKey)

        #expect(isValid == false)
    }

    @Test("Is key valid for encryption - unknown trust key is still valid")
    func testIsKeyValidForEncryptionUnknown() {
        let keyringService = KeyringService()
        let trustService = TrustService(keyringService: keyringService)

        let unknownKey = createMockKey(email: "unknown@test.com", trustLevel: .unknown)

        let isValid = trustService.isKeyValidForEncryption(unknownKey)

        // Unknown trust keys are still valid for encryption
        #expect(isValid == true)
    }

    @Test("Get trust warning for never-trusted key")
    func testGetTrustWarningNever() {
        let keyringService = KeyringService()
        let trustService = TrustService(keyringService: keyringService)

        let neverKey = createMockKey(email: "never@test.com", trustLevel: .never)

        let warning = trustService.getTrustWarning(for: neverKey)

        #expect(warning != nil)
        #expect(warning?.contains("Never Trust") == true)
    }

    @Test("Get trust warning for unknown key")
    func testGetTrustWarningUnknown() {
        let keyringService = KeyringService()
        let trustService = TrustService(keyringService: keyringService)

        let unknownKey = createMockKey(email: "unknown@test.com", trustLevel: .unknown)

        let warning = trustService.getTrustWarning(for: unknownKey)

        #expect(warning != nil)
        #expect(warning?.contains("unknown trust level") == true)
    }

    @Test("Get trust warning for expired key")
    func testGetTrustWarningExpired() {
        let keyringService = KeyringService()
        let trustService = TrustService(keyringService: keyringService)

        let expiredKey = createMockKey(email: "expired@test.com", trustLevel: .full, isExpired: true)

        let warning = trustService.getTrustWarning(for: expiredKey)

        #expect(warning != nil)
        #expect(warning?.contains("expired") == true)
    }

    @Test("Get trust warning for revoked key")
    func testGetTrustWarningRevoked() {
        let keyringService = KeyringService()
        let trustService = TrustService(keyringService: keyringService)

        let revokedKey = createMockKey(email: "revoked@test.com", trustLevel: .full, isRevoked: true)

        let warning = trustService.getTrustWarning(for: revokedKey)

        #expect(warning != nil)
        #expect(warning?.contains("revoked") == true)
    }

    @Test("Get trust warning returns nil for fully trusted key")
    func testGetTrustWarningNone() {
        let keyringService = KeyringService()
        let trustService = TrustService(keyringService: keyringService)

        let ultimateKey = createMockKey(email: "ultimate@test.com", trustLevel: .ultimate, isSecret: true)

        let warning = trustService.getTrustWarning(for: ultimateKey)

        #expect(warning == nil)
    }
}
