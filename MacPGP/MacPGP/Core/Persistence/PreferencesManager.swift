import Foundation
import SwiftUI

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

    private init() {}

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
