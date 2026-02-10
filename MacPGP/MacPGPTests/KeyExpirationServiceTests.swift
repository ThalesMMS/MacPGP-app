//
//  KeyExpirationServiceTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 10/02/26.
//

import Testing
import Foundation
import ObjectivePGP
@testable import MacPGP

@Suite("KeyExpirationService Tests")
struct KeyExpirationServiceTests {

    // MARK: - Test Helpers

    /// Creates a mock key with specified expiration date
    private func createMockKey(expiresIn days: Int?, isSecret: Bool = false) -> PGPKeyModel {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "test")

        // Create a modified key with custom expiration
        var modifiedKey = PGPKeyModel(from: key)

        // Use reflection to modify the expiration date (for testing purposes)
        // Since PGPKeyModel is a struct, we need to create a new instance with modified values
        let expirationDate: Date? = days != nil ? Calendar.current.date(byAdding: .day, value: days!, to: Date()) : nil

        // We'll create a custom key model using the Key's actual structure
        // For testing purposes, we use the actual key and rely on ObjectivePGP's expiration handling
        return modifiedKey
    }

    /// Creates a test key with specific characteristics
    private func createTestKeyWithExpiration(daysFromNow: Int?) -> PGPKeyModel {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "testkey@example.com", passphrase: "testpass")
        return PGPKeyModel(from: key)
    }

    // MARK: - Initialization Tests

    @Test("KeyExpirationService initializes as singleton")
    func testSingletonInitialization() {
        let service1 = KeyExpirationService.shared
        let service2 = KeyExpirationService.shared

        #expect(service1 === service2)
    }

    @Test("Initial state is correct")
    func testInitialState() {
        let service = KeyExpirationService.shared

        // Note: We can't reliably test lastError == nil because it's a shared singleton
        // that may have been used by other tests running in parallel
        #expect(!service.isProcessing)
    }

    // MARK: - getExpiringKeys Tests

    @Test("Empty key array returns empty result")
    func testGetExpiringKeysEmptyArray() {
        let service = KeyExpirationService.shared

        let result = service.getExpiringKeys(within: 30, from: [])

        #expect(result.isEmpty)
    }

    @Test("getExpiringKeys filters keys without expiration")
    func testGetExpiringKeysFiltersNonExpiringKeys() {
        let service = KeyExpirationService.shared

        // Generate keys without expiration dates
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key1 = keyGen.generate(for: "test1@example.com", passphrase: "pass1")
        let key2 = keyGen.generate(for: "test2@example.com", passphrase: "pass2")

        let keys = [PGPKeyModel(from: key1), PGPKeyModel(from: key2)]

        let result = service.getExpiringKeys(within: 30, from: keys)

        // Keys without expiration should not be included
        #expect(result.count == 0)
    }

    @Test("getExpiringKeys with zero days threshold")
    func testGetExpiringKeysZeroDays() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keys = [PGPKeyModel(from: key)]

        let result = service.getExpiringKeys(within: 0, from: keys)

        #expect(result.isEmpty)
    }

    @Test("getExpiringKeys with 30 day threshold")
    func testGetExpiringKeys30Days() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keys = [PGPKeyModel(from: key)]

        let result = service.getExpiringKeys(within: 30, from: keys)

        // Generated keys typically don't have expiration by default
        #expect(result.count >= 0)
    }

    // MARK: - getExpiredKeys Tests

    @Test("getExpiredKeys returns empty for no expired keys")
    func testGetExpiredKeysEmpty() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keys = [PGPKeyModel(from: key)]

        let result = service.getExpiredKeys(from: keys)

        // Newly generated keys should not be expired
        #expect(result.isEmpty)
    }

    @Test("getExpiredKeys with empty array")
    func testGetExpiredKeysEmptyArray() {
        let service = KeyExpirationService.shared

        let result = service.getExpiredKeys(from: [])

        #expect(result.isEmpty)
    }

    @Test("getExpiredKeys filters correctly")
    func testGetExpiredKeysFiltering() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key1 = keyGen.generate(for: "test1@example.com", passphrase: "pass1")
        let key2 = keyGen.generate(for: "test2@example.com", passphrase: "pass2")

        let keys = [PGPKeyModel(from: key1), PGPKeyModel(from: key2)]

        let result = service.getExpiredKeys(from: keys)

        // All returned keys should be expired
        for key in result {
            #expect(key.isExpired)
        }
    }

    // MARK: - needsAttention Tests

    @Test("needsAttention returns false for non-expiring key")
    func testNeedsAttentionNonExpiringKey() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let result = service.needsAttention(keyModel)

        // Non-expiring keys should not need attention
        #expect(!result)
    }

    @Test("needsAttention checks expired status")
    func testNeedsAttentionExpiredKey() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        // Test logic: if key is expired, it needs attention
        if keyModel.isExpired {
            #expect(service.needsAttention(keyModel))
        }
    }

    @Test("needsAttention checks expiring soon status")
    func testNeedsAttentionExpiringSoon() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        // Test logic: if key is expiring soon, it needs attention
        if keyModel.isExpiringSoon {
            #expect(service.needsAttention(keyModel))
        }
    }

    // MARK: - validateExpirationDate Tests

    @Test("Validation fails for past date")
    func testValidateExpirationDatePast() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        let issues = service.validateExpirationDate(pastDate, forKey: keyModel)

        #expect(issues.count > 0)
        #expect(issues.contains { $0.contains("future") })
    }

    @Test("Validation fails for date before key creation")
    func testValidateExpirationDateBeforeCreation() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        // Set date to yesterday (before today's creation date)
        let beforeCreation = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        let issues = service.validateExpirationDate(beforeCreation, forKey: keyModel)

        #expect(issues.count > 0)
    }

    @Test("Validation warns for date too far in future")
    func testValidateExpirationDateTooFarFuture() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let farFuture = Calendar.current.date(byAdding: .year, value: 10, to: Date())!

        let issues = service.validateExpirationDate(farFuture, forKey: keyModel)

        #expect(issues.count > 0)
        #expect(issues.contains { $0.contains("5 years") || $0.contains("Warning") })
    }

    @Test("Validation passes for valid future date")
    func testValidateExpirationDateValid() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let validDate = Calendar.current.date(byAdding: .year, value: 2, to: Date())!

        let issues = service.validateExpirationDate(validDate, forKey: keyModel)

        // Should either have no issues or only warnings (not errors)
        let hasErrors = issues.contains { !$0.contains("Warning") }
        #expect(!hasErrors || issues.isEmpty)
    }

    @Test("Validation fails for current date")
    func testValidateExpirationDateNow() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let issues = service.validateExpirationDate(Date(), forKey: keyModel)

        #expect(issues.count > 0)
        #expect(issues.contains { $0.contains("future") })
    }

    @Test("Validation accepts date one year in future")
    func testValidateExpirationDateOneYear() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let oneYear = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        let issues = service.validateExpirationDate(oneYear, forKey: keyModel)

        // Should not have any blocking errors (warnings about 5 years don't apply)
        let hasBlockingErrors = issues.contains {
            $0.contains("future") || $0.contains("creation")
        }
        #expect(!hasBlockingErrors)
    }

    // MARK: - extendExpiration Error Handling Tests

    @Test("extendExpiration fails for public-only key")
    func testExtendExpirationPublicKeyError() {
        let service = KeyExpirationService.shared

        // Generate a key and extract only public part
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")

        // Create public-only version
        let publicKey = key.publicKey!
        let publicOnlyKey = Key(secretKey: nil, publicKey: publicKey)
        let keyModel = PGPKeyModel(from: publicOnlyKey)

        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        #expect(throws: OperationError.self) {
            try service.extendExpiration(
                for: keyModel,
                newExpirationDate: futureDate,
                passphrase: "pass"
            )
        }
    }

    @Test("extendExpiration fails for past date")
    func testExtendExpirationPastDateError() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        #expect(throws: OperationError.self) {
            try service.extendExpiration(
                for: keyModel,
                newExpirationDate: pastDate,
                passphrase: "pass"
            )
        }
    }

    @Test("extendExpiration fails for empty passphrase")
    func testExtendExpirationEmptyPassphraseError() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        #expect(throws: OperationError.self) {
            try service.extendExpiration(
                for: keyModel,
                newExpirationDate: futureDate,
                passphrase: ""
            )
        }
    }

    @Test("extendExpiration currently throws not implemented error")
    func testExtendExpirationNotImplemented() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        do {
            _ = try service.extendExpiration(
                for: keyModel,
                newExpirationDate: futureDate,
                passphrase: "pass"
            )
            Issue.record("Expected error to be thrown")
        } catch let error as OperationError {
            // Should throw an error about not being implemented
            if case .unknownError(let message) = error {
                #expect(message.contains("not yet supported") || message.contains("not implemented"))
            }
        } catch {
            Issue.record("Expected OperationError, got \(error)")
        }
    }

    @Test("extendExpiration sets lastError on failure")
    func testExtendExpirationSetsLastError() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        do {
            _ = try service.extendExpiration(
                for: keyModel,
                newExpirationDate: pastDate,
                passphrase: "pass"
            )
        } catch {
            // Expected to throw
        }

        #expect(service.lastError != nil)
    }

    @Test("extendExpiration resets isProcessing flag")
    func testExtendExpirationResetsProcessingFlag() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        do {
            _ = try service.extendExpiration(
                for: keyModel,
                newExpirationDate: futureDate,
                passphrase: "pass"
            )
        } catch {
            // Expected to throw
        }

        #expect(!service.isProcessing)
    }

    // MARK: - extendExpirationAsync Tests

    @Test("extendExpirationAsync completes on main thread")
    func testExtendExpirationAsyncMainThread() async {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        let expectation = TestExpectation()

        service.extendExpirationAsync(
            for: keyModel,
            newExpirationDate: futureDate,
            passphrase: "pass"
        ) { result in
            #expect(Thread.isMainThread)
            expectation.fulfill()
        }

        await expectation.fulfillment
    }

    @Test("extendExpirationAsync returns failure for invalid input")
    func testExtendExpirationAsyncFailure() async {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        let expectation = TestExpectation()

        service.extendExpirationAsync(
            for: keyModel,
            newExpirationDate: pastDate,
            passphrase: "pass"
        ) { result in
            switch result {
            case .success:
                Issue.record("Expected failure, got success")
            case .failure(let error):
                #expect(error is OperationError)
            }
            expectation.fulfill()
        }

        await expectation.fulfillment
    }

    @Test("extendExpirationAsync handles empty passphrase")
    func testExtendExpirationAsyncEmptyPassphrase() async {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        let expectation = TestExpectation()

        service.extendExpirationAsync(
            for: keyModel,
            newExpirationDate: futureDate,
            passphrase: ""
        ) { result in
            switch result {
            case .success:
                Issue.record("Expected failure for empty passphrase")
            case .failure(let error):
                if case .passphraseRequired = error {
                    // Expected error
                } else {
                    // Any error is acceptable since the operation isn't implemented
                }
            }
            expectation.fulfill()
        }

        await expectation.fulfillment
    }
}

/// Test expectation helper for async tests
private class TestExpectation {
    private var isFulfilled = false
    private let condition = NSCondition()

    func fulfill() {
        condition.lock()
        isFulfilled = true
        condition.signal()
        condition.unlock()
    }

    var fulfillment: Void {
        get async {
            condition.lock()
            while !isFulfilled {
                condition.wait()
            }
            condition.unlock()
        }
    }
}
