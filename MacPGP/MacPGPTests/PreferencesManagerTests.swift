import Foundation
import Testing
@testable import MacPGP

@Suite("PreferencesManager Tests", .serialized)
struct PreferencesManagerTests {
    private enum TestDefaultsKeys {
        static let defaultKeySize = "defaultKeySize"
        static let defaultKeyAlgorithm = "defaultKeyAlgorithm"
        static let backupReminderEnabled = "backupReminderEnabled"
    }

    // MARK: - Helpers

    /// Cleans up the test keys we touch so tests don't bleed into each other.
    private func cleanupKeySizeKey() {
        UserDefaults.standard.removeObject(forKey: TestDefaultsKeys.defaultKeySize)
    }

    private func cleanupAlgorithmKey() {
        UserDefaults.standard.removeObject(forKey: TestDefaultsKeys.defaultKeyAlgorithm)
    }

    private func cleanupBackupReminderEnabledKey() {
        UserDefaults.standard.removeObject(forKey: TestDefaultsKeys.backupReminderEnabled)
    }

    // MARK: - defaultKeyAlgorithm

    @Test("defaultKeyAlgorithm getter returns supported stored values")
    func testDefaultKeyAlgorithmGetterReturnsStoredValue() {
        defer { cleanupAlgorithmKey() }

        UserDefaults.standard.set("ECDSA", forKey: TestDefaultsKeys.defaultKeyAlgorithm)
        #expect(PreferencesManager.shared.defaultKeyAlgorithm == .ecdsa)

        UserDefaults.standard.set("EdDSA", forKey: TestDefaultsKeys.defaultKeyAlgorithm)
        #expect(PreferencesManager.shared.defaultKeyAlgorithm == .eddsa)
    }

    @Test("defaultKeyAlgorithm getter returns RSA when no value is stored")
    func testDefaultKeyAlgorithmGetterReturnRSAWithNoStoredValue() {
        defer { cleanupAlgorithmKey() }

        UserDefaults.standard.removeObject(forKey: TestDefaultsKeys.defaultKeyAlgorithm)
        #expect(PreferencesManager.shared.defaultKeyAlgorithm == .rsa)
    }

    @Test("defaultKeyAlgorithm setter persists the assigned algorithm")
    func testDefaultKeyAlgorithmSetterPreservesAssignedRawValueForECDSA() {
        defer {
            cleanupAlgorithmKey()
            cleanupKeySizeKey()
        }

        PreferencesManager.shared.defaultKeyAlgorithm = .ecdsa
        let stored = UserDefaults.standard.string(forKey: TestDefaultsKeys.defaultKeyAlgorithm)
        #expect(stored == KeyAlgorithm.ecdsa.rawValue)
        #expect(PreferencesManager.shared.defaultKeyAlgorithm == .ecdsa)
    }

    @Test("defaultKeyAlgorithm setter stores RSA when explicitly set to RSA")
    func testDefaultKeyAlgorithmSetterStoresRSA() {
        defer { cleanupAlgorithmKey() }

        PreferencesManager.shared.defaultKeyAlgorithm = .rsa
        let stored = UserDefaults.standard.string(forKey: TestDefaultsKeys.defaultKeyAlgorithm)
        #expect(stored == KeyAlgorithm.rsa.rawValue)
    }

    @Test("defaultKeyAlgorithm setter normalizes unsupported algorithms to RSA")
    func testDefaultKeyAlgorithmSetterNormalizesUnsupportedAlgorithm() {
        defer {
            cleanupAlgorithmKey()
            cleanupKeySizeKey()
        }

        UserDefaults.standard.set(2048, forKey: TestDefaultsKeys.defaultKeySize)

        PreferencesManager.shared.defaultKeyAlgorithm = .dsa

        let storedAlgorithm = UserDefaults.standard.string(forKey: TestDefaultsKeys.defaultKeyAlgorithm)
        let storedKeySize = UserDefaults.standard.integer(forKey: TestDefaultsKeys.defaultKeySize)
        #expect(storedAlgorithm == KeyAlgorithm.rsa.rawValue)
        #expect(storedKeySize == 2048)
        #expect(PreferencesManager.shared.defaultKeyAlgorithm == .rsa)
    }

    // MARK: - defaultKeySize

    @Test("defaultKeySize returns current algorithm default when no value is stored")
    func testDefaultKeySizeReturnsDefaultWhenNotSet() {
        defer {
            cleanupAlgorithmKey()
            cleanupKeySizeKey()
        }

        PreferencesManager.shared.defaultKeyAlgorithm = .rsa
        UserDefaults.standard.removeObject(forKey: TestDefaultsKeys.defaultKeySize)
        #expect(PreferencesManager.shared.defaultKeySize == KeyAlgorithm.rsa.defaultKeySize)
    }

