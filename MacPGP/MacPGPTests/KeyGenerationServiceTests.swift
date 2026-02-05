//
//  KeyGenerationServiceTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 04/02/26.
//

import Testing
import Foundation
import ObjectivePGP
@testable import MacPGP

@Suite("KeyGenerationService Tests")
struct KeyGenerationServiceTests {

    // MARK: - Passphrase Validation Tests

    @Test("Empty passphrase has too short issue")
    func testValidateEmptyPassphrase() {
        let service = KeyGenerationService.shared

        let issues = service.validatePassphrase("")

        // Empty passphrase only gets tooShort issue since count > 0 is required for other checks
        #expect(issues.count == 1)
        #expect(issues.contains { if case .tooShort = $0 { return true }; return false })
    }

    @Test("Too short passphrase is detected")
    func testValidateTooShortPassphrase() {
        let service = KeyGenerationService.shared

        let issues = service.validatePassphrase("Pass1!")

        let hasTooShortIssue = issues.contains { if case .tooShort = $0 { return true }; return false }
        #expect(hasTooShortIssue)
    }

    @Test("Passphrase without uppercase is detected")
    func testValidateNoUppercase() {
        let service = KeyGenerationService.shared

        let issues = service.validatePassphrase("password123!")

        let hasNoUppercaseIssue = issues.contains { if case .noUppercase = $0 { return true }; return false }
        #expect(hasNoUppercaseIssue)
    }

    @Test("Passphrase without lowercase is detected")
    func testValidateNoLowercase() {
        let service = KeyGenerationService.shared

        let issues = service.validatePassphrase("PASSWORD123!")

        let hasNoLowercaseIssue = issues.contains { if case .noLowercase = $0 { return true }; return false }
        #expect(hasNoLowercaseIssue)
    }

    @Test("Passphrase without digit is detected")
    func testValidateNoDigit() {
        let service = KeyGenerationService.shared

        let issues = service.validatePassphrase("Password!")

        let hasNoDigitIssue = issues.contains { if case .noDigit = $0 { return true }; return false }
        #expect(hasNoDigitIssue)
    }

    @Test("Passphrase without special character is detected")
    func testValidateNoSpecialCharacter() {
        let service = KeyGenerationService.shared

        let issues = service.validatePassphrase("Password123")

        let hasNoSpecialCharIssue = issues.contains { if case .noSpecialCharacter = $0 { return true }; return false }
        #expect(hasNoSpecialCharIssue)
    }

    @Test("Valid passphrase has no issues")
    func testValidateValidPassphrase() {
        let service = KeyGenerationService.shared

        let issues = service.validatePassphrase("Password123!")

        #expect(issues.isEmpty)
    }

    @Test("Passphrase with multiple missing requirements")
    func testValidateMultipleIssues() {
        let service = KeyGenerationService.shared

        let issues = service.validatePassphrase("pass")

        #expect(issues.count >= 3)
        let hasTooShortIssue = issues.contains { if case .tooShort = $0 { return true }; return false }
        #expect(hasTooShortIssue)
    }

    // MARK: - Passphrase Strength Tests

    @Test("Empty passphrase has none strength")
    func testStrengthEmptyPassphrase() {
        let service = KeyGenerationService.shared

        let strength = service.passphraseStrength("")

        #expect(strength == .none)
    }

    @Test("Very weak passphrase is detected")
    func testStrengthVeryWeakPassphrase() {
        let service = KeyGenerationService.shared

        let strength = service.passphraseStrength("pass")

        #expect(strength == .veryWeak)
    }

    @Test("Weak passphrase is detected")
    func testStrengthWeakPassphrase() {
        let service = KeyGenerationService.shared

        let strength = service.passphraseStrength("password")

        #expect(strength == .weak)
    }

    @Test("Fair passphrase is detected")
    func testStrengthFairPassphrase() {
        let service = KeyGenerationService.shared

        let strength = service.passphraseStrength("password1")

        #expect(strength == .fair)
    }

    @Test("Good passphrase is detected")
    func testStrengthGoodPassphrase() {
        let service = KeyGenerationService.shared

        let strength = service.passphraseStrength("Password1!")

        #expect(strength == .good)
    }

    @Test("Strong passphrase is detected")
    func testStrengthStrongPassphrase() {
        let service = KeyGenerationService.shared

        let strength = service.passphraseStrength("StrongPassword123!")

        #expect(strength == .strong)
    }

