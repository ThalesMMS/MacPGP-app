import Foundation
import Testing
@testable import MacPGP

@Suite("DateProviding Tests")
struct DateProvidingTests {

    // MARK: - SystemDateProvider

    @Test("SystemDateProvider.now is close to the current wall-clock time")
    func systemDateProviderNowIsCurrentDate() {
        let provider = SystemDateProvider()
        let before = Date()
        let now = provider.now
        let after = Date()

        #expect(now >= before)
        #expect(now <= after)
    }

    @Test("SystemDateProvider.now returns a fresh Date on each call")
    func systemDateProviderNowChangesOverTime() async {
        let provider = SystemDateProvider()
        let first = provider.now
        // A brief suspension is enough to advance the wall clock.
        try? await Task.sleep(nanoseconds: 5_000_000) // 5 ms
        let second = provider.now
        #expect(second >= first)
    }

    @Test("SystemDateProvider conforms to DateProviding")
    func systemDateProviderConformance() {
        let provider: any DateProviding = SystemDateProvider()
        let now = provider.now
        // The returned date should be within 1 second of Date().
        #expect(abs(now.timeIntervalSinceNow) < 1)
    }

    // MARK: - Custom DateProviding conformance

    @Test("Custom DateProviding implementation can inject a fixed date")
    func customDateProvidingFixedDate() {
        struct FixedClock: DateProviding {
            let fixedDate: Date
            var now: Date { fixedDate }
        }

        let sentinel = Date(timeIntervalSince1970: 1_000_000)
        let clock: any DateProviding = FixedClock(fixedDate: sentinel)
        #expect(clock.now == sentinel)
        #expect(clock.now == sentinel) // stable across calls
    }

    @Test("Custom DateProviding can advance time deterministically")
    func customDateProvidingAdvancingClock() {
        final class SteppingClock: DateProviding, @unchecked Sendable {
            private var current: Date
            init(start: Date) { self.current = start }
            var now: Date { current }
            func advance(by seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
        }

        let start = Date(timeIntervalSince1970: 0)
        let clock = SteppingClock(start: start)

        #expect(clock.now == start)
        clock.advance(by: 3600)
        #expect(clock.now == start.addingTimeInterval(3600))
        clock.advance(by: 3600)
        #expect(clock.now == start.addingTimeInterval(7200))
    }

    // MARK: - Sendable conformance

    @Test("SystemDateProvider can be used from a nonisolated context")
    func systemDateProviderNonisolated() async {
        let provider = SystemDateProvider()
        let date = await Task.detached {
            provider.now
        }.value
        #expect(abs(date.timeIntervalSinceNow) < 5)
    }
}