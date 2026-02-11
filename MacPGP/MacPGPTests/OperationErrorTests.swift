//
//  OperationErrorTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 10/02/26.
//

import Testing
import Foundation
@testable import MacPGP

@Suite("OperationError Tests")
struct OperationErrorTests {

    // MARK: - Error Description Tests

    @Test("keyNotFound provides clear error description")
    func testKeyNotFoundErrorDescription() {
        let error = OperationError.keyNotFound(keyID: "ABC123")
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("ABC123"))
        #expect(description!.contains("keyring"))
    }

    @Test("invalidPassphrase provides clear error description")
    func testInvalidPassphraseErrorDescription() {
        let error = OperationError.invalidPassphrase
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("passphrase"))
        #expect(description!.contains("incorrect"))
    }

    @Test("passphraseRequired provides clear error description")
    func testPassphraseRequiredErrorDescription() {
        let error = OperationError.passphraseRequired
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("passphrase"))
        #expect(description!.contains("required"))
    }

    @Test("encryptionFailed without underlying error provides clear description")
    func testEncryptionFailedErrorDescription() {
        let error = OperationError.encryptionFailed(underlying: nil)
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("encrypt"))
        #expect(description!.contains("public key"))
    }

    @Test("encryptionFailed with underlying error includes error details")
    func testEncryptionFailedWithUnderlyingError() {
        let underlyingError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = OperationError.encryptionFailed(underlying: underlyingError)
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("Details:"))
        #expect(description!.contains("Test error"))
    }

    @Test("decryptionFailed without underlying error provides clear description")
    func testDecryptionFailedErrorDescription() {
        let error = OperationError.decryptionFailed(underlying: nil)
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("decrypt"))
        #expect(description!.contains("private key"))
    }

    @Test("decryptionFailed with underlying error includes error details")
    func testDecryptionFailedWithUnderlyingError() {
        let underlyingError = NSError(domain: "TestDomain", code: 456, userInfo: [NSLocalizedDescriptionKey: "Decrypt error"])
        let error = OperationError.decryptionFailed(underlying: underlyingError)
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("Details:"))
        #expect(description!.contains("Decrypt error"))
    }

    @Test("signingFailed provides clear error description")
    func testSigningFailedErrorDescription() {
        let error = OperationError.signingFailed(underlying: nil)
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("signature"))
        #expect(description!.contains("private key"))
    }

    @Test("verificationFailed provides clear error description")
    func testVerificationFailedErrorDescription() {
        let error = OperationError.verificationFailed(underlying: nil)
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("verify"))
        #expect(description!.contains("signature"))
    }

    @Test("keyGenerationFailed provides clear error description")
    func testKeyGenerationFailedErrorDescription() {
        let error = OperationError.keyGenerationFailed(underlying: nil)
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("generate"))
        #expect(description!.contains("key"))
    }

    @Test("keyImportFailed provides clear error description")
    func testKeyImportFailedErrorDescription() {
        let error = OperationError.keyImportFailed(underlying: nil)
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("import"))
        #expect(description!.contains("key"))
    }

    @Test("keyExportFailed provides clear error description")
    func testKeyExportFailedErrorDescription() {
        let error = OperationError.keyExportFailed(underlying: nil)
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("export"))
        #expect(description!.contains("key"))
    }

    @Test("keychainError provides clear error description")
    func testKeychainErrorDescription() {
        let error = OperationError.keychainError(underlying: nil)
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("Keychain"))
        #expect(description!.contains("passphrase"))
    }

    @Test("persistenceError provides clear error description")
    func testPersistenceErrorDescription() {
        let error = OperationError.persistenceError(underlying: nil)
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("save") || description!.contains("load"))
        #expect(description!.contains("storage"))
    }

    @Test("invalidKeyData provides clear error description")
    func testInvalidKeyDataErrorDescription() {
        let error = OperationError.invalidKeyData
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("invalid"))
        #expect(description!.contains("key data"))
    }

    @Test("keyExpired provides clear error description")
    func testKeyExpiredErrorDescription() {
        let error = OperationError.keyExpired
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("expired"))
        #expect(description!.contains("key"))
    }

    @Test("keyRevoked provides clear error description")
    func testKeyRevokedErrorDescription() {
        let error = OperationError.keyRevoked
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("revoked"))
        #expect(description!.contains("key"))
    }

    @Test("noPublicKey provides clear error description")
    func testNoPublicKeyErrorDescription() {
        let error = OperationError.noPublicKey
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("public key"))
    }

    @Test("noSecretKey provides clear error description")
    func testNoSecretKeyErrorDescription() {
        let error = OperationError.noSecretKey
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("private key"))
    }

    @Test("recipientKeyMissing provides clear error description")
    func testRecipientKeyMissingErrorDescription() {
        let error = OperationError.recipientKeyMissing
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("recipient"))
        #expect(description!.contains("public key"))
    }

    @Test("signerKeyMissing provides clear error description")
    func testSignerKeyMissingErrorDescription() {
        let error = OperationError.signerKeyMissing
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("private key"))
        #expect(description!.contains("sign"))
    }

    @Test("fileAccessError provides clear error description")
    func testFileAccessErrorDescription() {
        let error = OperationError.fileAccessError(path: "/tmp/test.txt")
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("/tmp/test.txt"))
        #expect(description!.contains("access"))
    }

    @Test("unknownError provides clear error description")
    func testUnknownErrorDescription() {
        let error = OperationError.unknownError(message: "Something went wrong")
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description!.contains("Something went wrong"))
    }

    // MARK: - Recovery Suggestion Tests

    @Test("keyNotFound provides actionable recovery suggestion")
    func testKeyNotFoundRecoverySuggestion() {
        let error = OperationError.keyNotFound(keyID: "ABC123")
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("Import") || suggestion!.contains("import"))
        #expect(suggestion!.contains("Generate") || suggestion!.contains("generate"))
    }

    @Test("invalidPassphrase provides actionable recovery suggestion")
    func testInvalidPassphraseRecoverySuggestion() {
        let error = OperationError.invalidPassphrase
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("Keychain"))
        #expect(suggestion!.contains("try again") || suggestion!.contains("Double-check"))
    }

    @Test("passphraseRequired provides actionable recovery suggestion")
    func testPassphraseRequiredRecoverySuggestion() {
        let error = OperationError.passphraseRequired
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("Enter") || suggestion!.contains("passphrase"))
        #expect(suggestion!.contains("Keychain"))
    }

    @Test("encryptionFailed provides actionable recovery suggestion")
    func testEncryptionFailedRecoverySuggestion() {
        let error = OperationError.encryptionFailed(underlying: nil)
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("Check") || suggestion!.contains("key"))
        #expect(suggestion!.contains("expired") || suggestion!.contains("revoked") || suggestion!.contains("reimport"))
    }

    @Test("decryptionFailed provides actionable recovery suggestion")
    func testDecryptionFailedRecoverySuggestion() {
        let error = OperationError.decryptionFailed(underlying: nil)
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("private key") || suggestion!.contains("passphrase"))
        #expect(suggestion!.contains("verify") || suggestion!.contains("ensure"))
    }

    @Test("signingFailed provides actionable recovery suggestion")
    func testSigningFailedRecoverySuggestion() {
        let error = OperationError.signingFailed(underlying: nil)
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("private key") || suggestion!.contains("passphrase"))
    }

    @Test("verificationFailed provides actionable recovery suggestion")
    func testVerificationFailedRecoverySuggestion() {
        let error = OperationError.verificationFailed(underlying: nil)
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("Import") || suggestion!.contains("public key"))
    }

    @Test("keyGenerationFailed provides actionable recovery suggestion")
    func testKeyGenerationFailedRecoverySuggestion() {
        let error = OperationError.keyGenerationFailed(underlying: nil)
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("Try") || suggestion!.contains("again"))
        #expect(suggestion!.contains("2048") || suggestion!.contains("4096"))
    }

    @Test("keyImportFailed provides actionable recovery suggestion")
    func testKeyImportFailedRecoverySuggestion() {
        let error = OperationError.keyImportFailed(underlying: nil)
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("BEGIN PGP") || suggestion!.contains("key block"))
    }

    @Test("keyExportFailed provides actionable recovery suggestion")
    func testKeyExportFailedRecoverySuggestion() {
        let error = OperationError.keyExportFailed(underlying: nil)
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("permissions") || suggestion!.contains("disk space"))
    }

    @Test("keychainError provides actionable recovery suggestion")
    func testKeychainErrorRecoverySuggestion() {
        let error = OperationError.keychainError(underlying: nil)
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("System Settings") || suggestion!.contains("Privacy"))
        #expect(suggestion!.contains("Keychain"))
    }

    @Test("persistenceError provides actionable recovery suggestion")
    func testPersistenceErrorRecoverySuggestion() {
        let error = OperationError.persistenceError(underlying: nil)
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("disk space") || suggestion!.contains("permissions"))
    }

    @Test("invalidKeyData provides actionable recovery suggestion")
    func testInvalidKeyDataRecoverySuggestion() {
        let error = OperationError.invalidKeyData
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("BEGIN PGP") || suggestion!.contains("valid"))
    }

    @Test("keyExpired provides actionable recovery suggestion")
    func testKeyExpiredRecoverySuggestion() {
        let error = OperationError.keyExpired
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("Generate") || suggestion!.contains("new key"))
    }

    @Test("keyRevoked provides actionable recovery suggestion")
    func testKeyRevokedRecoverySuggestion() {
        let error = OperationError.keyRevoked
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("Contact") || suggestion!.contains("key owner"))
    }

    @Test("noPublicKey provides actionable recovery suggestion")
    func testNoPublicKeyRecoverySuggestion() {
        let error = OperationError.noPublicKey
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("Import") || suggestion!.contains("Search"))
    }

    @Test("noSecretKey provides actionable recovery suggestion")
    func testNoSecretKeyRecoverySuggestion() {
        let error = OperationError.noSecretKey
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("Generate") || suggestion!.contains("private key"))
    }

    @Test("recipientKeyMissing provides actionable recovery suggestion")
    func testRecipientKeyMissingRecoverySuggestion() {
        let error = OperationError.recipientKeyMissing
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("Search") || suggestion!.contains("Import"))
        #expect(suggestion!.contains("recipient"))
    }

    @Test("signerKeyMissing provides actionable recovery suggestion")
    func testSignerKeyMissingRecoverySuggestion() {
        let error = OperationError.signerKeyMissing
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("Generate") || suggestion!.contains("key pair"))
    }

    @Test("fileAccessError provides actionable recovery suggestion")
    func testFileAccessErrorRecoverySuggestion() {
        let error = OperationError.fileAccessError(path: "/tmp/test.txt")
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("permission") || suggestion!.contains("Privacy"))
    }

    @Test("unknownError provides actionable recovery suggestion")
    func testUnknownErrorRecoverySuggestion() {
        let error = OperationError.unknownError(message: "Test")
        let suggestion = error.recoverySuggestion

        #expect(suggestion != nil)
        #expect(suggestion!.contains("Try") || suggestion!.contains("again"))
    }

    // MARK: - Failure Reason Tests

    @Test("keyNotFound provides clear failure reason")
    func testKeyNotFoundFailureReason() {
        let error = OperationError.keyNotFound(keyID: "XYZ789")
        let reason = error.failureReason

        #expect(reason != nil)
        #expect(reason!.contains("XYZ789"))
        #expect(reason!.contains("not found"))
    }

    @Test("invalidPassphrase provides clear failure reason")
    func testInvalidPassphraseFailureReason() {
        let error = OperationError.invalidPassphrase
        let reason = error.failureReason

        #expect(reason != nil)
        #expect(reason!.contains("does not match"))
    }

    @Test("passphraseRequired provides clear failure reason")
    func testPassphraseRequiredFailureReason() {
        let error = OperationError.passphraseRequired
        let reason = error.failureReason

        #expect(reason != nil)
        #expect(reason!.contains("encrypted"))
        #expect(reason!.contains("requires"))
    }

    @Test("encryptionFailed with underlying error provides detailed failure reason")
    func testEncryptionFailedFailureReason() {
        let underlyingError = NSError(domain: "CryptoError", code: 999, userInfo: [NSLocalizedDescriptionKey: "Crypto failure"])
        let error = OperationError.encryptionFailed(underlying: underlyingError)
        let reason = error.failureReason

        #expect(reason != nil)
        #expect(reason!.contains("Crypto failure"))
    }

    @Test("decryptionFailed without underlying error provides clear failure reason")
    func testDecryptionFailedFailureReason() {
        let error = OperationError.decryptionFailed(underlying: nil)
        let reason = error.failureReason

        #expect(reason != nil)
        #expect(reason!.contains("private key") || reason!.contains("passphrase"))
    }

    @Test("invalidKeyData provides clear failure reason")
    func testInvalidKeyDataFailureReason() {
        let error = OperationError.invalidKeyData
        let reason = error.failureReason

        #expect(reason != nil)
        #expect(reason!.contains("PGP") || reason!.contains("format"))
    }

    @Test("keyExpired provides clear failure reason")
    func testKeyExpiredFailureReason() {
        let error = OperationError.keyExpired
        let reason = error.failureReason

        #expect(reason != nil)
        #expect(reason!.contains("expiration"))
    }

    @Test("keyRevoked provides clear failure reason")
    func testKeyRevokedFailureReason() {
        let error = OperationError.keyRevoked
        let reason = error.failureReason

        #expect(reason != nil)
        #expect(reason!.contains("revocation"))
    }

    @Test("fileAccessError provides clear failure reason")
    func testFileAccessErrorFailureReason() {
        let error = OperationError.fileAccessError(path: "/some/path.txt")
        let reason = error.failureReason

        #expect(reason != nil)
        #expect(reason!.contains("/some/path.txt"))
        #expect(reason!.contains("permission") || reason!.contains("not exist"))
    }

    // MARK: - LocalizedError Conformance Tests

    @Test("Error conforms to LocalizedError protocol")
    func testLocalizedErrorConformance() {
        let error: LocalizedError = OperationError.invalidPassphrase

        #expect(error.errorDescription != nil)
        #expect(error.recoverySuggestion != nil)
        #expect(error.failureReason != nil)
    }

    @Test("All error messages are non-empty")
    func testAllErrorMessagesNonEmpty() {
        let errors: [OperationError] = [
            .keyNotFound(keyID: "TEST"),
            .invalidPassphrase,
            .passphraseRequired,
            .encryptionFailed(underlying: nil),
            .decryptionFailed(underlying: nil),
            .signingFailed(underlying: nil),
            .verificationFailed(underlying: nil),
            .keyGenerationFailed(underlying: nil),
            .keyImportFailed(underlying: nil),
            .keyExportFailed(underlying: nil),
            .keychainError(underlying: nil),
            .persistenceError(underlying: nil),
            .invalidKeyData,
            .keyExpired,
            .keyRevoked,
            .noPublicKey,
            .noSecretKey,
            .recipientKeyMissing,
            .signerKeyMissing,
            .fileAccessError(path: "/test"),
            .unknownError(message: "test")
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
            #expect(error.recoverySuggestion != nil)
            #expect(!error.recoverySuggestion!.isEmpty)
            #expect(error.failureReason != nil)
            #expect(!error.failureReason!.isEmpty)
        }
    }
}
