import Foundation
import Testing
@testable import MacPGP

@Suite("PassphraseCache Tests")
@MainActor
struct PassphraseCacheTests {
    @Test("returns cached passphrase while enabled and unexpired")
    func returnsCachedPassphrase() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        var enabled = true
        let cache = PassphraseCache(
            isEnabled: { enabled },
            timeoutMinutes: { 10 },
            now: { currentDate }
        )

        cache.store("secret", forKeyID: " abcd 1234 ")
        currentDate = currentDate.addingTimeInterval(60)

        #expect(cache.passphrase(forKeyID: "ABCD1234") == "secret")
    }

    @Test("does not store or return passphrases when disabled")
    func disabledCacheDoesNotReturnPassphrase() {
        var enabled = true
        let cache = PassphraseCache(
            isEnabled: { enabled },
            timeoutMinutes: { 10 },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        cache.store("secret", forKeyID: "ABCD")
        enabled = false

        #expect(cache.passphrase(forKeyID: "ABCD") == nil)

        enabled = true
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
}
