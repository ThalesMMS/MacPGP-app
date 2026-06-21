//
//  SerializedGlobalDefaultsTrait.swift
//  MacPGPTests
//
//  Serializes tests across suites that mutate process-global state.
//

import Testing

/// A process-wide async mutex used to serialize tests that mutate the shared
/// `UserDefaults.standard` (directly or through `PreferencesManager.shared`).
///
/// Implemented as an actor with a FIFO continuation queue so callers suspend —
/// rather than busy-wait — while another test holds the lock. The actor's
/// executor is *not* held across the awaited test body; the `isLocked` flag is
/// the logical lock, so other tasks can enqueue while the holder is suspended.
private actor GlobalDefaultsLock {
    static let shared = GlobalDefaultsLock()

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Acquires the lock, suspending until it is free if another holder has it.
    func acquire() async {
        guard isLocked else {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Releases the lock, handing ownership directly to the next waiter (if any)
    /// so the lock never appears momentarily free between contending tests.
    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Serializes every test in the annotated suites against one another, *across*
/// suite boundaries.
///
/// Swift Testing's built-in `.serialized` trait only orders tests *within* a
/// single suite — separate suites still run in parallel with each other. Suites
/// that mutate the shared `UserDefaults.standard` (via `PreferencesManager.shared`)
/// therefore race across suite boundaries: one suite can reset a key while
/// another is mid-test between its own write and read of that key. Applying this
/// trait to every such suite funnels their tests through a single process-wide
/// async mutex so only one runs at a time, regardless of which suite it's in.
struct SerializedGlobalDefaults: TestTrait, SuiteTrait, TestScoping {
    // Apply the scope to each individual test in the suite, not just the suite
    // container, so other annotated suites can interleave between this suite's
    // tests rather than blocking on it wholesale.
    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        self
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        // The suite container itself (testCase == nil) passes through without
        // taking the lock; only its tests do. Locking at both levels would
        // self-deadlock, since the container scope wraps the test scopes.
        guard testCase != nil else {
            try await function()
            return
        }

        await GlobalDefaultsLock.shared.acquire()
        // Release on every exit path (including a thrown test failure) without a
        // closure hand-off, so the protocol's test body is only ever called
        // directly and never re-typed across an isolation boundary.
        do {
            try await function()
        } catch {
            await GlobalDefaultsLock.shared.release()
            throw error
        }
        await GlobalDefaultsLock.shared.release()
    }
}

extension Trait where Self == SerializedGlobalDefaults {
    /// Serializes the annotated suite's tests against all other suites carrying
    /// this trait, so concurrent `UserDefaults.standard` mutations can't interleave.
    static var serializedGlobalDefaults: Self { Self() }
}
