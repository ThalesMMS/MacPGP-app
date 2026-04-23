import Foundation
import RNPKit
import Testing
@testable import MacPGP

@Suite("PublicKeyExport Tests")
struct PublicKeyExportTests {
    @Test("PublicKeyExport strips secret key material from exported keys")
    func testExportStripsSecretKeyMaterial() throws {
        let keyGenerator = KeyGenerator()
        keyGenerator.keyBitsLength = 2048

        let secretKey = keyGenerator.generate(
            for: "public-export@test.local",
            passphrase: "Password123!"
        )

        let exportedData = try PublicKeyExport.export(secretKey)
        let exportedKeys = try RNP.readKeys(from: exportedData)

        #expect(exportedKeys.count == 1)
        #expect(exportedKeys.first?.isSecret == false)
        #expect(
            exportedKeys.first?.publicKey?.fingerprint.description ==
            secretKey.publicKey?.fingerprint.description
        )
    }

    @Test("Shared projection cleanup reports and removes secret key entries")
    func testSanitizeSharedProjectionDataRemovesSecretKeys() throws {
        let keyGenerator = KeyGenerator()
        keyGenerator.keyBitsLength = 2048

        let secretKey = keyGenerator.generate(
            for: "shared-projection@test.local",
            passphrase: "Password123!"
        )

        let legacyProjection = try secretKey.export()
        let cleanup = try SharedContainerSync.sanitizeSharedProjectionData(legacyProjection)
        let cleanedKeys = try RNP.readKeys(from: cleanup.data)

        #expect(cleanup.removedSecretFingerprints == [secretKey.publicKey?.fingerprint.description ?? "unknown"])
        #expect(cleanedKeys.count == 1)
        #expect(cleanedKeys.first?.isSecret == false)
        #expect(
            cleanedKeys.first?.publicKey?.fingerprint.description ==
            secretKey.publicKey?.fingerprint.description
        )
    }
}
