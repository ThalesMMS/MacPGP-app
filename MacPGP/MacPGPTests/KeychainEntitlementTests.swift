//
//  KeychainEntitlementTests.swift
//  MacPGPTests
//
//  Verifies new passphrase writes fail closed (rather than silently creating a
//  legacy login-keychain item) when the Data Protection Keychain entitlement is
//  missing, while legacy read/migration still work (issue #145).
//

import Foundation
import Security
import Testing
@testable import MacPGP

/// Records calls and lets a test choose the status returned for each Keychain op.
private final class FakeSecItemClient: SecItemClient, @unchecked Sendable {
    struct AddCall { let usesDataProtection: Bool }

    private let lock = NSLock()
    private var _addCalls: [AddCall] = []
    private let addStatus: @Sendable (_ usesDataProtection: Bool) -> OSStatus

    init(addStatus: @escaping @Sendable (_ usesDataProtection: Bool) -> OSStatus) {
        self.addStatus = addStatus
    }

    var addCalls: [AddCall] {
        lock.lock(); defer { lock.unlock() }
        return _addCalls
    }

    private func usesDataProtection(_ query: CFDictionary) -> Bool {
        let dict = query as NSDictionary
        return (dict[kSecUseDataProtectionKeychain as String] as? Bool) == true
    }

    func add(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        let dp = usesDataProtection(attributes)
        lock.lock(); _addCalls.append(AddCall(usesDataProtection: dp)); lock.unlock()
        return addStatus(dp)
    }

    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        errSecItemNotFound
    }

    func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
        errSecSuccess
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        errSecItemNotFound
    }
}

@Suite("Keychain entitlement fail-closed")
struct KeychainEntitlementTests {

    @Test("New production write fails closed when the Data Protection Keychain entitlement is missing")
    func testNewWriteFailsClosedWithoutLegacyFallback() {
        // Production mode: legacy fallback disabled; DP add reports a missing entitlement.
        let fake = FakeSecItemClient { _ in errSecMissingEntitlement }
        let manager = KeychainManager(
            serviceName: "test-fail-closed-\(UUID().uuidString)",
            secItem: fake,
            allowsLegacyFallbackForNewWrites: false
        )

        do {
            try manager.storePassphrase("secret", forKeyID: "key-\(UUID().uuidString)")
            Issue.record("Expected storePassphrase to fail closed")
        } catch let error as OperationError {
            guard case .keychainEntitlementMissing = error else {
                Issue.record("Expected .keychainEntitlementMissing, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected OperationError, got \(error)")
        }

        // The data-protection add was attempted exactly once; no legacy item was created.
        #expect(fake.addCalls.count == 1)
        #expect(fake.addCalls.allSatisfy { $0.usesDataProtection })
        #expect(fake.addCalls.contains { !$0.usesDataProtection } == false)
    }

    @Test("Missing-entitlement error has actionable copy that does not imply storage succeeded")
    func testEntitlementErrorCopy() {
        let error = OperationError.keychainEntitlementMissing
        let description = error.errorDescription ?? ""
        #expect(!description.isEmpty)
        #expect(description.lowercased().contains("not saved") || description.lowercased().contains("unavailable"))
        #expect((error.recoverySuggestion ?? "").isEmpty == false)
    }

    @Test("Test/development environments still fall back to the legacy keychain")
    func testDevelopmentFallbackStillWrites() throws {
        // DP add reports missing entitlement; legacy add succeeds.
        let fake = FakeSecItemClient { usesDataProtection in
            usesDataProtection ? errSecMissingEntitlement : errSecSuccess
        }
        let manager = KeychainManager(
            serviceName: "test-dev-fallback-\(UUID().uuidString)",
            secItem: fake,
            allowsLegacyFallbackForNewWrites: true
        )

        try manager.storePassphrase("secret", forKeyID: "key-\(UUID().uuidString)")

        // Both a data-protection attempt and a legacy fallback write occurred.
        #expect(fake.addCalls.contains { $0.usesDataProtection })
        #expect(fake.addCalls.contains { !$0.usesDataProtection })
    }

    @Test("The default policy enables the legacy fallback under XCTest")
    func testDefaultPolicyUnderTests() {
        // Tests run under XCTest, so the default keeps the legacy fallback enabled
        // (otherwise unsigned CI/dev builds could not store passphrases at all).
        #expect(KeychainManager.defaultAllowsLegacyFallbackForNewWrites == true)
    }
}
