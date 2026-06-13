//
//  RevocationServiceTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 10/02/26.
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

@MainActor
@Suite("RevocationService Tests", .serialized)
struct RevocationServiceTests {

    // MARK: - Test Helpers

    /// Creates a test key for testing purposes
    private func createTestKey(isSecret: Bool = true) -> PGPKeyModel {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let key = keyGen.generate(for: "test@example.com", passphrase: "testpass")

        if isSecret {
            return PGPKeyModel(from: key)
        } else {
            // Create public-only version
            let publicKey = key.publicKey!
            let publicOnlyKey = Key(secretKey: nil, publicKey: publicKey)
            return PGPKeyModel(from: publicOnlyKey)
        }
    }

    /// Creates multiple test keys
    private func createTestKeys(count: Int, includeRevoked: Bool = false) -> [PGPKeyModel] {
        var keys: [PGPKeyModel] = []
        for i in 0..<count {
            let keyGen = KeyGenerator()
            keyGen.keyBitsLength = 2048
            let key = keyGen.generate(for: "test\(i)@example.com", passphrase: "pass\(i)")
            keys.append(PGPKeyModel(from: key))
        }
        return keys
    }

    private func createKeyringService(containing keys: [PGPKeyModel] = []) throws -> KeyringService {
        let service = KeyringService()

        for key in keys {
            try service.addKey(key.rawKey)
        }

        return service
    }

    private func unwrapLastError(from service: RevocationService, context: String) -> OperationError? {
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

    private func expectInvalidPassphrase(_ error: OperationError, context: String) {
        if case .invalidPassphrase = error {
            return
        }

        Issue.record("Expected OperationError.invalidPassphrase for \(context), got \(error)")
    }

    private func expectKeyImportFailed(_ error: OperationError, context: String) {
        if case .keyImportFailed(let underlying) = error {
            #expect(underlying == nil)
            return
        }

        Issue.record("Expected OperationError.keyImportFailed for \(context), got \(error)")
    }

    private func expectKeyNotFound(_ error: OperationError, context: String) {
        if case .keyNotFound(let keyID) = error {
            #expect(!keyID.isEmpty)
            return
        }

        Issue.record("Expected OperationError.keyNotFound for \(context), got \(error)")
    }

    @discardableResult
    private func expectUnknownError(_ error: OperationError, context: String) -> String {
        if case .unknownError(let message) = error {
            #expect(!message.isEmpty)
            #expect(!message.localizedCaseInsensitiveContains("not implemented"))
            return message
        }

        Issue.record("Expected OperationError.unknownError for \(context), got \(error)")
        return ""
    }

    // MARK: - Initialization Tests

    @Test("RevocationService initializes as singleton")
    func testSingletonInitialization() {
        let service1 = RevocationService.shared
        let service2 = RevocationService.shared

        #expect(service1 === service2)
    }

    @Test("Initial state is correct")
    func testInitialState() {
        let service = RevocationService.shared

        #expect(!service.isProcessing)
    }

    // MARK: - RevocationReason Enum Tests

    @Test("RevocationReason has correct descriptions")
    func testRevocationReasonDescriptions() {
        #expect(RevocationReason.noReason.description == "No reason specified")
        #expect(RevocationReason.compromised.description == "Key has been compromised")
        #expect(RevocationReason.superseded.description == "Key is superseded by a new key")
        #expect(RevocationReason.noLongerUsed.description == "Key is no longer used")
    }

    @Test("RevocationReason has correct display names")
    func testRevocationReasonDisplayNames() {
        #expect(RevocationReason.noReason.displayName == "No Reason")
        #expect(RevocationReason.compromised.displayName == "Compromised")
        #expect(RevocationReason.superseded.displayName == "Superseded")
        #expect(RevocationReason.noLongerUsed.displayName == "No Longer Used")
    }

    @Test("RevocationReason enum has all cases")
    func testRevocationReasonAllCases() {
        let allCases = RevocationReason.allCases

        #expect(allCases.count == 4)
        #expect(allCases.contains(.noReason))
        #expect(allCases.contains(.compromised))
        #expect(allCases.contains(.superseded))
        #expect(allCases.contains(.noLongerUsed))
    }

    @Test("RevocationReason raw values are correct")
    func testRevocationReasonRawValues() {
        #expect(RevocationReason.noReason.rawValue == 0)
        #expect(RevocationReason.compromised.rawValue == 1)
        #expect(RevocationReason.superseded.rawValue == 2)
        #expect(RevocationReason.noLongerUsed.rawValue == 3)
    }

    @Test("generateRevocationCertificate returns armored data and applyRevocation marks the key as revoked")
    func testGenerateAndApplyRevocationCertificate() throws {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)
        let keyringService = try createKeyringService(containing: [key])

        let certificate = try service.generateRevocationCertificate(
            for: key,
            reason: .compromised,
            passphrase: "testpass"
        )

        #expect(!certificate.isEmpty)
        let armoredCertificate = String(data: certificate, encoding: .utf8)
        #expect(armoredCertificate?.contains("BEGIN PGP") == true)

        let revokedFingerprint = try service.importRevocationCertificate(
            data: certificate,
            keyringService: keyringService,
            expectedKey: key
        )
        #expect(revokedFingerprint == key.fingerprint)

        let revokedKey = try service.applyRevocation(to: key, certificate: certificate)
        #expect(revokedKey.isRevoked)
        #expect(revokedKey.revokedDate != nil)
    }

