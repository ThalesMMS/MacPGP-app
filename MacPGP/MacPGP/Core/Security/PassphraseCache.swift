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

    /// Monotonically increasing generation that advances every time the cache is
    /// locked. Callers capture this before an async passphrase retrieval and pass
    /// it back to `store(_:forKeyID:lockGeneration:)` so a completion that lands
    /// after a lock cannot repopulate the cache.
    private(set) var lockGeneration: Int = 0

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

    /// Generation-guarded store for results produced by asynchronous work. If the
    /// cache has been locked since `generation` was captured, the store is skipped.
    func store(_ passphrase: String, for key: PGPKeyModel, lockGeneration generation: Int) {
        guard generation == lockGeneration else { return }
        store(passphrase, for: key)
    }

    /// Generation-guarded store for results produced by asynchronous work. If the
    /// cache has been locked since `generation` was captured, the store is skipped.
    func store(_ passphrase: String, forKeyID keyID: String, lockGeneration generation: Int) {
        guard generation == lockGeneration else { return }
        store(passphrase, forKeyID: keyID)
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

    /// Immediately invalidates every cached passphrase and advances the lock
    /// generation, regardless of the configured timeout (including "Never clear").
    /// Persisted Keychain items are not affected. Note that Swift `String` storage
    /// cannot be guaranteed to be zeroized in memory; this removes the only
    /// references MacPGP holds, but does not promise secure erasure of copies the
    /// runtime may have made.
    func lock() {
        lockGeneration &+= 1
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
