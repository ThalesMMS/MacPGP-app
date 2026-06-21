import Foundation

/// Abstraction over "the current instant" used for time-dependent key validity.
///
/// Key expiration must be evaluated against the current time at the moment an
/// operation runs, not cached when a model is created. Production code uses
/// ``SystemDateProvider``; tests inject a controllable clock so expiration
/// boundaries can be exercised deterministically without recreating models.
nonisolated protocol DateProviding: Sendable {
    var now: Date { get }
}

/// Default clock backed by the system wall clock.
nonisolated struct SystemDateProvider: DateProviding {
    var now: Date { Date() }
}
