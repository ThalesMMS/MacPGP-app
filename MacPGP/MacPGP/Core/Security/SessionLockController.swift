import Foundation
import AppKit

extension Notification.Name {
    /// Posted after MacPGP locks (explicitly or via a system security event) so
    /// active workflows can clear passphrase fields and pending prompts.
    static let macPGPDidLock = Notification.Name("macPGPDidLock")
}

/// Locks MacPGP's in-memory credential state, both on explicit user request and on
/// macOS security lifecycle events.
///
/// On lock the in-memory `PassphraseCache` is cleared and a `.macPGPDidLock`
/// notification is posted. Persisted Keychain passphrases are never touched.
@MainActor
final class SessionLockController {
    static let shared = SessionLockController()

    private let cache: PassphraseCache
    private let lockNotificationCenter: NotificationCenter
    nonisolated(unsafe) private var observerTokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    /// System/security events that clear the in-memory passphrase cache.
    ///
    /// Ordinary app deactivation (`NSApplication.didResignActiveNotification`) is
    /// intentionally excluded: simply switching to another app should not discard
    /// the cache, which would make the remember-passphrase feature unusable. Only a
    /// real session lock/switch, system or display sleep, or termination locks MacPGP.
    static let workspaceTriggerNames: [Notification.Name] = [
        NSWorkspace.willSleepNotification,
        NSWorkspace.screensDidSleepNotification,
        NSWorkspace.sessionDidResignActiveNotification
    ]

    static let appTriggerNames: [Notification.Name] = [
        NSApplication.willTerminateNotification
    ]

    init(
        cache: PassphraseCache? = nil,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        appNotificationCenter: NotificationCenter = NotificationCenter.default,
        lockNotificationCenter: NotificationCenter = NotificationCenter.default
    ) {
        self.cache = cache ?? .shared
        self.lockNotificationCenter = lockNotificationCenter
        for name in Self.workspaceTriggerNames {
            addObserver(on: workspaceNotificationCenter, for: name)
        }
        for name in Self.appTriggerNames {
            addObserver(on: appNotificationCenter, for: name)
        }
    }

    /// Locks MacPGP: clears the in-memory passphrase cache (overriding any timeout,
    /// including "Never clear") and notifies active workflows. Keychain-stored
    /// passphrases are not affected.
    func lock() {
        cache.lock()
        lockNotificationCenter.post(name: .macPGPDidLock, object: nil)
    }

    private func addObserver(on center: NotificationCenter, for name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            self?.lockFromAnyThread()
        }
        observerTokens.append((center, token))
    }

    nonisolated private func lockFromAnyThread() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.lock()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    self.lock()
                }
            }
        }
    }

    deinit {
        for entry in observerTokens {
            entry.center.removeObserver(entry.token)
        }
    }
}
