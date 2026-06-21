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

    var locale: Locale {
        Locale(identifier: rawValue)
    }
}

@Observable
final class PreferencesManager {
    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard
    private var selectedAppLanguage: AppLanguage

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
        static let lastBackupReminderDate = "lastBackupReminderDate"
        static let backupReminderEnabled = "backupReminderEnabled"
        static let backupReminderIntervalDays = "backupReminderIntervalDays"
        static let defaultKeyServer = "defaultKeyServer"
        static let enabledKeyServers = "enabledKeyServers"
        static let keyServerTimeout = "keyServerTimeout"
        static let insecureKeyServersAllowed = "insecureKeyServersAllowed"
        static let appLanguage = "appLanguage"
    }

    var defaultKeyAlgorithm: KeyAlgorithm {
        get {
            guard let rawValue = defaults.string(forKey: Keys.defaultKeyAlgorithm),
                  let algorithm = KeyAlgorithm(rawValue: rawValue),
                  [.rsa, .ecdsa, .eddsa].contains(algorithm) else {
                return .rsa
            }
            return algorithm
        }
        set {
            let normalizedAlgorithm = Self.normalizedDefaultKeyAlgorithm(newValue)
            defaults.set(normalizedAlgorithm.rawValue, forKey: Keys.defaultKeyAlgorithm)

            let storedSize = defaults.integer(forKey: Keys.defaultKeySize)
            if !normalizedAlgorithm.supportedKeySizes.contains(storedSize) {
                defaults.set(normalizedAlgorithm.defaultKeySize, forKey: Keys.defaultKeySize)
            }
        }
    }

    var defaultKeySize: Int {
        get {
            let storedSize = defaults.integer(forKey: Keys.defaultKeySize)
                .nonZeroOr(defaultKeyAlgorithm.defaultKeySize)
            return defaultKeyAlgorithm.supportedKeySizes.contains(storedSize)
                ? storedSize
                : defaultKeyAlgorithm.defaultKeySize
        }
        set {
            let normalizedSize = defaultKeyAlgorithm.supportedKeySizes.contains(newValue)
                ? newValue
                : defaultKeyAlgorithm.defaultKeySize
            defaults.set(normalizedSize, forKey: Keys.defaultKeySize)
        }
    }

    var defaultKeyExpirationMonths: Int {
        get {
            if defaults.object(forKey: Keys.defaultKeyExpiration) == nil {
                return 24
            }
            return defaults.integer(forKey: Keys.defaultKeyExpiration)
        }
        set { defaults.set(newValue, forKey: Keys.defaultKeyExpiration) }
    }

    var rememberPassphrase: Bool {
        get { defaults.bool(forKey: Keys.rememberPassphrase) }
        set { defaults.set(newValue, forKey: Keys.rememberPassphrase) }
    }

    var passphraseTimeoutMinutes: Int {
        get {
            guard defaults.object(forKey: Keys.passphraseTimeout) != nil else {
                return 10
            }

            return defaults.integer(forKey: Keys.passphraseTimeout)
        }
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

    var lastBackupReminderDate: Date? {
        get { defaults.object(forKey: Keys.lastBackupReminderDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastBackupReminderDate) }
    }

    var backupReminderEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.backupReminderEnabled) == nil {
                return false
            }
            return defaults.bool(forKey: Keys.backupReminderEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.backupReminderEnabled) }
    }

    var backupReminderIntervalDays: Int {
        get { defaults.integer(forKey: Keys.backupReminderIntervalDays).nonZeroOr(30) }
        set { defaults.set(newValue, forKey: Keys.backupReminderIntervalDays) }
    }

    var enabledKeyServers: [String] {
        get {
            let stored = defaults.stringArray(forKey: Keys.enabledKeyServers) ?? []
            let normalized = normalizeEnabledKeyServers(stored)
            return normalized.isEmpty ? defaultEnabledKeyServers : normalized
        }
        set {
            let normalized = normalizeEnabledKeyServers(newValue)
            let enabledServers = normalized.isEmpty ? defaultEnabledKeyServers : normalized
            defaults.set(enabledServers, forKey: Keys.enabledKeyServers)

            if !enabledServers.contains(defaults.string(forKey: Keys.defaultKeyServer) ?? "") {
                defaults.set(preferredDefaultKeyServer(among: enabledServers), forKey: Keys.defaultKeyServer)
            }
        }
    }

    var defaultKeyServer: String {
        get {
            let storedValue = defaults.string(forKey: Keys.defaultKeyServer) ?? KeyServerConfig.keysOpenpgp.hostname
            return enabledKeyServers.contains(storedValue)
                ? storedValue
                : preferredDefaultKeyServer(among: enabledKeyServers)
        }
        set {
            let normalizedValue = enabledKeyServers.contains(newValue)
                ? newValue
                : preferredDefaultKeyServer(among: enabledKeyServers)
            defaults.set(normalizedValue, forKey: Keys.defaultKeyServer)
        }
    }

    /// Chooses a fallback default keyserver, always preferring a secure (TLS)
    /// endpoint so an insecure server is never selected by accident.
    private func preferredDefaultKeyServer(among hostnames: [String]) -> String {
        let secureHostnames = Set(KeyServerConfig.defaults.filter(\.isSecure).map(\.hostname))
        return hostnames.first(where: { secureHostnames.contains($0) })
            ?? hostnames.first
            ?? KeyServerConfig.keysOpenpgp.hostname
    }

    var keyServerTimeout: Int {
        get { defaults.integer(forKey: Keys.keyServerTimeout).nonZeroOr(30) }
        set { defaults.set(newValue, forKey: Keys.keyServerTimeout) }
    }

    /// Hostnames of insecure (HKP/HTTP) keyservers the user has explicitly opted
    /// into contacting over plaintext transport. Only known insecure hostnames are
    /// persisted; secure servers never require an opt-in.
    var insecureKeyServersAllowed: [String] {
        get {
            let stored = defaults.stringArray(forKey: Keys.insecureKeyServersAllowed) ?? []
            return normalizeInsecureKeyServers(stored)
        }
        set {
            defaults.set(normalizeInsecureKeyServers(newValue), forKey: Keys.insecureKeyServersAllowed)
        }
    }

    /// Returns whether the user has explicitly opted into insecure transport for
    /// the given keyserver hostname.
    func isInsecureKeyServerAllowed(_ hostname: String) -> Bool {
        insecureKeyServersAllowed.contains(hostname)
    }

    /// Records (or clears) the user's explicit opt-in to insecure transport for the
    /// given keyserver hostname. No-op for secure or unknown hostnames.
    func setInsecureKeyServer(_ hostname: String, allowed: Bool) {
        guard insecureKeyServerHostnames.contains(hostname) else { return }
        var allowedServers = insecureKeyServersAllowed
        if allowed {
            if !allowedServers.contains(hostname) {
                allowedServers.append(hostname)
            }
        } else {
            allowedServers.removeAll { $0 == hostname }
        }
        insecureKeyServersAllowed = allowedServers
    }

    /// Known insecure keyserver hostnames from the bundled defaults.
    private var insecureKeyServerHostnames: Set<String> {
        Set(KeyServerConfig.defaults.filter { !$0.isSecure }.map(\.hostname))
    }

    /// Filters hostnames to include only those known to be insecure, removing duplicates.
    /// - Parameter servers: The hostnames to normalize.
    /// - Returns: The filtered list of insecure hostnames with duplicates removed.
    private func normalizeInsecureKeyServers(_ servers: [String]) -> [String] {
        let knownInsecure = insecureKeyServerHostnames
        var seen = Set<String>()
        return servers.filter { hostname in
            knownInsecure.contains(hostname) && seen.insert(hostname).inserted
        }
    }

    var appLanguage: AppLanguage {
        get {
            let storedLanguage = Self.storedOrDetectedLanguage(defaults: defaults)
            if selectedAppLanguage != storedLanguage {
                selectedAppLanguage = storedLanguage
            }
            return selectedAppLanguage
        }
        set {
            selectedAppLanguage = newValue
            defaults.set(newValue.rawValue, forKey: Keys.appLanguage)
            applyLanguage(newValue)
        }
    }

    /// Applies a language preference to the app by setting the `AppleLanguages` user default.
    private func applyLanguage(_ language: AppLanguage) {
        defaults.set([language.rawValue], forKey: "AppleLanguages")
        defaults.synchronize()
    }

    private init() {
        selectedAppLanguage = Self.storedOrDetectedLanguage(defaults: defaults)
        applyLanguage(selectedAppLanguage)
    }

    private var defaultEnabledKeyServers: [String] {
        KeyServerConfig.defaults
            .filter(\.isEnabled)
            .map(\.hostname)
    }

    /// Filters the keyserver list to include only known servers and removes duplicates.
    /// - Parameters:
    ///   - servers: The list of keyserver hostnames to normalize.
    /// - Returns: A filtered list containing only known keyservers without duplicates, in the original order.
    private func normalizeEnabledKeyServers(_ servers: [String]) -> [String] {
        let knownServers = Set(KeyServerConfig.defaults.map(\.hostname))
        var seen = Set<String>()

        return servers.filter { hostname in
            knownServers.contains(hostname) && seen.insert(hostname).inserted
        }
    }

    /// Returns the app language preference from storage, falling back to system detection or English.
    /// - Returns: The stored language preference if available and valid, the system language if none is stored, or English if the stored value cannot be decoded.
    private static func storedOrDetectedLanguage(defaults: UserDefaults) -> AppLanguage {
        guard let value = defaults.string(forKey: Keys.appLanguage) else {
            return detectSystemLanguage()
        }
        return AppLanguage(rawValue: value) ?? .english
    }

    /// Determines which supported app language matches the system's preferred language.
    /// - Returns: An `AppLanguage` case corresponding to the system's preference, or `.english` if no supported language matches.
    private static func detectSystemLanguage() -> AppLanguage {
        for languageIdentifier in Locale.preferredLanguages {
            let locale = Locale(identifier: languageIdentifier)
            guard let languageCode = locale.language.languageCode?.identifier else { continue }

            switch languageCode {
            case "en": return .english
            case "es": return .spanish
            case "fr": return .french
            case "de": return .german
            case "pt": return .portuguese
            case "zh":
                if locale.language.script?.identifier == "Hans" {
                    return .chinese
                }
                continue
            default: continue
            }
        }
        return .english
    }

    /// Clears all stored preferences and reapplies the system language.
    func resetToDefaults() {
        let domain = Bundle.main.bundleIdentifier ?? "com.macpgp"
        defaults.removePersistentDomain(forName: domain)
        selectedAppLanguage = Self.detectSystemLanguage()
        applyLanguage(selectedAppLanguage)
    }

    /// Ensures an algorithm is supported, defaulting to RSA if not.
    /// - Parameters:
    ///   - algorithm: The algorithm to validate.
    /// - Returns: The provided algorithm if it is one of the supported algorithms (RSA, ECDSA, or EDDSA), otherwise `.rsa`.
    private static func normalizedDefaultKeyAlgorithm(_ algorithm: KeyAlgorithm) -> KeyAlgorithm {
        [.rsa, .ecdsa, .eddsa].contains(algorithm) ? algorithm : .rsa
    }
}

private extension Int {
    func nonZeroOr(_ defaultValue: Int) -> Int {
        self == 0 ? defaultValue : self
    }
}
