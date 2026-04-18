import Foundation
import Testing
@testable import MacPGP

@Suite("PreferencesManager Tests", .serialized)
struct PreferencesManagerTests {
    private enum TestDefaultsKeys {
        static let defaultKeySize = "defaultKeySize"
        static let defaultKeyAlgorithm = "defaultKeyAlgorithm"
    }

    // MARK: - Helpers

    /// Cleans up the test keys we touch so tests don't bleed into each other.
    private func cleanupKeySizeKey() {
        UserDefaults.standard.removeObject(forKey: TestDefaultsKeys.defaultKeySize)
    }

    private func cleanupAlgorithmKey() {
        UserDefaults.standard.removeObject(forKey: TestDefaultsKeys.defaultKeyAlgorithm)
    }

    // MARK: - defaultKeyAlgorithm

    @Test("defaultKeyAlgorithm getter always returns RSA regardless of stored value")
    func testDefaultKeyAlgorithmGetterAlwaysReturnsRSA() {
        defer { cleanupAlgorithmKey() }

        // Even if some other value was previously stored, the getter is hardcoded to .rsa
        UserDefaults.standard.set("ECDSA", forKey: TestDefaultsKeys.defaultKeyAlgorithm)
        #expect(PreferencesManager.shared.defaultKeyAlgorithm == .rsa)

        UserDefaults.standard.set("EdDSA", forKey: TestDefaultsKeys.defaultKeyAlgorithm)
        #expect(PreferencesManager.shared.defaultKeyAlgorithm == .rsa)
    }

    @Test("defaultKeyAlgorithm getter returns RSA when no value is stored")
    func testDefaultKeyAlgorithmGetterReturnRSAWithNoStoredValue() {
        defer { cleanupAlgorithmKey() }

        UserDefaults.standard.removeObject(forKey: TestDefaultsKeys.defaultKeyAlgorithm)
        #expect(PreferencesManager.shared.defaultKeyAlgorithm == .rsa)
    }

    @Test("defaultKeyAlgorithm setter preserves the assigned raw value for future compatibility")
    func testDefaultKeyAlgorithmSetterPreservesAssignedRawValueForECDSA() {
        defer { cleanupAlgorithmKey() }

        // The release UI always reads back RSA, but the stored raw value is preserved so
        // this preference can round-trip once non-RSA algorithms are re-enabled.
        PreferencesManager.shared.defaultKeyAlgorithm = .ecdsa
        let stored = UserDefaults.standard.string(forKey: TestDefaultsKeys.defaultKeyAlgorithm)
        #expect(stored == KeyAlgorithm.ecdsa.rawValue)
    }

    @Test("defaultKeyAlgorithm setter stores RSA when explicitly set to RSA")
    func testDefaultKeyAlgorithmSetterStoresRSA() {
        defer { cleanupAlgorithmKey() }

        PreferencesManager.shared.defaultKeyAlgorithm = .rsa
        let stored = UserDefaults.standard.string(forKey: TestDefaultsKeys.defaultKeyAlgorithm)
        #expect(stored == KeyAlgorithm.rsa.rawValue)
    }

    // MARK: - defaultKeySize

    @Test("defaultKeySize returns RSA default when no value is stored")
    func testDefaultKeySizeReturnsDefaultWhenNotSet() {
        defer { cleanupKeySizeKey() }

        UserDefaults.standard.removeObject(forKey: TestDefaultsKeys.defaultKeySize)
        #expect(PreferencesManager.shared.defaultKeySize == KeyAlgorithm.rsa.defaultKeySize)
    }

    @Test("defaultKeySize returns stored value when it is a valid RSA key size")
    func testDefaultKeySizeReturnsValidStoredSize() {
        defer { cleanupKeySizeKey() }

        for size in KeyAlgorithm.rsa.supportedKeySizes {
            UserDefaults.standard.set(size, forKey: TestDefaultsKeys.defaultKeySize)
            #expect(PreferencesManager.shared.defaultKeySize == size)
        }
    }

    @Test("defaultKeySize returns RSA default when stored value is not a supported RSA size")
    func testDefaultKeySizeReturnsDefaultForUnsupportedStoredValue() {
        defer { cleanupKeySizeKey() }

        // 1024 is not in [2048, 3072, 4096]
        UserDefaults.standard.set(1024, forKey: TestDefaultsKeys.defaultKeySize)
        #expect(PreferencesManager.shared.defaultKeySize == KeyAlgorithm.rsa.defaultKeySize)
    }

    @Test("defaultKeySize returns RSA default when stored value is zero")
    func testDefaultKeySizeReturnsDefaultForZeroStoredValue() {
        defer { cleanupKeySizeKey() }

        UserDefaults.standard.set(0, forKey: TestDefaultsKeys.defaultKeySize)
        #expect(PreferencesManager.shared.defaultKeySize == KeyAlgorithm.rsa.defaultKeySize)
    }

    @Test("defaultKeySize setter persists valid RSA key size")
    func testDefaultKeySizeSetterPersistsValidSize() {
        defer { cleanupKeySizeKey() }

        PreferencesManager.shared.defaultKeySize = 2048
        #expect(UserDefaults.standard.integer(forKey: TestDefaultsKeys.defaultKeySize) == 2048)

        PreferencesManager.shared.defaultKeySize = 3072
        #expect(UserDefaults.standard.integer(forKey: TestDefaultsKeys.defaultKeySize) == 3072)
    }

    @Test("defaultKeySize setter normalizes unsupported size to RSA default")
    func testDefaultKeySizeSetterNormalizesInvalidSize() {
        defer { cleanupKeySizeKey() }

        // 512 is not a valid RSA key size
        PreferencesManager.shared.defaultKeySize = 512
        #expect(UserDefaults.standard.integer(forKey: TestDefaultsKeys.defaultKeySize) == KeyAlgorithm.rsa.defaultKeySize)
    }

    @Test("defaultKeySize setter normalizes non-RSA ECDSA size to RSA default")
    func testDefaultKeySizeSetterNormalizesECDSASize() {
        defer { cleanupKeySizeKey() }

        // 256 is valid for ECDSA but not for RSA
        PreferencesManager.shared.defaultKeySize = 256
        #expect(UserDefaults.standard.integer(forKey: TestDefaultsKeys.defaultKeySize) == KeyAlgorithm.rsa.defaultKeySize)
    }

    @Test("defaultKeySize getter returns after round-trip through setter")
    func testDefaultKeySizeRoundTrip() {
        defer { cleanupKeySizeKey() }

        for size in KeyAlgorithm.rsa.supportedKeySizes {
            PreferencesManager.shared.defaultKeySize = size
            #expect(PreferencesManager.shared.defaultKeySize == size)
        }
    }
}
