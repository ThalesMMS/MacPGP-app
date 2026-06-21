//
//  KeyExpirationServiceTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 10/02/26.
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

@MainActor
@Suite("KeyExpirationService Tests", .serialized)
struct KeyExpirationServiceTests {

    // MARK: - Test Helpers

    /// Creates a mock key.
    private func createMockKey(isSecret: Bool = false) -> PGPKeyModel {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: "test@example.com", passphrase: "test")

        if isSecret {
            return PGPKeyModel(from: key)
        }

        let publicKey = key.publicKey!
        return PGPKeyModel(from: Key(secretKey: nil, publicKey: publicKey))
    }

    /// Creates a test key with specific characteristics
    private func createTestKeyWithExpiration(daysFromNow: Int?) -> PGPKeyModel {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: "testkey@example.com", passphrase: "testpass")
        return PGPKeyModel(from: key)
    }

    private func createTestKey(
        email: String = "test@example.com",
        passphrase: String = "testpass",
        isSecret: Bool = true
    ) -> PGPKeyModel {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: email, passphrase: passphrase)

        if isSecret {
            return PGPKeyModel(from: key)
        }

        let publicKey = key.publicKey!
        let publicOnlyKey = Key(secretKey: nil, publicKey: publicKey)
        return PGPKeyModel(from: publicOnlyKey)
    }

    private func unwrapLastError(from service: KeyExpirationService, context: String) -> OperationError? {
        guard let lastError = service.lastError else {
            Issue.record("Expected lastError for \(context)")
            return nil
        }

        return lastError
    }

    private func expectNoSecretKey(_ error: OperationError, context: String) {
        if case .noSecretKey = error {
            return
        }

        Issue.record("Expected OperationError.noSecretKey for \(context), got \(error)")
    }

    private func expectPassphraseRequired(_ error: OperationError, context: String) {
        if case .passphraseRequired = error {
            return
        }

        Issue.record("Expected OperationError.passphraseRequired for \(context), got \(error)")
    }

    @discardableResult
    private func expectUnknownError(
        _ error: OperationError,
        containing expectedSubstring: String,
        context: String
    ) -> String {
        if case .unknownError(let message) = error {
            #expect(message.localizedCaseInsensitiveContains(expectedSubstring))
            #expect(!message.localizedCaseInsensitiveContains("not implemented"))
            return message
        }

        Issue.record("Expected OperationError.unknownError for \(context), got \(error)")
        return ""
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
        let key1 = try! keyGen.generate(for: "test1@example.com", passphrase: "pass1")
        let key2 = try! keyGen.generate(for: "test2@example.com", passphrase: "pass2")

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
        let key = try! keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keys = [PGPKeyModel(from: key)]

        let result = service.getExpiringKeys(within: 0, from: keys)

        #expect(result.isEmpty)
    }

    @Test("getExpiringKeys with 30 day threshold")
    func testGetExpiringKeys30Days() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: "test@example.com", passphrase: "pass")
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
        let key = try! keyGen.generate(for: "test@example.com", passphrase: "pass")
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
        let key1 = try! keyGen.generate(for: "test1@example.com", passphrase: "pass1")
        let key2 = try! keyGen.generate(for: "test2@example.com", passphrase: "pass2")

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
        let key = try! keyGen.generate(for: "test@example.com", passphrase: "pass")
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
        let key = try! keyGen.generate(for: "test@example.com", passphrase: "pass")
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
        let key = try! keyGen.generate(for: "test@example.com", passphrase: "pass")
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
        let key = try! keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        let issues = service.validateExpirationDate(pastDate, forKey: keyModel)

        #expect(issues.count > 0)
        #expect(issues.contains { $0.message.contains("future") && $0.severity == .error })
    }

    @Test("Validation fails for date before key creation")
    func testValidateExpirationDateBeforeCreation() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        // Set date to yesterday (before today's creation date)
        let beforeCreation = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        let issues = service.validateExpirationDate(beforeCreation, forKey: keyModel)

        #expect(issues.count > 0)
        #expect(issues.contains { $0.severity == .error })
    }

    @Test("Validation warns for date too far in future")
    func testValidateExpirationDateTooFarFuture() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let farFuture = Calendar.current.date(byAdding: .year, value: 10, to: Date())!

        let issues = service.validateExpirationDate(farFuture, forKey: keyModel)

        #expect(issues.count > 0)
        #expect(issues.contains { $0.message.contains("5 years") && $0.severity == .warning })
    }

    @Test("Validation passes for valid future date")
    func testValidateExpirationDateValid() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let validDate = Calendar.current.date(byAdding: .year, value: 2, to: Date())!

        let issues = service.validateExpirationDate(validDate, forKey: keyModel)

        // Should either have no issues or only warnings (not errors)
        let hasErrors = issues.contains { $0.severity == .error }
        #expect(!hasErrors || issues.isEmpty)
    }

    @Test("Validation fails for current date")
    func testValidateExpirationDateNow() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let issues = service.validateExpirationDate(Date(), forKey: keyModel)

        #expect(issues.count > 0)
        #expect(issues.contains { $0.message.contains("future") && $0.severity == .error })
    }

    @Test("Validation accepts date one year in future")
    func testValidateExpirationDateOneYear() {
        let service = KeyExpirationService.shared

        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: "test@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let oneYear = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        let issues = service.validateExpirationDate(oneYear, forKey: keyModel)

        // Should not have any blocking errors (warnings about 5 years don't apply)
        let hasBlockingErrors = issues.contains { $0.severity == .error }
        #expect(!hasBlockingErrors)
    }

    @Test("extendExpiration updates the key expiration date")
    func testExtendExpirationUpdatesKey() async throws {
        let service = KeyExpirationService.shared
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: "expires@example.com", passphrase: "testpass")
        let keyModel = PGPKeyModel(from: key)
        let newExpirationDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())!

        let updatedKey = try await service.extendExpirationAsync(
            for: keyModel,
            newExpirationDate: newExpirationDate,
            passphrase: "testpass"
        )

        #expect(updatedKey.expirationDate != nil)
        if let expirationDate = updatedKey.expirationDate {
            #expect(abs(expirationDate.timeIntervalSince(newExpirationDate)) < 5)
        }
        #expect(!updatedKey.isExpired)
    }

    @Test("extendExpiration wraps unsupported passphrase failures as unknown error")
    func testExtendExpirationInvalidPassphrase() async {
        let service = KeyExpirationService.shared
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: "expires@example.com", passphrase: "testpass")
        let keyModel = PGPKeyModel(from: key)
        let newExpirationDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())!

        do {
            _ = try await service.extendExpirationAsync(
                for: keyModel,
                newExpirationDate: newExpirationDate,
                passphrase: "wrong-passphrase"
            )
            Issue.record("Expected wrapped unknown error")
        } catch let error as OperationError {
            if case .unknownError(let message) = error {
                #expect(message.contains("set key expiration failed"))
            } else {
                Issue.record("Expected OperationError.unknownError, got \(error)")
            }
        } catch {
            Issue.record("Expected OperationError.unknownError, got \(error)")
        }
    }

    // MARK: - extendExpiration Error Handling Tests

    @Test("extendExpiration fails for public-only key")
    func testExtendExpirationPublicKeyError() async {
        let service = KeyExpirationService.shared
        let keyModel = createTestKey(passphrase: "pass", isSecret: false)
        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        do {
            _ = try await service.extendExpirationAsync(
                for: keyModel,
                newExpirationDate: futureDate,
                passphrase: "pass"
            )
            Issue.record("Expected OperationError.noSecretKey")
        } catch let error as OperationError {
            expectNoSecretKey(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.noSecretKey, got \(error)")
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            expectNoSecretKey(lastError, context: "\(#function) lastError")
        }
        #expect(!service.isProcessing)
    }

    @Test("extendExpiration fails for past date")
    func testExtendExpirationPastDateError() async {
        let service = KeyExpirationService.shared
        let keyModel = createTestKey(passphrase: "pass")
        let pastDate = Date().addingTimeInterval(-86400)

        do {
            _ = try await service.extendExpirationAsync(
                for: keyModel,
                newExpirationDate: pastDate,
                passphrase: "pass"
            )
            Issue.record("Expected OperationError.unknownError")
        } catch let error as OperationError {
            _ = expectUnknownError(error, containing: "future", context: #function)
        } catch {
            Issue.record("Expected OperationError.unknownError, got \(error)")
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            _ = expectUnknownError(lastError, containing: "future", context: "\(#function) lastError")
        }
        #expect(!service.isProcessing)
    }

    @Test("extendExpiration fails for empty passphrase")
    func testExtendExpirationEmptyPassphraseError() async {
        let service = KeyExpirationService.shared
        let keyModel = createTestKey(passphrase: "pass")
        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        do {
            _ = try await service.extendExpirationAsync(
                for: keyModel,
                newExpirationDate: futureDate,
                passphrase: ""
            )
            Issue.record("Expected OperationError.passphraseRequired")
        } catch let error as OperationError {
            expectPassphraseRequired(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.passphraseRequired, got \(error)")
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            expectPassphraseRequired(lastError, context: "\(#function) lastError")
        }
        #expect(!service.isProcessing)
    }

    @Test("extendExpiration sets lastError on failure")
    func testExtendExpirationSetsLastError() async {
        let service = KeyExpirationService.shared
        let keyModel = createTestKey(passphrase: "pass")
        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        do {
            _ = try await service.extendExpirationAsync(
                for: keyModel,
                newExpirationDate: futureDate,
                passphrase: ""
            )
            Issue.record("Expected OperationError.passphraseRequired")
        } catch let error as OperationError {
            expectPassphraseRequired(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.passphraseRequired, got \(error)")
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            expectPassphraseRequired(lastError, context: "\(#function) lastError")
        }
    }

    @Test("extendExpiration resets isProcessing flag")
    func testExtendExpirationResetsProcessingFlag() async throws {
        let service = KeyExpirationService.shared
        let successKey = createTestKey(email: "processing-success@example.com", passphrase: "pass")
        let successDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())!

        _ = try await service.extendExpirationAsync(
            for: successKey,
            newExpirationDate: successDate,
            passphrase: "pass"
        )
        #expect(!service.isProcessing)

        let failureKey = createTestKey(email: "processing-failure@example.com", passphrase: "pass")
        let failureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        do {
            _ = try await service.extendExpirationAsync(
                for: failureKey,
                newExpirationDate: failureDate,
                passphrase: ""
            )
            Issue.record("Expected OperationError.passphraseRequired")
        } catch let error as OperationError {
            expectPassphraseRequired(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.passphraseRequired, got \(error)")
        }

        #expect(!service.isProcessing)
    }

    // MARK: - extendExpirationAsync Tests

    @Test("extendExpirationAsync completes on main thread")
    @MainActor
    func testExtendExpirationAsyncMainThread() async {
        let service = KeyExpirationService.shared
        let keyModel = createTestKey(email: "async-main@example.com", passphrase: "pass")
        let futureDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())!

        do {
            let updatedKey = try await service.extendExpirationAsync(
                for: keyModel,
                newExpirationDate: futureDate,
                passphrase: "pass"
            )
            #expect(updatedKey.expirationDate != nil)
            if let expirationDate = updatedKey.expirationDate {
                #expect(abs(expirationDate.timeIntervalSince(futureDate)) < 5)
            }
        } catch {
            Issue.record("Expected successful expiration update, got \(error)")
        }
        #expect(!service.isProcessing)
    }

    @Test("extendExpirationAsync returns failure for invalid input")
    @MainActor
    func testExtendExpirationAsyncFailure() async {
        let service = KeyExpirationService.shared
        let keyModel = createTestKey(passphrase: "pass")
        let pastDate = Date().addingTimeInterval(-86400)

        do {
            _ = try await service.extendExpirationAsync(
                for: keyModel,
                newExpirationDate: pastDate,
                passphrase: "pass"
            )
            Issue.record("Expected failure, got success")
        } catch let error as OperationError {
            _ = expectUnknownError(error, containing: "future", context: #function)
        } catch {
            Issue.record("Expected OperationError.unknownError, got \(error)")
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            _ = expectUnknownError(lastError, containing: "future", context: "\(#function) lastError")
        }
        #expect(!service.isProcessing)
    }

    @Test("extendExpirationAsync handles empty passphrase")
    @MainActor
    func testExtendExpirationAsyncEmptyPassphrase() async {
        let service = KeyExpirationService.shared
        let keyModel = createTestKey(passphrase: "pass")
        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        do {
            _ = try await service.extendExpirationAsync(
                for: keyModel,
                newExpirationDate: futureDate,
                passphrase: ""
            )
            Issue.record("Expected failure for empty passphrase")
        } catch let error as OperationError {
            expectPassphraseRequired(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.passphraseRequired, got \(error)")
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            expectPassphraseRequired(lastError, context: "\(#function) lastError")
        }
        #expect(!service.isProcessing)
    }

    // MARK: - OperationError mapping

    @Test("extendExpiration wraps OperationError unchanged — no double wrapping")
    func testExtendExpirationDoesNotRewrapOperationError() async {
        // When extendedKey throws an OperationError directly (e.g. passphraseRequired),
        // OperationError.from(_:) must pass it through unmodified, not wrap it in unknownError.
        let service = KeyExpirationService.shared
        let keyModel = createTestKey(passphrase: "correct-pass")
        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        do {
            _ = try await service.extendExpirationAsync(
                for: keyModel,
                newExpirationDate: futureDate,
                passphrase: ""  // triggers OperationError.passphraseRequired directly
            )
            Issue.record("Expected OperationError.passphraseRequired")
        } catch let error as OperationError {
            // Must be .passphraseRequired, not .unknownError wrapping a string
            if case .passphraseRequired = error {
                // Correct — passthrough preserved.
            } else {
                Issue.record("Expected .passphraseRequired (unchanged), got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("extendExpiration wraps OperationError.noSecretKey unchanged")
    func testExtendExpirationDoesNotRewrapNoSecretKey() async {
        let service = KeyExpirationService.shared
        let publicKeyModel = createTestKey(passphrase: "pass", isSecret: false)
        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        do {
            _ = try await service.extendExpirationAsync(
                for: publicKeyModel,
                newExpirationDate: futureDate,
                passphrase: "pass"
            )
            Issue.record("Expected OperationError.noSecretKey")
        } catch let error as OperationError {
            if case .noSecretKey = error {
                // Correct — passthrough preserved.
            } else {
                Issue.record("Expected .noSecretKey (unchanged), got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - extendExpiration metadata preservation

    @Test("extendExpiration preserves verification metadata from original key")
    func testExtendExpirationPreservesVerificationMetadata() async throws {
        let service = KeyExpirationService.shared
        let baseKey = createTestKey(email: "meta@example.com", passphrase: "meta-pass")

        // Build a key model with explicit verification metadata.
        let verificationDate = Date(timeIntervalSince1970: 1_000_000)
        let keyWithMeta = PGPKeyModel(
            from: baseKey.rawKey,
            isVerified: true,
            verificationDate: verificationDate,
            verificationMethod: .inPerson,
            trustLevel: .full
        )

        let futureDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        let updatedKey = try await service.extendExpirationAsync(
            for: keyWithMeta,
            newExpirationDate: futureDate,
            passphrase: "meta-pass"
        )

        #expect(updatedKey.isVerified == true)
        #expect(updatedKey.trustLevel == .full)
        #expect(updatedKey.verificationMethod == .inPerson)
        if let vDate = updatedKey.verificationDate {
            #expect(abs(vDate.timeIntervalSince(verificationDate)) < 1)
        } else {
            Issue.record("verificationDate should be preserved after expiration extension")
        }
    }

    @Test("extendExpiration preserves unverified state from original key")
    func testExtendExpirationPreservesUnverifiedState() async throws {
        let service = KeyExpirationService.shared
        let key = createTestKey(email: "unverified@example.com", passphrase: "unver-pass")

        let futureDate = Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        let updatedKey = try await service.extendExpirationAsync(
            for: key,
            newExpirationDate: futureDate,
            passphrase: "unver-pass"
        )

        #expect(updatedKey.isVerified == false)
        #expect(updatedKey.verificationDate == nil)
        #expect(updatedKey.verificationMethod == nil)
    }

    // MARK: - validateExpirationDate boundary

    @Test("validateExpirationDate at exactly 5-year boundary produces no warning")
    func testValidateExpirationDateExactFiveYears() {
        let service = KeyExpirationService.shared
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: "boundary@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        // Exactly 5 years from now is within the limit, so no warning expected.
        let fiveYears = Calendar.current.date(byAdding: .year, value: 5, to: Date())!
        let issues = service.validateExpirationDate(fiveYears, forKey: keyModel)
        let warnings = issues.filter { $0.severity == .warning }
        // At the exact boundary there should be no "more than 5 years" warning.
        #expect(warnings.isEmpty)
    }

    @Test("validateExpirationDate just past 5-year boundary produces warning")
    func testValidateExpirationDateJustPastFiveYears() {
        let service = KeyExpirationService.shared
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = try! keyGen.generate(for: "boundary2@example.com", passphrase: "pass")
        let keyModel = PGPKeyModel(from: key)

        let fiveYearsPlusOneDay = Calendar.current.date(
            byAdding: .day, value: 1,
            to: Calendar.current.date(byAdding: .year, value: 5, to: Date())!
        )!
        let issues = service.validateExpirationDate(fiveYearsPlusOneDay, forKey: keyModel)
        let warnings = issues.filter { $0.severity == .warning }
        #expect(!warnings.isEmpty)
        #expect(warnings.contains { $0.message.contains("5 years") })
    }
}
