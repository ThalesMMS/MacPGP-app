import Foundation

@MainActor
final class PassphraseCache {
    static let shared = PassphraseCache()

    private struct Entry {
        let passphrase: String
        let storedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let isEnabled: @MainActor () -> Bool
    private let timeoutMinutes: @MainActor () -> Int
    private let now: () -> Date

    init(
        isEnabled: @escaping @MainActor () -> Bool = { PreferencesManager.shared.rememberPassphrase },
        timeoutMinutes: @escaping @MainActor () -> Int = { PreferencesManager.shared.passphraseTimeoutMinutes },
        now: @escaping () -> Date = Date.init
    ) {
        self.isEnabled = isEnabled
        self.timeoutMinutes = timeoutMinutes
        self.now = now
    }

    func store(_ passphrase: String, for key: PGPKeyModel) {
        store(passphrase, forKeyID: Self.cacheKey(for: key))
    }

    func store(_ passphrase: String, forKeyID keyID: String) {
        guard isEnabled() else {
            clear()
            return
        }

        let key = Self.normalizedKeyID(keyID)
        guard !key.isEmpty, !passphrase.isEmpty else { return }

        entries[key] = Entry(passphrase: passphrase, storedAt: now())
    }

    func passphrase(for key: PGPKeyModel) -> String? {
        passphrase(forKeyID: Self.cacheKey(for: key))
    }

    func passphrase(forKeyID keyID: String) -> String? {
        guard isEnabled() else {
            clear()
            return nil
        }

        let key = Self.normalizedKeyID(keyID)
        guard let entry = entries[key] else { return nil }

        let timeout = timeoutMinutes()
        guard timeout > 0 else { return entry.passphrase }

        let expiry = entry.storedAt.addingTimeInterval(TimeInterval(timeout) * 60)
        guard now() < expiry else {
            entries.removeValue(forKey: key)
            return nil
        }

        return entry.passphrase
    }

    func clear() {
        entries.removeAll()
    }

    private static func cacheKey(for key: PGPKeyModel) -> String {
        if !key.fingerprint.isEmpty {
            return key.fingerprint
        }

        return key.shortKeyID
    }

    private static func normalizedKeyID(_ keyID: String) -> String {
        keyID.filter { !$0.isWhitespace }.uppercased()
    }
}
