import Foundation
import RNPKit
import Testing
@testable import MacPGP

@Suite("ServicesProvider Tests")
struct ServicesProviderTests {
    @Test("Services provider reads live keyring mutations")
    func servicesProviderReadsLiveKeyringMutations() throws {
        let keyring = makeIsolatedKeyring()
        let provider = ServicesProvider(keyringService: keyring)

        #expect(provider.availableEncryptionKeys().isEmpty)
        #expect(provider.availableDecryptionKeys().isEmpty)
        #expect(provider.availableSigningKeys().isEmpty)

        let key = makeSecretKey(email: "services-provider-\(UUID().uuidString)@example.com")
        try keyring.addKey(key.rawKey)

        #expect(provider.availableEncryptionKeys().contains { $0.fingerprint == key.fingerprint })
        #expect(provider.availableDecryptionKeys().contains { $0.fingerprint == key.fingerprint })
        #expect(provider.availableSigningKeys().contains { $0.fingerprint == key.fingerprint })

        try keyring.deleteKey(key)

        #expect(provider.availableEncryptionKeys().isEmpty)
        #expect(provider.availableDecryptionKeys().isEmpty)
        #expect(provider.availableSigningKeys().isEmpty)
    }

    private func makeIsolatedKeyring() -> KeyringService {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServicesProviderTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Keyring", isDirectory: true)

        return KeyringService(persistence: KeyringPersistence(directoryOverride: directory))
    }

    private func makeSecretKey(email: String) -> PGPKeyModel {
        let generator = KeyGenerator()
        generator.keyBitsLength = 2048
        return PGPKeyModel(from: generator.generate(for: email, passphrase: "TestPassword123!"))
    }
}