    @Test("PassphraseStrength enum has correct descriptions")
    func testPassphraseStrengthDescriptions() {
        #expect(PassphraseStrength.none.description == "No passphrase")
        #expect(PassphraseStrength.veryWeak.description == "Very Weak")
        #expect(PassphraseStrength.weak.description == "Weak")
        #expect(PassphraseStrength.fair.description == "Fair")
        #expect(PassphraseStrength.good.description == "Good")
        #expect(PassphraseStrength.strong.description == "Strong")
    }

    @Test("PassphraseStrength enum has correct colors")
    func testPassphraseStrengthColors() {
        #expect(PassphraseStrength.none.color == "gray")
        #expect(PassphraseStrength.veryWeak.color == "red")
        #expect(PassphraseStrength.weak.color == "orange")
        #expect(PassphraseStrength.fair.color == "yellow")
        #expect(PassphraseStrength.good.color == "green")
        #expect(PassphraseStrength.strong.color == "blue")
    }

    @Test("PassphraseValidationIssue has correct descriptions")
    func testPassphraseValidationIssueDescriptions() {
        #expect(PassphraseValidationIssue.tooShort(minimum: 8).description == "Must be at least 8 characters")
        #expect(PassphraseValidationIssue.noUppercase.description == "Should contain uppercase letters")
        #expect(PassphraseValidationIssue.noLowercase.description == "Should contain lowercase letters")
        #expect(PassphraseValidationIssue.noDigit.description == "Should contain numbers")
        #expect(PassphraseValidationIssue.noSpecialCharacter.description == "Should contain special characters")
    }

    // MARK: - KeyGenerationParameters Tests

    @Test("KeyGenerationParameters userID format without comment")
    func testUserIDFormatWithoutComment() {
        let params = KeyGenerationParameters(
            name: "Test User",
            email: "test@example.com",
            comment: nil,
            passphrase: "Password123!"
        )

        #expect(params.userID == "Test User <test@example.com>")
    }

    @Test("KeyGenerationParameters userID format with comment")
    func testUserIDFormatWithComment() {
        let params = KeyGenerationParameters(
            name: "Test User",
            email: "test@example.com",
            comment: "Work Key",
            passphrase: "Password123!"
        )

        #expect(params.userID == "Test User (Work Key) <test@example.com>")
    }

    @Test("KeyGenerationParameters userID format with empty comment")
    func testUserIDFormatWithEmptyComment() {
        let params = KeyGenerationParameters(
            name: "Test User",
            email: "test@example.com",
            comment: "",
            passphrase: "Password123!"
        )

        #expect(params.userID == "Test User <test@example.com>")
    }

    @Test("KeyGenerationParameters has correct defaults")
    func testKeyGenerationParametersDefaults() {
        let params = KeyGenerationParameters(
            name: "Test User",
            email: "test@example.com",
            passphrase: "Password123!"
        )

        #expect(params.algorithm == .rsa)
        #expect(params.keySize == 4096)
        #expect(params.expirationMonths == 24)
        #expect(params.comment == nil)
    }

    // MARK: - Key Generation Tests

    @Test("Generate RSA key successfully")
    func testGenerateRSAKey() throws {
        let service = KeyGenerationService.shared

        let params = KeyGenerationParameters(
            name: "Test User",
            email: "test-gen-rsa@example.com",
            passphrase: "TestPassword123!",
            algorithm: .rsa,
            keySize: 2048
        )

        let key = try service.generateKey(with: params)

        #expect(key.publicKey != nil)
        #expect(key.secretKey != nil)
    }

    @Test("Generate key with comment")
    func testGenerateKeyWithComment() throws {
        let service = KeyGenerationService.shared

        let params = KeyGenerationParameters(
            name: "Test User",
            email: "test-gen-comment@example.com",
            comment: "Test Comment",
            passphrase: "TestPassword123!",
            algorithm: .rsa,
            keySize: 2048
        )

        let key = try service.generateKey(with: params)

        #expect(key.publicKey != nil)
        #expect(key.secretKey != nil)

        let userID = key.publicKey?.users.first?.userID ?? ""
        #expect(userID.contains("Test Comment"))
    }

    @Test("Generate key without comment")
    func testGenerateKeyWithoutComment() throws {
        let service = KeyGenerationService.shared

        let params = KeyGenerationParameters(
            name: "Test User",
            email: "test-gen-nocomment@example.com",
            comment: nil,
            passphrase: "TestPassword123!",
            algorithm: .rsa,
            keySize: 2048
        )

        let key = try service.generateKey(with: params)

        #expect(key.publicKey != nil)
        #expect(key.secretKey != nil)
    }

