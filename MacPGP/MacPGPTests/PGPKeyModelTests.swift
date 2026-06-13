import Foundation
import RNPKit
import Testing
@testable import MacPGP

private final class BundleToken: NSObject {}

@Suite("PGPKeyModel Tests")
struct PGPKeyModelTests {

    private struct GeneratedKeyFixture {
        let requestedKeySize: Int
        let model: PGPKeyModel
        let metadataCreationDate: Date
        let startedAt: Date
        let finishedAt: Date
    }

    private struct ParsedKeyFixture {
        let model: PGPKeyModel
        let metadataCreationDate: Date
    }

    private enum FixtureError: Error {
        case missingFixture(String)
        case emptyFixture(String)
    }

    private func generateRSAKeyFixture(keySize: Int) -> GeneratedKeyFixture {
        let keyGenerator = KeyGenerator()
        keyGenerator.keyAlgorithm = .RSA
        keyGenerator.keyBitsLength = Int32(keySize)

        let startedAt = Date()
        let key = keyGenerator.generate(
            for: "pgp-key-model-\(keySize)-\(UUID().uuidString)@example.com",
            passphrase: "TestPassword123!"
        )
        let model = PGPKeyModel(from: key)
        let finishedAt = Date()

        return GeneratedKeyFixture(
            requestedKeySize: keySize,
            model: model,
            metadataCreationDate: key.metadata.creationDate,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    private func generateKeyFixture(expirationDate: Date) throws -> PGPKeyModel {
        let passphrase = "TestPassword123!"
        let keyGenerator = KeyGenerator()
        keyGenerator.keyBitsLength = 2048
        let key = keyGenerator.generate(
            for: "pgp-key-expiration-\(UUID().uuidString)@example.com",
            passphrase: passphrase
        )
        let expiringKey = try key.setExpiration(
            expirationDate,
            passphraseForKey: { _ in passphrase }
        )
        return PGPKeyModel(from: expiringKey)
    }

    private func expectWarningLevel(
        _ actual: ExpirationWarningLevel,
        is expected: ExpirationWarningLevel,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        switch (actual, expected) {
        case (.none, .none),
             (.warning, .warning),
             (.critical, .critical),
             (.expired, .expired):
            return
        default:
            Issue.record("Expected \(expected), got \(actual)", sourceLocation: sourceLocation)
        }
    }

    private func loadArmoredKeyFixture(named name: String) throws -> ParsedKeyFixture {
        let bundle = Bundle(for: BundleToken.self)
        let fixtureURL = bundle.url(forResource: name, withExtension: "asc", subdirectory: "Resources")
            ?? bundle.url(forResource: name, withExtension: "asc")

        guard let fixtureURL else {
            throw FixtureError.missingFixture(name)
        }

        let data = try Data(contentsOf: fixtureURL)
        let keys = try RNP.readKeys(from: data)

        guard let key = keys.first else {
            throw FixtureError.emptyFixture(name)
        }

        return ParsedKeyFixture(
            model: PGPKeyModel(from: key),
            metadataCreationDate: key.metadata.creationDate
        )
    }

    @Test("PGPKeyModel extracts RSA metadata from generated keys", arguments: [2048, 3072, 4096])
    func testExtractsRSAMetadataFromGeneratedKeys(keySize: Int) {
        let fixture = generateRSAKeyFixture(keySize: keySize)

        #expect(fixture.model.algorithm == .rsa)
        #expect(fixture.model.keySize == fixture.requestedKeySize)
        #expect(fixture.model.creationDate == fixture.metadataCreationDate)
        #expect(fixture.model.creationDate >= fixture.startedAt.addingTimeInterval(-1))
        #expect(fixture.model.creationDate <= fixture.finishedAt.addingTimeInterval(1))
    }

    @Test("PGPKeyModel extracts EdDSA metadata from fixture")
    func testExtractsEdDSAMetadataFromFixture() throws {
        let fixture = try loadArmoredKeyFixture(named: "eddsa_testkey")

        #expect(fixture.model.algorithm == .eddsa)
        #expect(fixture.model.keySize == 256)
        #expect(fixture.metadataCreationDate == Date(timeIntervalSince1970: 1_554_440_750))
        #expect(fixture.model.creationDate == fixture.metadataCreationDate)
        #expect(fixture.model.expirationDate == nil)
        #expect(fixture.model.primaryUserID?.name == "Alice")
        #expect(fixture.model.primaryUserID?.comment == "Test ecc key")
        #expect(fixture.model.email == "alice@example.org")
    }

    @Test("PGPKeyModel algorithmDescription matches extracted metadata")
    func testAlgorithmDescriptionMatchesExtractedMetadata() {
        let fixture = generateRSAKeyFixture(keySize: 2048)

        #expect(fixture.model.algorithmDescription == "RSA 2048")
    }

    @Test("PGPKeyModel treats keys expiring later today as critical, not expired")
    func testExpirationWarningLevelForKeyExpiringLaterToday() throws {
        let now = Date()
        guard let today = Calendar.current.dateInterval(of: .day, for: now) else {
            Issue.record("Could not resolve current day interval")
            return
        }
        let laterToday = today.end.addingTimeInterval(-60)

        guard laterToday > now else {
            Issue.record("Could not choose a future time later today")
            return
        }

        let model = try generateKeyFixture(expirationDate: laterToday)

        #expect(model.isExpired == false)
        #expect(model.daysUntilExpiration == 0)
        expectWarningLevel(model.expirationWarningLevel, is: .critical)
    }

    @Test("PGPKeyModel treats keys expiring tomorrow as one day away")
    func testDaysUntilExpirationForKeyExpiringTomorrow() throws {
        let now = Date()
        let calendar = Calendar.current
        guard let tomorrow = calendar.dateInterval(of: .day, for: now)?.end.addingTimeInterval(60) else {
            Issue.record("Could not resolve tomorrow boundary")
            return
        }

        let model = try generateKeyFixture(expirationDate: tomorrow)

        #expect(model.isExpired == false)
        #expect(model.daysUntilExpiration == 1)
        expectWarningLevel(model.expirationWarningLevel, is: .critical)
    }

    @Test("PGPKeyModel keeps expired keys expired")
    func testExpirationWarningLevelForExpiredKey() throws {
        let model = try generateKeyFixture(expirationDate: Date().addingTimeInterval(3600))
        let expiredModel = PGPKeyModel(copying: model, isExpired: true)

        expectWarningLevel(expiredModel.expirationWarningLevel, is: .expired)
    }

    // MARK: - Copying Initializer with trustLevel Tests

    @Test("Copying init preserves all properties when no overrides provided")
    func testCopyingInitPreservesAllProperties() {
        let fixture = generateRSAKeyFixture(keySize: 2048)
        let original = fixture.model

        let copied = PGPKeyModel(copying: original)

        #expect(copied.id == original.id)
        #expect(copied.fingerprint == original.fingerprint)
        #expect(copied.shortKeyID == original.shortKeyID)
        #expect(copied.algorithm == original.algorithm)
        #expect(copied.keySize == original.keySize)
        #expect(copied.creationDate == original.creationDate)
        #expect(copied.isSecretKey == original.isSecretKey)
        #expect(copied.isExpired == original.isExpired)
        #expect(copied.isRevoked == original.isRevoked)
        #expect(copied.trustLevel == original.trustLevel)
    }

    @Test("Copying init overrides trustLevel when explicitly provided")
    func testCopyingInitOverridesTrustLevel() {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let rawKey = keyGen.generate(for: "trust-override@test.local", passphrase: "pass")
        let original = PGPKeyModel(
            from: rawKey,
            isVerified: false,
            verificationDate: nil,
            verificationMethod: nil,
            trustLevel: .unknown
        )

        let copied = PGPKeyModel(copying: original, trustLevel: .full)

        #expect(copied.trustLevel == .full)
        #expect(original.trustLevel == .unknown)
    }

    @Test("Copying init uses source trustLevel when nil override provided")
    func testCopyingInitUsesSourceTrustLevelWhenNilOverride() {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let rawKey = keyGen.generate(for: "trust-nil-override@test.local", passphrase: "pass")
        let original = PGPKeyModel(
            from: rawKey,
            isVerified: false,
            verificationDate: nil,
            verificationMethod: nil,
            trustLevel: .marginal
        )

        let copied = PGPKeyModel(copying: original, trustLevel: nil)

        #expect(copied.trustLevel == .marginal)
    }

    @Test("Copying init can set each supported trust level")
    func testCopyingInitAllTrustLevels() {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let rawKey = keyGen.generate(for: "trust-all-levels@test.local", passphrase: "pass")
        let original = PGPKeyModel(from: rawKey)

        let trustLevels: [TrustLevel] = [.unknown, .never, .marginal, .full, .ultimate]

        for level in trustLevels {
            let copied = PGPKeyModel(copying: original, trustLevel: level)
            #expect(copied.trustLevel == level)
        }
    }

    @Test("Copying init trustLevel override does not affect other properties")
    func testCopyingInitTrustLevelOverridePreservesOtherProperties() {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let rawKey = keyGen.generate(for: "trust-identity-preserved@test.local", passphrase: "pass")
        let original = PGPKeyModel(
            from: rawKey,
            isVerified: true,
            verificationDate: Date(),
            verificationMethod: .inPerson,
            trustLevel: .marginal
        )

        let copied = PGPKeyModel(copying: original, trustLevel: .ultimate)

        #expect(copied.trustLevel == .ultimate)
        #expect(copied.fingerprint == original.fingerprint)
        #expect(copied.isVerified == original.isVerified)
        #expect(copied.verificationMethod == original.verificationMethod)
        #expect(copied.id == original.id)
    }
}
