import Foundation
import ObjectivePGP
import Testing
@testable import MacPGP

private final class BundleToken: NSObject {}

@Suite("PGPKeyModel Tests")
struct PGPKeyModelTests {

    private struct GeneratedKeyFixture {
        let requestedKeySize: Int
        let model: PGPKeyModel
        let packetCreationDate: Date?
        let startedAt: Date
        let finishedAt: Date
    }

    private struct ParsedKeyFixture {
        let model: PGPKeyModel
        let packetCreationDate: Date?
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

        let packetCreationDate = primaryKeyPacket(from: key)?
            .value(forKey: "createDate") as? Date

        return GeneratedKeyFixture(
            requestedKeySize: keySize,
            model: model,
            packetCreationDate: packetCreationDate,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    private func primaryKeyPacket(from key: Key) -> NSObject? {
        key.publicKey?.value(forKey: "primaryKeyPacket") as? NSObject
    }

    private func loadArmoredKeyFixture(named name: String) throws -> ParsedKeyFixture {
        let bundle = Bundle(for: BundleToken.self)
        let fixtureURL = bundle.url(forResource: name, withExtension: "asc", subdirectory: "Resources")
            ?? bundle.url(forResource: name, withExtension: "asc")

        guard let fixtureURL else {
            throw FixtureError.missingFixture(name)
        }

        let data = try Data(contentsOf: fixtureURL)
        let keys = try ObjectivePGP.readKeys(from: data)

        guard let key = keys.first else {
            throw FixtureError.emptyFixture(name)
        }

        return ParsedKeyFixture(
            model: PGPKeyModel(from: key),
            packetCreationDate: primaryKeyPacket(from: key)?.value(forKey: "createDate") as? Date
        )
    }

    // NOTE: ObjectivePGP key generation for ECDSA and EdDSA remains unstable and is
    // already documented in KeyGenerationServiceTests. This suite adds fixture-based
    // EdDSA parsing coverage; ECDSA parsing remains uncovered because the current
    // dependency checkout does not ship an ECDSA fixture and generation still crashes.

    @Test("PGPKeyModel extracts RSA metadata from generated keys", arguments: [2048, 3072, 4096])
    func testExtractsRSAMetadataFromGeneratedKeys(keySize: Int) {
        let fixture = generateRSAKeyFixture(keySize: keySize)

        #expect(fixture.model.algorithm == .rsa)
        #expect(fixture.model.keySize == fixture.requestedKeySize)
        #expect(fixture.packetCreationDate != nil)

        if let packetCreationDate = fixture.packetCreationDate {
            #expect(fixture.model.creationDate == packetCreationDate)
            #expect(fixture.model.creationDate >= fixture.startedAt.addingTimeInterval(-1))
            #expect(fixture.model.creationDate <= fixture.finishedAt.addingTimeInterval(1))
        }
    }

    @Test("PGPKeyModel extracts EdDSA metadata from fixture")
    func testExtractsEdDSAMetadataFromFixture() throws {
        let fixture = try loadArmoredKeyFixture(named: "eddsa_testkey")

        #expect(fixture.model.algorithm == .eddsa)
        #expect(fixture.model.keySize == 256)
        #expect(fixture.packetCreationDate == Date(timeIntervalSince1970: 1_554_440_750))
        #expect(fixture.model.creationDate == fixture.packetCreationDate)
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