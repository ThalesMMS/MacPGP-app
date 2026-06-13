import Foundation
import Testing
@testable import MacPGP

@Suite("PreferencesManager Tests", .serialized)
struct PreferencesManagerTests {
    private enum TestDefaultsKeys {
        static let defaultKeySize = "defaultKeySize"
        static let defaultKeyAlgorithm = "defaultKeyAlgorithm"
        static let backupReminderEnabled = "backupReminderEnabled"
        static let passphraseTimeout = "passphraseTimeout"
        static let appLanguage = "appLanguage"
        static let appleLanguages = "AppleLanguages"
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

    private func cleanupPassphraseTimeoutKey() {
        UserDefaults.standard.removeObject(forKey: TestDefaultsKeys.passphraseTimeout)
    }

    private func preservingLanguageDefaults(_ body: () -> Void) {
        let originalAppLanguage = UserDefaults.standard.object(forKey: TestDefaultsKeys.appLanguage)
        let originalAppleLanguages = UserDefaults.standard.object(forKey: TestDefaultsKeys.appleLanguages)

        defer {
            restore(originalAppLanguage, forKey: TestDefaultsKeys.appLanguage)
            restore(originalAppleLanguages, forKey: TestDefaultsKeys.appleLanguages)
        }

        body()
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
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

    // MARK: - passphraseTimeoutMinutes

    @Test("passphraseTimeoutMinutes defaults to 10 when unset")
    func testPassphraseTimeoutDefaultsToTenWhenUnset() {
        defer { cleanupPassphraseTimeoutKey() }

        UserDefaults.standard.removeObject(forKey: TestDefaultsKeys.passphraseTimeout)

        #expect(PreferencesManager.shared.passphraseTimeoutMinutes == 10)
    }

    @Test("passphraseTimeoutMinutes preserves zero as never clear")
    func testPassphraseTimeoutPreservesZero() {
        defer { cleanupPassphraseTimeoutKey() }

        PreferencesManager.shared.passphraseTimeoutMinutes = 0

        #expect(PreferencesManager.shared.passphraseTimeoutMinutes == 0)
    }

    @Test("passphraseTimeoutMinutes preserves positive timeout values")
    func testPassphraseTimeoutPreservesPositiveValues() {
        defer { cleanupPassphraseTimeoutKey() }

        for timeout in [5, 10, 30, 60] {
            PreferencesManager.shared.passphraseTimeoutMinutes = timeout
            #expect(PreferencesManager.shared.passphraseTimeoutMinutes == timeout)
        }
    }

    // MARK: - appLanguage

    @Test("appLanguage getter does not mutate appLanguage or AppleLanguages defaults")
    func appLanguageGetterDoesNotMutateLanguageDefaults() {
        preservingLanguageDefaults {
            let sentinelAppleLanguages = ["zz-Test"]
            UserDefaults.standard.removeObject(forKey: TestDefaultsKeys.appLanguage)
            UserDefaults.standard.set(sentinelAppleLanguages, forKey: TestDefaultsKeys.appleLanguages)

            let language = PreferencesManager.shared.appLanguage

            #expect(AppLanguage.allCases.contains(language))
            #expect(UserDefaults.standard.object(forKey: TestDefaultsKeys.appLanguage) == nil)
            #expect(UserDefaults.standard.stringArray(forKey: TestDefaultsKeys.appleLanguages) == sentinelAppleLanguages)
        }
    }

    @Test("appLanguage setter persists preference and applies AppleLanguages")
    func appLanguageSetterPersistsAndAppliesLanguage() {
        preservingLanguageDefaults {
            PreferencesManager.shared.appLanguage = .german

            #expect(UserDefaults.standard.string(forKey: TestDefaultsKeys.appLanguage) == AppLanguage.german.rawValue)
            #expect(UserDefaults.standard.stringArray(forKey: TestDefaultsKeys.appleLanguages) == [AppLanguage.german.rawValue])
        }
    }
}