    @Test("defaultKeySize returns stored value when it is valid for the selected algorithm")
    func testDefaultKeySizeReturnsValidStoredSize() {
        defer {
            cleanupAlgorithmKey()
            cleanupKeySizeKey()
        }

        PreferencesManager.shared.defaultKeyAlgorithm = .ecdsa

        for size in KeyAlgorithm.ecdsa.supportedKeySizes {
            UserDefaults.standard.set(size, forKey: TestDefaultsKeys.defaultKeySize)
            #expect(PreferencesManager.shared.defaultKeySize == size)
        }
    }

    @Test("defaultKeySize returns current algorithm default when stored value is unsupported")
    func testDefaultKeySizeReturnsDefaultForUnsupportedStoredValue() {
        defer {
            cleanupAlgorithmKey()
            cleanupKeySizeKey()
        }

        PreferencesManager.shared.defaultKeyAlgorithm = .eddsa
        UserDefaults.standard.set(1024, forKey: TestDefaultsKeys.defaultKeySize)
        #expect(PreferencesManager.shared.defaultKeySize == KeyAlgorithm.eddsa.defaultKeySize)
    }

    @Test("defaultKeySize returns current algorithm default when stored value is zero")
    func testDefaultKeySizeReturnsDefaultForZeroStoredValue() {
        defer {
            cleanupAlgorithmKey()
            cleanupKeySizeKey()
        }

        PreferencesManager.shared.defaultKeyAlgorithm = .ecdsa
        UserDefaults.standard.set(0, forKey: TestDefaultsKeys.defaultKeySize)
        #expect(PreferencesManager.shared.defaultKeySize == KeyAlgorithm.ecdsa.defaultKeySize)
    }

    @Test("defaultKeySize setter persists valid size for selected algorithm")
    func testDefaultKeySizeSetterPersistsValidSize() {
        defer {
            cleanupAlgorithmKey()
            cleanupKeySizeKey()
        }

        PreferencesManager.shared.defaultKeyAlgorithm = .ecdsa
        PreferencesManager.shared.defaultKeySize = 384
        #expect(UserDefaults.standard.integer(forKey: TestDefaultsKeys.defaultKeySize) == 384)

        PreferencesManager.shared.defaultKeySize = 521
        #expect(UserDefaults.standard.integer(forKey: TestDefaultsKeys.defaultKeySize) == 521)
    }

    @Test("defaultKeySize setter normalizes unsupported size to current algorithm default")
    func testDefaultKeySizeSetterNormalizesInvalidSize() {
        defer {
            cleanupAlgorithmKey()
            cleanupKeySizeKey()
        }

        PreferencesManager.shared.defaultKeyAlgorithm = .eddsa
        PreferencesManager.shared.defaultKeySize = 512
        #expect(UserDefaults.standard.integer(forKey: TestDefaultsKeys.defaultKeySize) == KeyAlgorithm.eddsa.defaultKeySize)
    }

    @Test("changing the default algorithm normalizes incompatible stored size")
    func testDefaultKeyAlgorithmNormalizesStoredKeySize() {
        defer {
            cleanupAlgorithmKey()
            cleanupKeySizeKey()
        }

        UserDefaults.standard.set(4096, forKey: TestDefaultsKeys.defaultKeySize)
        PreferencesManager.shared.defaultKeyAlgorithm = .eddsa

        #expect(UserDefaults.standard.integer(forKey: TestDefaultsKeys.defaultKeySize) == KeyAlgorithm.eddsa.defaultKeySize)
    }

    @Test("defaultKeySize getter returns after round-trip through setter")
    func testDefaultKeySizeRoundTrip() {
        defer {
            cleanupAlgorithmKey()
            cleanupKeySizeKey()
        }

        PreferencesManager.shared.defaultKeyAlgorithm = .rsa

        for size in KeyAlgorithm.rsa.supportedKeySizes {
            PreferencesManager.shared.defaultKeySize = size
            #expect(PreferencesManager.shared.defaultKeySize == size)
        }
    }

    // MARK: - backupReminderEnabled

    @Test("backupReminderEnabled defaults off until user opts in")
    func testBackupReminderEnabledDefaultsOff() {
        defer { cleanupBackupReminderEnabledKey() }

        UserDefaults.standard.removeObject(forKey: TestDefaultsKeys.backupReminderEnabled)
        #expect(PreferencesManager.shared.backupReminderEnabled == false)
    }

    @Test("backupReminderEnabled persists enabled and disabled values")
    func testBackupReminderEnabledRoundTripPersistence() {
        defer { cleanupBackupReminderEnabledKey() }

        PreferencesManager.shared.backupReminderEnabled = true
        #expect(PreferencesManager.shared.backupReminderEnabled == true)

        PreferencesManager.shared.backupReminderEnabled = false
        #expect(PreferencesManager.shared.backupReminderEnabled == false)
    }
}