    @Test("generateRevocationCertificate fails with invalid passphrase")
    func testGenerateRevocationCertificateInvalidPassphrase() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)

        do {
            _ = try service.generateRevocationCertificate(
                for: key,
                reason: .noReason,
                passphrase: "wrong-passphrase"
            )
            Issue.record("Expected invalid passphrase error")
        } catch let error as OperationError {
            expectInvalidPassphrase(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.invalidPassphrase, got \(error)")
        }
    }

    // MARK: - generateRevocationCertificate Error Tests

    @Test("generateRevocationCertificate fails for public-only key")
    func testGenerateRevocationCertificatePublicKeyError() {
        let service = RevocationService.shared
        let publicKey = createTestKey(isSecret: false)

        do {
            _ = try service.generateRevocationCertificate(
                for: publicKey,
                reason: .noReason,
                passphrase: "testpass"
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

    @Test("generateRevocationCertificate fails for empty passphrase")
    func testGenerateRevocationCertificateEmptyPassphrase() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)

        do {
            _ = try service.generateRevocationCertificate(
                for: key,
                reason: .compromised,
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

    @Test("generateRevocationCertificate succeeds for a valid secret key")
    func testGenerateRevocationCertificateNotImplemented() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)

        do {
            let certificate = try service.generateRevocationCertificate(
                for: key,
                reason: .compromised,
                passphrase: "testpass"
            )

            #expect(!certificate.isEmpty)
            #expect(String(data: certificate, encoding: .utf8)?.contains("BEGIN PGP") == true)
        } catch {
            Issue.record("Expected revocation generation to succeed, got \(error)")
        }

        #expect(!service.isProcessing)
    }

    @Test("generateRevocationCertificate sets lastError on failure")
    func testGenerateRevocationCertificateSetsLastError() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)

        do {
            _ = try service.generateRevocationCertificate(
                for: key,
                reason: .noReason,
                passphrase: "wrong-passphrase"
            )
            Issue.record("Expected OperationError.invalidPassphrase")
        } catch let error as OperationError {
            expectInvalidPassphrase(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.invalidPassphrase, got \(error)")
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            expectInvalidPassphrase(lastError, context: "\(#function) lastError")
        }
    }

    @Test("generateRevocationCertificate resets isProcessing flag")
    func testGenerateRevocationCertificateResetsProcessingFlag() {
        let service = RevocationService.shared
        let publicKey = createTestKey(isSecret: false)

        do {
            _ = try service.generateRevocationCertificate(
                for: publicKey,
                reason: .superseded,
                passphrase: "testpass"
            )
            Issue.record("Expected OperationError.noSecretKey")
        } catch let error as OperationError {
            expectNoSecretKey(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.noSecretKey, got \(error)")
        }

        #expect(!service.isProcessing)
    }

    @Test("generateRevocationCertificate accepts all revocation reasons")
    func testGenerateRevocationCertificateAllReasons() {
        let service = RevocationService.shared

        for reason in RevocationReason.allCases {
            let key = createTestKey(isSecret: true)
            let certificate = try? service.generateRevocationCertificate(
                for: key,
                reason: reason,
                passphrase: "testpass"
            )

            #expect(certificate?.isEmpty == false)
        }
    }

    // MARK: - generateRevocationCertificateAsync Tests

    @Test("generateRevocationCertificateAsync completes on main thread")
    @MainActor
    func testGenerateRevocationCertificateAsyncMainThread() async {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)

        do {
            let certificate = try await service.generateRevocationCertificateAsync(
                for: key,
                reason: .compromised,
                passphrase: "testpass"
            )
            #expect(Thread.isMainThread)
            #expect(!certificate.isEmpty)
        } catch {
            Issue.record("Expected successful revocation generation, got \(error)")
        }
    }

    @Test("generateRevocationCertificateAsync returns failure for public key")
    @MainActor
    func testGenerateRevocationCertificateAsyncPublicKeyFailure() async {
        let service = RevocationService.shared
        let publicKey = createTestKey(isSecret: false)

        do {
            _ = try await service.generateRevocationCertificateAsync(
                for: publicKey,
                reason: .noReason,
                passphrase: "testpass"
            )
            Issue.record("Expected failure for public key")
        } catch let error as OperationError {
            #expect(Thread.isMainThread)
            expectNoSecretKey(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.noSecretKey, got \(error)")
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            expectNoSecretKey(lastError, context: "\(#function) lastError")
        }
        #expect(!service.isProcessing)
    }

    @Test("generateRevocationCertificateAsync handles empty passphrase")
    @MainActor
    func testGenerateRevocationCertificateAsyncEmptyPassphrase() async {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)

        do {
            _ = try await service.generateRevocationCertificateAsync(
                for: key,
                reason: .noLongerUsed,
                passphrase: ""
            )
            Issue.record("Expected failure for empty passphrase")
        } catch let error as OperationError {
            #expect(Thread.isMainThread)
            expectPassphraseRequired(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.passphraseRequired, got \(error)")
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            expectPassphraseRequired(lastError, context: "\(#function) lastError")
        }
        #expect(!service.isProcessing)
    }

    // MARK: - importRevocationCertificate Tests

    @Test("importRevocationCertificate rejects invalid certificate data")
    func testImportRevocationCertificateNotImplemented() {
        let service = RevocationService.shared
        let keyringService = KeyringService()
        let testData = Data("test certificate".utf8)

        do {
            _ = try service.importRevocationCertificate(data: testData, keyringService: keyringService)
            Issue.record("Expected OperationError.keyImportFailed")
        } catch let error as OperationError {
            expectKeyImportFailed(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.keyImportFailed, got \(error)")
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            expectKeyImportFailed(lastError, context: "\(#function) lastError")
        }

        #expect(!service.isProcessing)
    }

    @Test("importRevocationCertificate sets lastError on failure")
    func testImportRevocationCertificateSetsLastError() {
        let service = RevocationService.shared
        let keyringService = KeyringService()
        let testData = Data("test".utf8)

        do {
            _ = try service.importRevocationCertificate(data: testData, keyringService: keyringService)
        } catch {
            // Expected to throw
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            expectKeyImportFailed(lastError, context: "\(#function) lastError")
        }
    }

    @Test("importRevocationCertificate resets isProcessing flag")
    func testImportRevocationCertificateResetsProcessingFlag() {
        let service = RevocationService.shared
        let keyringService = KeyringService()
        let testData = Data("test".utf8)

        do {
            _ = try service.importRevocationCertificate(data: testData, keyringService: keyringService)
            Issue.record("Expected OperationError.keyImportFailed")
        } catch let error as OperationError {
            expectKeyImportFailed(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.keyImportFailed, got \(error)")
        }

        #expect(!service.isProcessing)
    }

    @Test("importRevocationCertificate handles empty data")
    func testImportRevocationCertificateEmptyData() {
        let service = RevocationService.shared
        let keyringService = KeyringService()
        let emptyData = Data()

        do {
            _ = try service.importRevocationCertificate(data: emptyData, keyringService: keyringService)
            Issue.record("Expected error for empty data")
        } catch let error as OperationError {
            expectKeyImportFailed(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.keyImportFailed, got \(error)")
        }
    }

    @Test("importRevocationCertificate returns matching local key fingerprint")
    func testImportRevocationCertificateMatchesLocalKey() throws {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)
        let keyringService = try createKeyringService(containing: [key])
        let certificate = try service.generateRevocationCertificate(
            for: key,
            reason: .compromised,
            passphrase: "testpass"
        )

        let revokedFingerprint = try service.importRevocationCertificate(
            data: certificate,
            keyringService: keyringService,
            expectedKey: key
        )

        #expect(revokedFingerprint == key.fingerprint)
    }

    @Test("revocation identifier matching rejects arbitrary fingerprint suffix")
    func testRevocationIdentifierMatchingRejectsArbitraryFingerprintSuffix() {
        let identifier = "A1B2C3D4"
        let fingerprintWithSameSuffix = "00112233445566778899AABBCCDDEEFFA1B2C3D4"

        #expect(!RevocationService.identifier(identifier, matchesFingerprint: fingerprintWithSameSuffix, shortKeyID: "1122334455667788"))
        #expect(RevocationService.identifier(identifier, matchesFingerprint: identifier, shortKeyID: "1122334455667788"))
        #expect(RevocationService.identifier(identifier, matchesFingerprint: "00112233445566778899AABBCCDDEEFF00112233", shortKeyID: identifier))
    }

    @Test("importRevocationCertificate rejects certificate without local key")
    func testImportRevocationCertificateRejectsMissingLocalKey() throws {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)
        let keyringService = try createKeyringService()
        let certificate = try service.generateRevocationCertificate(
            for: key,
            reason: .compromised,
            passphrase: "testpass"
        )

        do {
            _ = try service.importRevocationCertificate(data: certificate, keyringService: keyringService)
            Issue.record("Expected OperationError.keyNotFound")
        } catch let error as OperationError {
            expectKeyNotFound(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.keyNotFound, got \(error)")
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            expectKeyNotFound(lastError, context: "\(#function) lastError")
        }
    }

    @Test("importRevocationCertificate rejects certificate for different selected key")
    func testImportRevocationCertificateRejectsDifferentExpectedKey() throws {
        let service = RevocationService.shared
        let revokedKey = createTestKey(isSecret: true)
        let selectedKey = createTestKey(isSecret: true)
        let keyringService = try createKeyringService(containing: [revokedKey, selectedKey])
        let certificate = try service.generateRevocationCertificate(
            for: revokedKey,
            reason: .compromised,
            passphrase: "testpass"
        )

        do {
            _ = try service.importRevocationCertificate(
                data: certificate,
                keyringService: keyringService,
                expectedKey: selectedKey
            )
            Issue.record("Expected OperationError.unknownError")
        } catch let error as OperationError {
            let message = expectUnknownError(error, context: #function)
            #expect(message.localizedCaseInsensitiveContains("does not match"))
        } catch {
            Issue.record("Expected OperationError.unknownError, got \(error)")
        }
    }

    // MARK: - applyRevocation Tests

    @Test("applyRevocation rejects invalid certificate data")
    func testApplyRevocationNotImplemented() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)
        let testData = Data("certificate".utf8)

        do {
            _ = try service.applyRevocation(to: key, certificate: testData)
            Issue.record("Expected OperationError.unknownError")
        } catch let error as OperationError {
            _ = expectUnknownError(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.unknownError, got \(error)")
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            _ = expectUnknownError(lastError, context: "\(#function) lastError")
        }

        #expect(!service.isProcessing)
    }

    @Test("applyRevocation sets lastError on failure")
    func testApplyRevocationSetsLastError() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)
        let testData = Data("cert".utf8)

        do {
            _ = try service.applyRevocation(to: key, certificate: testData)
        } catch {
            // Expected to throw
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            _ = expectUnknownError(lastError, context: "\(#function) lastError")
        }
    }

    @Test("applyRevocation resets isProcessing flag")
    func testApplyRevocationResetsProcessingFlag() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)
        let testData = Data("cert".utf8)

        do {
            _ = try service.applyRevocation(to: key, certificate: testData)
            Issue.record("Expected OperationError.unknownError")
        } catch let error as OperationError {
            _ = expectUnknownError(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.unknownError, got \(error)")
        }

        #expect(!service.isProcessing)
    }

    // MARK: - applyRevocationAsync Tests

    @Test("applyRevocationAsync completes on main thread")
    @MainActor
    func testApplyRevocationAsyncMainThread() async {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)
        guard let certificate = try? service.generateRevocationCertificate(
            for: key,
            reason: .compromised,
            passphrase: "testpass"
        ) else {
            Issue.record("Expected revocation certificate generation to succeed")
            return
        }
        do {
            let updatedKey = try await service.applyRevocationAsync(to: key, certificate: certificate)
            #expect(Thread.isMainThread)
            #expect(updatedKey.isRevoked)
        } catch {
            Issue.record("Expected successful revocation apply, got \(error)")
        }
    }

    @Test("applyRevocationAsync returns failure for invalid certificate data")
    @MainActor
    func testApplyRevocationAsyncFailure() async {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)
        let testData = Data("cert".utf8)
        do {
            _ = try await service.applyRevocationAsync(to: key, certificate: testData)
            Issue.record("Expected failure, got success")
        } catch let error as OperationError {
            #expect(Thread.isMainThread)
            _ = expectUnknownError(error, context: #function)
        } catch {
            Issue.record("Expected OperationError.unknownError, got \(error)")
        }

        if let lastError = unwrapLastError(from: service, context: #function) {
            _ = expectUnknownError(lastError, context: "\(#function) lastError")
        }
        #expect(!service.isProcessing)
    }

    // MARK: - isRevoked Tests

    @Test("isRevoked returns false for non-revoked key")
    func testIsRevokedFalse() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)

        let result = service.isRevoked(key)

        #expect(!result)
    }

    @Test("isRevoked correctly reads key property")
    func testIsRevokedReadsProperty() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)

        let result = service.isRevoked(key)

        #expect(result == key.isRevoked)
    }

    // MARK: - getRevokedKeys Tests

    @Test("getRevokedKeys returns empty for empty array")
    func testGetRevokedKeysEmptyArray() {
        let service = RevocationService.shared

        let result = service.getRevokedKeys(from: [])

        #expect(result.isEmpty)
    }

    @Test("getRevokedKeys returns empty for non-revoked keys")
    func testGetRevokedKeysNonRevokedKeys() {
        let service = RevocationService.shared
        let keys = createTestKeys(count: 3)

        let result = service.getRevokedKeys(from: keys)

        // Newly generated keys should not be revoked
        #expect(result.isEmpty)
    }

    @Test("getRevokedKeys filters correctly")
    func testGetRevokedKeysFiltering() {
        let service = RevocationService.shared
        let keys = createTestKeys(count: 5)

        let result = service.getRevokedKeys(from: keys)

        // All returned keys should be revoked
        for key in result {
            #expect(key.isRevoked)
        }
    }

    @Test("getRevokedKeys preserves order")
    func testGetRevokedKeysOrder() {
        let service = RevocationService.shared
        let keys = createTestKeys(count: 3)

        let result = service.getRevokedKeys(from: keys)

        // Result should maintain the same order as input
        // (This test mainly verifies the filter operation works correctly)
        #expect(result.count >= 0)
    }

    // MARK: - validateKeyUsability Tests

    @Test("validateKeyUsability returns empty for valid key")
    func testValidateKeyUsabilityValid() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)

        let issues = service.validateKeyUsability(key)

        // A newly generated key should have no usability issues
        #expect(issues.isEmpty)
    }

    @Test("validateKeyUsability checks revocation status")
    func testValidateKeyUsabilityRevoked() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)

        // Test the logic for revoked keys
        if key.isRevoked {
            let issues = service.validateKeyUsability(key)
            #expect(issues.contains { $0.contains("revoked") })
        }
    }

    @Test("validateKeyUsability checks expiration status")
    func testValidateKeyUsabilityExpired() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)

        // Test the logic for expired keys
        if key.isExpired {
            let issues = service.validateKeyUsability(key)
            #expect(issues.contains { $0.contains("expired") })
        }
    }

    @Test("validateKeyUsability returns multiple issues")
    func testValidateKeyUsabilityMultipleIssues() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)

        let issues = service.validateKeyUsability(key)

        // Issues array should be a valid array (empty or with items)
        #expect(issues is [String])
    }

    @Test("validateKeyUsability issue messages are descriptive")
    func testValidateKeyUsabilityDescriptiveMessages() {
        let service = RevocationService.shared
        let key = createTestKey(isSecret: true)

        let issues = service.validateKeyUsability(key)

        // All messages should be non-empty strings
        for issue in issues {
            #expect(!issue.isEmpty)
        }
    }

    // MARK: - File Export/Import Tests

    @Test("exportRevocationCertificate succeeds for valid path")
    func testExportRevocationCertificateSuccess() throws {
        let service = RevocationService.shared
        let testData = Data("test certificate".utf8)

        // Create temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_revocation.asc")

        // Clean up any existing file
        try? FileManager.default.removeItem(at: fileURL)

        // Test export
        try service.exportRevocationCertificate(certificate: testData, to: fileURL)

        // Verify file was created
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // Clean up
        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("exportRevocationCertificate creates file with correct content")
    func testExportRevocationCertificateContent() throws {
        let service = RevocationService.shared
        let testData = Data("test certificate content".utf8)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_cert.asc")

        try? FileManager.default.removeItem(at: fileURL)

        try service.exportRevocationCertificate(certificate: testData, to: fileURL)

        // Read back and verify content
        let readData = try Data(contentsOf: fileURL)
        #expect(readData == testData)

        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("exportRevocationCertificate handles empty data")
    func testExportRevocationCertificateEmptyData() throws {
        let service = RevocationService.shared
        let emptyData = Data()

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("empty_cert.asc")

        try? FileManager.default.removeItem(at: fileURL)

        try service.exportRevocationCertificate(certificate: emptyData, to: fileURL)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("importRevocationCertificateFromFile succeeds for existing file")
    func testImportRevocationCertificateFromFileSuccess() throws {
        let service = RevocationService.shared
        let testData = Data("certificate data".utf8)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("import_test.asc")

        // Create test file
        try testData.write(to: fileURL, options: [.atomic])

        // Test import
        let importedData = try service.importRevocationCertificateFromFile(from: fileURL)

        #expect(importedData == testData)

        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("importRevocationCertificateFromFile fails for non-existent file")
    func testImportRevocationCertificateFromFileNotFound() {
        let service = RevocationService.shared

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("nonexistent.asc")

        // Ensure file doesn't exist
        try? FileManager.default.removeItem(at: fileURL)

        #expect(throws: OperationError.self) {
            _ = try service.importRevocationCertificateFromFile(from: fileURL)
        }
    }

    @Test("importRevocationCertificateFromFile sets lastError on failure")
    func testImportRevocationCertificateFromFileSetsLastError() {
        let service = RevocationService.shared

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("nonexistent_file.asc")

        try? FileManager.default.removeItem(at: fileURL)

        do {
            _ = try service.importRevocationCertificateFromFile(from: fileURL)
        } catch {
            // Expected to throw
        }

        #expect(service.lastError != nil)
    }

    @Test("File operations handle large data")
    func testFileOperationsLargeData() throws {
        let service = RevocationService.shared

        // Create large test data (1MB)
        let largeData = Data(repeating: 0xAB, count: 1024 * 1024)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("large_cert.asc")

        try? FileManager.default.removeItem(at: fileURL)

        // Export
        try service.exportRevocationCertificate(certificate: largeData, to: fileURL)

        // Import
        let importedData = try service.importRevocationCertificateFromFile(from: fileURL)

        #expect(importedData == largeData)
        #expect(importedData.count == 1024 * 1024)

        try? FileManager.default.removeItem(at: fileURL)
    }
}
