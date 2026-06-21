import Foundation
import Testing
@testable import MacPGP

@Suite("PassphraseCache Tests")
@MainActor
struct PassphraseCacheTests {
    @Test("returns cached passphrase while enabled and unexpired")
    func returnsCachedPassphrase() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let cache = PassphraseCache(
            isEnabled: { true },
            timeoutMinutes: { 10 },
            now: { currentDate }
        )

        cache.store("secret", forKeyID: " abcd 1234 ")
        currentDate = currentDate.addingTimeInterval(60)

        #expect(cache.passphrase(forKeyID: "ABCD1234") == "secret")
    }

    @Test("does not store or return passphrases when disabled")
    func disabledCacheDoesNotReturnPassphrase() {
        let enabled = LockedBool(true)
        let cache = PassphraseCache(
            isEnabled: { enabled.value },
            timeoutMinutes: { 10 },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        cache.store("secret", forKeyID: "ABCD")
        enabled.value = false

        #expect(cache.passphrase(forKeyID: "ABCD") == nil)

        enabled.value = true
        #expect(cache.passphrase(forKeyID: "ABCD") == nil)
    }

    @Test("expires passphrase after configured timeout")
    func expiresAfterTimeout() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let cache = PassphraseCache(
            isEnabled: { true },
            timeoutMinutes: { 5 },
            now: { currentDate }
        )

        cache.store("secret", forKeyID: "ABCD")
        currentDate = currentDate.addingTimeInterval(301)

        #expect(cache.passphrase(forKeyID: "ABCD") == nil)
    }

    @Test("zero timeout keeps passphrase until cache is cleared")
    func zeroTimeoutNeverExpires() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let cache = PassphraseCache(
            isEnabled: { true },
            timeoutMinutes: { 0 },
            now: { currentDate }
        )

        cache.store("secret", forKeyID: "ABCD")
        currentDate = currentDate.addingTimeInterval(86_400)

        #expect(cache.passphrase(forKeyID: "ABCD") == "secret")

        cache.clear()
        #expect(cache.passphrase(forKeyID: "ABCD") == nil)
    }

    @Test("lock clears entries even with a never-clear timeout")
    func lockOverridesNeverClear() {
        let cache = PassphraseCache(
            isEnabled: { true },
            timeoutMinutes: { 0 },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        cache.store("secret", forKeyID: "ABCD")
        #expect(cache.passphrase(forKeyID: "ABCD") == "secret")

        cache.lock()
        #expect(cache.passphrase(forKeyID: "ABCD") == nil)
    }

    @Test("lock advances the lock generation")
    func lockAdvancesGeneration() {
        let cache = PassphraseCache(
            isEnabled: { true },
            timeoutMinutes: { 10 },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let start = cache.lockGeneration
        cache.lock()
        #expect(cache.lockGeneration == start + 1)
        cache.lock()
        #expect(cache.lockGeneration == start + 2)
    }

    @Test("generation-guarded store is dropped after a lock (stale async completion)")
    func generationGuardedStoreDroppedAfterLock() {
        let cache = PassphraseCache(
            isEnabled: { true },
            timeoutMinutes: { 10 },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        // Capture the generation before an async retrieval...
        let captured = cache.lockGeneration
        // ...a lock happens during the async gap...
        cache.lock()
        // ...and the stale completion attempts to cache its result.
        cache.store("secret", forKeyID: "ABCD", lockGeneration: captured)

        #expect(cache.passphrase(forKeyID: "ABCD") == nil)
    }

    @Test("generation-guarded store succeeds when no lock intervened")
    func generationGuardedStoreSucceedsWithoutLock() {
        let cache = PassphraseCache(
            isEnabled: { true },
            timeoutMinutes: { 10 },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let captured = cache.lockGeneration
        cache.store("secret", forKeyID: "ABCD", lockGeneration: captured)

        #expect(cache.passphrase(forKeyID: "ABCD") == "secret")
    }

    @Test("new cache instance starts empty")
    func newCacheInstanceStartsEmpty() {
        let firstCache = PassphraseCache(
            isEnabled: { true },
            timeoutMinutes: { 10 },
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        firstCache.store("secret", forKeyID: "ABCD")

        let secondCache = PassphraseCache(
            isEnabled: { true },
            timeoutMinutes: { 10 },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        #expect(secondCache.passphrase(forKeyID: "ABCD") == nil)
    }

    private final class LockedBool: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Bool

        init(_ value: Bool) {
            self.storage = value
        }

        var value: Bool {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }
            set {
                lock.lock()
                storage = newValue
                lock.unlock()
            }
        }
    }
}
