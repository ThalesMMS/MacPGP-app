import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case portuguese = "pt"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .portuguese: return "Português"
        case .chinese: return "中文"
        }
    }
}

@Observable
final class PreferencesManager {
    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let defaultKeyAlgorithm = "defaultKeyAlgorithm"
        static let defaultKeySize = "defaultKeySize"
        static let defaultKeyExpiration = "defaultKeyExpiration"
        static let rememberPassphrase = "rememberPassphrase"
        static let passphraseTimeout = "passphraseTimeout"
        static let showKeyIDInList = "showKeyIDInList"
        static let confirmBeforeDelete = "confirmBeforeDelete"
        static let autoSaveKeyring = "autoSaveKeyring"
        static let armorOutput = "armorOutput"
        static let lastBackupDate = "lastBackupDate"
        static let backupReminderEnabled = "backupReminderEnabled"
        static let backupReminderIntervalDays = "backupReminderIntervalDays"
        static let defaultKeyServer = "defaultKeyServer"
        static let keyServerTimeout = "keyServerTimeout"
        static let autoRefreshKeys = "autoRefreshKeys"
        static let appLanguage = "appLanguage"
    }

    var defaultKeyAlgorithm: KeyAlgorithm {
        get {
            guard let value = defaults.string(forKey: Keys.defaultKeyAlgorithm) else {
                return .rsa
            }
            return KeyAlgorithm(rawValue: value) ?? .rsa
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.defaultKeyAlgorithm)
        }
    }

    var defaultKeySize: Int {
        get { defaults.integer(forKey: Keys.defaultKeySize).nonZeroOr(4096) }
        set { defaults.set(newValue, forKey: Keys.defaultKeySize) }
    }

    var defaultKeyExpirationMonths: Int {
        get { defaults.integer(forKey: Keys.defaultKeyExpiration).nonZeroOr(24) }
        set { defaults.set(newValue, forKey: Keys.defaultKeyExpiration) }
    }

    var rememberPassphrase: Bool {
        get { defaults.bool(forKey: Keys.rememberPassphrase) }
        set { defaults.set(newValue, forKey: Keys.rememberPassphrase) }
    }

    var passphraseTimeoutMinutes: Int {
        get { defaults.integer(forKey: Keys.passphraseTimeout).nonZeroOr(10) }
        set { defaults.set(newValue, forKey: Keys.passphraseTimeout) }
    }

    var showKeyIDInList: Bool {
        get {
            if defaults.object(forKey: Keys.showKeyIDInList) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.showKeyIDInList)
        }
        set { defaults.set(newValue, forKey: Keys.showKeyIDInList) }
    }

    var confirmBeforeDelete: Bool {
        get {
            if defaults.object(forKey: Keys.confirmBeforeDelete) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.confirmBeforeDelete)
        }
        set { defaults.set(newValue, forKey: Keys.confirmBeforeDelete) }
    }

    var autoSaveKeyring: Bool {
        get {
            if defaults.object(forKey: Keys.autoSaveKeyring) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.autoSaveKeyring)
        }
        set { defaults.set(newValue, forKey: Keys.autoSaveKeyring) }
    }

    var armorOutput: Bool {
        get {
            if defaults.object(forKey: Keys.armorOutput) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.armorOutput)
        }
        set { defaults.set(newValue, forKey: Keys.armorOutput) }
    }

    var lastBackupDate: Date? {
        get { defaults.object(forKey: Keys.lastBackupDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastBackupDate) }
    }

    var backupReminderEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.backupReminderEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.backupReminderEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.backupReminderEnabled) }
    }

    var backupReminderIntervalDays: Int {
        get { defaults.integer(forKey: Keys.backupReminderIntervalDays).nonZeroOr(30) }
        set { defaults.set(newValue, forKey: Keys.backupReminderIntervalDays) }
    }

    var defaultKeyServer: String {
        get {
            guard let value = defaults.string(forKey: Keys.defaultKeyServer) else {
                return "keys.openpgp.org"
            }
            return value
        }
        set {
            defaults.set(newValue, forKey: Keys.defaultKeyServer)
        }
    }

    var keyServerTimeout: Int {
        get { defaults.integer(forKey: Keys.keyServerTimeout).nonZeroOr(30) }
        set { defaults.set(newValue, forKey: Keys.keyServerTimeout) }
    }

    var autoRefreshKeys: Bool {
        get { defaults.bool(forKey: Keys.autoRefreshKeys) }
        set { defaults.set(newValue, forKey: Keys.autoRefreshKeys) }
    }

    var appLanguage: AppLanguage {
        get {
            // Check if language has been explicitly set
            if defaults.object(forKey: Keys.appLanguage) == nil {
                // First launch - auto-detect from system and save as preference
                let detectedLanguage = detectSystemLanguage()
                defaults.set(detectedLanguage.rawValue, forKey: Keys.appLanguage)
                applyLanguage(detectedLanguage)
                return detectedLanguage
            }

            guard let value = defaults.string(forKey: Keys.appLanguage) else {
                return .english
            }
            return AppLanguage(rawValue: value) ?? .english
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.appLanguage)
            applyLanguage(newValue)
        }
    }

    /// Apply the selected language to the application
    /// This sets the AppleLanguages user default which affects String(localized:) and NSLocalizedString
    private func applyLanguage(_ language: AppLanguage) {
        // Set the language override in UserDefaults
        // This is the standard way to override app language without changing system settings
        defaults.set([language.rawValue], forKey: "AppleLanguages")
        defaults.synchronize()

        // Note: For the language change to take full effect, some UI elements may require
        // the app to restart or views to be recreated. SwiftUI views will generally
        // pick up the change on next render.
    }

    private init() {
        // Apply the saved language preference on initialization
        // This ensures the app starts with the correct language
        let currentLanguage = appLanguage
        applyLanguage(currentLanguage)
    }

    private func detectSystemLanguage() -> AppLanguage {
        // Get the system's preferred languages
        let preferredLanguages = Locale.preferredLanguages

        // Try to match the first preferred language to our supported languages
        for languageIdentifier in preferredLanguages {
            // Extract the language code (e.g., "en-US" -> "en", "zh-Hans-CN" -> "zh-Hans")
            let locale = Locale(identifier: languageIdentifier)
            guard let languageCode = locale.language.languageCode?.identifier else {
                continue
            }

            // Check for script code for Chinese (simplified vs traditional)
            let scriptCode = locale.language.script?.identifier

            // Match to our supported languages
            switch languageCode {
            case "en":
                return .english
            case "es":
                return .spanish
            case "fr":
                return .french
            case "de":
                return .german
            case "pt":
                return .portuguese
            case "zh":
                // For Chinese, check if it's Simplified (Hans)
                if scriptCode == "Hans" || scriptCode == nil {
                    return .chinese
                }
                // We only support Simplified Chinese, but still return it for Traditional
                return .chinese
            default:
                continue
            }
        }

        // Default to English if no match found
        return .english
    }

    func resetToDefaults() {
        let domain = Bundle.main.bundleIdentifier ?? "com.macpgp"
        defaults.removePersistentDomain(forName: domain)
    }
}

private extension Int {
    func nonZeroOr(_ defaultValue: Int) -> Int {
        self == 0 ? defaultValue : self
    }
}
