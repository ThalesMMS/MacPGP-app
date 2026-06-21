//
//  SessionLockControllerTests.swift
//  MacPGPTests
//
//  Coverage for issue #128: explicit lock and system lock/sleep/resign events
//  clear the in-memory passphrase cache, while ordinary app deactivation does not.
//

import Foundation
import Testing
import AppKit
@testable import MacPGP

@MainActor
@Suite("SessionLockController Tests")
struct SessionLockControllerTests {
    private func makeCache() -> PassphraseCache {
        PassphraseCache(
            isEnabled: { true },
            timeoutMinutes: { 0 },
            now: { Date(timeIntervalSince1970: 1_000) }
        )
    }

    @Test("explicit lock clears the cache and posts macPGPDidLock")
    func explicitLockClearsAndNotifies() {
        let cache = makeCache()
        let lockCenter = NotificationCenter()
        let posted = LockedBool(false)
        let token = lockCenter.addObserver(forName: .macPGPDidLock, object: nil, queue: nil) { _ in posted.value = true }
        defer { lockCenter.removeObserver(token) }

        let controller = SessionLockController(
            cache: cache,
            workspaceNotificationCenter: NotificationCenter(),
            appNotificationCenter: NotificationCenter(),
            lockNotificationCenter: lockCenter
        )

        cache.store("secret", forKeyID: "ABCD")
        withExtendedLifetime(controller) {
            controller.lock()
            #expect(cache.passphrase(forKeyID: "ABCD") == nil)
            #expect(posted.value)
        }
    }

    @Test("system sleep notification locks the cache")
    func sleepLocksCache() {
        let cache = makeCache()
        let workspace = NotificationCenter()
        let controller = SessionLockController(
            cache: cache,
            workspaceNotificationCenter: workspace,
            appNotificationCenter: NotificationCenter(),
            lockNotificationCenter: NotificationCenter()
        )

        cache.store("secret", forKeyID: "ABCD")
        withExtendedLifetime(controller) {
            workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
            #expect(cache.passphrase(forKeyID: "ABCD") == nil)
        }
    }

    @Test("session resign-active (lock/switch) notification locks the cache")
    func sessionResignLocksCache() {
        let cache = makeCache()
        let workspace = NotificationCenter()
        let controller = SessionLockController(
            cache: cache,
            workspaceNotificationCenter: workspace,
            appNotificationCenter: NotificationCenter(),
            lockNotificationCenter: NotificationCenter()
        )

        cache.store("secret", forKeyID: "ABCD")
        let start = cache.lockGeneration
        withExtendedLifetime(controller) {
            workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
            #expect(cache.passphrase(forKeyID: "ABCD") == nil)
            #expect(cache.lockGeneration == start + 1)
        }
    }

    @Test("app termination notification locks the cache")
    func terminationLocksCache() {
        let cache = makeCache()
        let appCenter = NotificationCenter()
        let controller = SessionLockController(
            cache: cache,
            workspaceNotificationCenter: NotificationCenter(),
            appNotificationCenter: appCenter,
            lockNotificationCenter: NotificationCenter()
        )

        cache.store("secret", forKeyID: "ABCD")
        withExtendedLifetime(controller) {
            appCenter.post(name: NSApplication.willTerminateNotification, object: nil)
            #expect(cache.passphrase(forKeyID: "ABCD") == nil)
        }
    }

    @Test("off-main system sleep notification locks the cache")
    func offMainSleepLocksCache() async {
        let cache = makeCache()
        let workspace = NotificationCenter()
        let controller = SessionLockController(
            cache: cache,
            workspaceNotificationCenter: workspace,
            appNotificationCenter: NotificationCenter(),
            lockNotificationCenter: NotificationCenter()
        )

        cache.store("secret", forKeyID: "ABCD")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
                continuation.resume()
            }
        }
        #expect(cache.passphrase(forKeyID: "ABCD") == nil)
        withExtendedLifetime(controller) {}
    }

    @Test("ordinary app deactivation does NOT lock the cache")
    func ordinaryDeactivationDoesNotLock() {
        let cache = makeCache()
        let appCenter = NotificationCenter()
        let controller = SessionLockController(
            cache: cache,
            workspaceNotificationCenter: NotificationCenter(),
            appNotificationCenter: appCenter,
            lockNotificationCenter: NotificationCenter()
        )

        cache.store("secret", forKeyID: "ABCD")
        withExtendedLifetime(controller) {
            // didResignActive is intentionally not a lock trigger.
            appCenter.post(name: NSApplication.didResignActiveNotification, object: nil)
            #expect(cache.passphrase(forKeyID: "ABCD") == "secret")
        }
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