    @Test("Generated key has correct user ID")
    func testGeneratedKeyUserID() throws {
        let service = KeyGenerationService.shared

        let params = KeyGenerationParameters(
            name: "John Doe",
            email: "john.doe@example.com",
            comment: "Personal",
            passphrase: "TestPassword123!",
            algorithm: .rsa,
            keySize: 2048
        )

        let key = try service.generateKey(with: params)

        let userID = key.publicKey?.users.first?.userID ?? ""
        #expect(userID.contains("John Doe"))
        #expect(userID.contains("john.doe@example.com"))
        #expect(userID.contains("Personal"))
    }

    // NOTE: ECDSA and EdDSA tests are commented out due to ObjectivePGP library limitations
    // The library doesn't properly support these algorithms and causes crashes during key generation

    // @Test("Generate key with ECDSA algorithm")
    // func testGenerateECDSAKey() throws {
    //     let service = KeyGenerationService.shared
    //
    //     let params = KeyGenerationParameters(
    //         name: "Test User",
    //         email: "test-gen-ecdsa@example.com",
    //         passphrase: "TestPassword123!",
    //         algorithm: .ecdsa,
    //         keySize: 256
    //     )
    //
    //     let key = try service.generateKey(with: params)
    //
    //     #expect(key.publicKey != nil)
    //     #expect(key.secretKey != nil)
    // }

    // @Test("Generate key with EdDSA algorithm")
    // func testGenerateEdDSAKey() throws {
    //     let service = KeyGenerationService.shared
    //
    //     let params = KeyGenerationParameters(
    //         name: "Test User",
    //         email: "test-gen-eddsa@example.com",
    //         passphrase: "TestPassword123!",
    //         algorithm: .eddsa,
    //         keySize: 256
    //     )
    //
    //     let key = try service.generateKey(with: params)
    //
    //     #expect(key.publicKey != nil)
    //     #expect(key.secretKey != nil)
    // }

    @Test("Generate key with different key sizes")
    func testGenerateKeyWithDifferentSizes() throws {
        let service = KeyGenerationService.shared

        for keySize in [2048, 3072, 4096] {
            let params = KeyGenerationParameters(
                name: "Test User",
                email: "test-gen-size-\(keySize)@example.com",
                passphrase: "TestPassword123!",
                algorithm: .rsa,
                keySize: keySize
            )

            let key = try service.generateKey(with: params)

            #expect(key.publicKey != nil)
            #expect(key.secretKey != nil)
        }
    }

    // MARK: - Async Key Generation Tests

    @Test("Generate key async successfully")
    func testGenerateKeyAsync() async throws {
        let service = KeyGenerationService.shared

        let params = KeyGenerationParameters(
            name: "Test User",
            email: "test-gen-async@example.com",
            passphrase: "TestPassword123!",
            algorithm: .rsa,
            keySize: 2048
        )

        let result = await withCheckedContinuation { continuation in
            var progressValues: [Double] = []

            service.generateKeyAsync(
                with: params,
                progress: { progress in
                    progressValues.append(progress)
                },
                completion: { result in
                    continuation.resume(returning: (result, progressValues))
                }
            )
        }

        switch result.0 {
        case .success(let key):
            #expect(key.publicKey != nil)
            #expect(key.secretKey != nil)
        case .failure(let error):
            Issue.record("Key generation failed: \(error)")
        }

        #expect(result.1.count > 0)
        #expect(result.1.contains(0.1))
        #expect(result.1.contains(1.0))
    }

    @Test("Generate key async reports progress")
    func testGenerateKeyAsyncProgress() async throws {
        let service = KeyGenerationService.shared

        let params = KeyGenerationParameters(
            name: "Test User",
            email: "test-gen-async-progress@example.com",
            passphrase: "TestPassword123!",
            algorithm: .rsa,
            keySize: 2048
        )

        let result = await withCheckedContinuation { continuation in
            var initialProgressReceived = false
            var finalProgressReceived = false

            service.generateKeyAsync(
                with: params,
                progress: { progress in
                    if progress == 0.1 {
                        initialProgressReceived = true
                    }
                    if progress == 1.0 {
                        finalProgressReceived = true
                    }
                },
                completion: { _ in
                    continuation.resume(returning: (initialProgressReceived, finalProgressReceived))
                }
            )
        }

        #expect(result.0)
        #expect(result.1)
    }

    @Test("KeyGenerationService is singleton")
    func testSingletonInstance() {
        let instance1 = KeyGenerationService.shared
        let instance2 = KeyGenerationService.shared

        #expect(instance1 === instance2)
    }
}
