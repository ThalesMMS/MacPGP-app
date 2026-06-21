import Foundation
import Testing
@testable import MacPGP

@MainActor
@Suite("Keyserver Preference Tests", .serialized, .serializedGlobalDefaults)
struct KeyServerPreferenceTests {
    private static let preferencesLock = NSLock()

    private enum DefaultsKeys {
        static let defaultKeyServer = "defaultKeyServer"
        static let enabledKeyServers = "enabledKeyServers"
        static let keyServerTimeout = "keyServerTimeout"
    }

    private let preferenceKeys = [
        DefaultsKeys.defaultKeyServer,
        DefaultsKeys.enabledKeyServers,
        DefaultsKeys.keyServerTimeout
    ]

    private func withCleanKeyServerPreferences(_ body: () throws -> Void) rethrows {
        Self.preferencesLock.lock()
        defer {
            Self.preferencesLock.unlock()
        }

        let defaults = UserDefaults.standard
        let preferences = PreferencesManager.shared
        let savedValues = Dictionary(uniqueKeysWithValues: preferenceKeys.map { ($0, defaults.object(forKey: $0)) })

        for key in preferenceKeys {
            defaults.removeObject(forKey: key)
        }

        defer {
            for key in preferenceKeys {
                if let value = savedValues[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }

            _ = preferences.enabledKeyServers
            _ = preferences.defaultKeyServer
            _ = preferences.keyServerTimeout
        }

        try body()
    }

    @Test("enabledKeyServers persists selected hostnames")
    func testEnabledKeyServersPersistence() throws {
        withCleanKeyServerPreferences {
            let expected = [
                KeyServerConfig.keysOpenpgp.hostname,
                KeyServerConfig.mitKeyserver.hostname
            ]

            PreferencesManager.shared.enabledKeyServers = expected

            #expect(PreferencesManager.shared.enabledKeyServers == expected)
            #expect(UserDefaults.standard.stringArray(forKey: DefaultsKeys.enabledKeyServers) == expected)
        }
    }

    @Test("Disabling current default keyserver resets defaultKeyServer")
    func testEnabledKeyServersSetterResetsDisabledDefaultServer() throws {
        withCleanKeyServerPreferences {
            PreferencesManager.shared.enabledKeyServers = [
                KeyServerConfig.keysOpenpgp.hostname,
                KeyServerConfig.ubuntuKeyserver.hostname
            ]
            PreferencesManager.shared.defaultKeyServer = KeyServerConfig.ubuntuKeyserver.hostname

            PreferencesManager.shared.enabledKeyServers = [KeyServerConfig.keysOpenpgp.hostname]

            #expect(PreferencesManager.shared.defaultKeyServer == KeyServerConfig.keysOpenpgp.hostname)
        }
    }

    @Test("defaultKeyServer falls back when stored hostname is disabled")
    func testDefaultKeyServerFallsBackWhenStoredHostnameDisabled() throws {
        withCleanKeyServerPreferences {
            PreferencesManager.shared.enabledKeyServers = [KeyServerConfig.keysOpenpgp.hostname]
            UserDefaults.standard.set(KeyServerConfig.mitKeyserver.hostname, forKey: DefaultsKeys.defaultKeyServer)

            #expect(PreferencesManager.shared.defaultKeyServer == KeyServerConfig.keysOpenpgp.hostname)
        }
    }

    @Test("enabled keyserver normalization filters unknowns and restores defaults for empty list")
    func testNormalizeEnabledKeyServersBehavior() throws {
        withCleanKeyServerPreferences {
            PreferencesManager.shared.enabledKeyServers = [
                "unknown.example.test",
                KeyServerConfig.mitKeyserver.hostname,
                KeyServerConfig.mitKeyserver.hostname,
                KeyServerConfig.keysOpenpgp.hostname
            ]

            #expect(PreferencesManager.shared.enabledKeyServers == [
                KeyServerConfig.mitKeyserver.hostname,
                KeyServerConfig.keysOpenpgp.hostname
            ])

            PreferencesManager.shared.enabledKeyServers = []

            let defaultEnabledHostnames = KeyServerConfig.defaults
                .filter(\.isEnabled)
                .map(\.hostname)
            #expect(PreferencesManager.shared.enabledKeyServers == defaultEnabledHostnames)
        }
    }

    @Test("keyServerTimeout persists supported release values")
    func testKeyServerTimeoutPersistence() throws {
        withCleanKeyServerPreferences {
            for timeout in [15, 30, 60, 90] {
                PreferencesManager.shared.keyServerTimeout = timeout
                #expect(PreferencesManager.shared.keyServerTimeout == timeout)
                #expect(UserDefaults.standard.integer(forKey: DefaultsKeys.keyServerTimeout) == timeout)
            }
        }
    }

    @Test("KeyServerConfig.enabledServers returns only preference-enabled servers")
    func testKeyServerConfigEnabledServersUsesPreferences() throws {
        withCleanKeyServerPreferences {
            PreferencesManager.shared.enabledKeyServers = [KeyServerConfig.mitKeyserver.hostname]

            let enabledServers = KeyServerConfig.enabledServers(using: PreferencesManager.shared)

            #expect(enabledServers.map(\.hostname) == [KeyServerConfig.mitKeyserver.hostname])
        }
    }

    @Test("KeyServerConfig.defaultServer returns preference-selected server")
    func testKeyServerConfigDefaultServerUsesPreferences() throws {
        withCleanKeyServerPreferences {
            PreferencesManager.shared.enabledKeyServers = [
                KeyServerConfig.ubuntuKeyserver.hostname,
                KeyServerConfig.mitKeyserver.hostname
            ]
            PreferencesManager.shared.defaultKeyServer = KeyServerConfig.mitKeyserver.hostname

            let defaultServer = KeyServerConfig.defaultServer(using: PreferencesManager.shared)

            #expect(defaultServer.hostname == KeyServerConfig.mitKeyserver.hostname)
        }
    }

    @Test("KeyServerConfig.defaultServer(using: nil) uses PreferencesManager.shared")
    func testDefaultServerNilPreferencesUsesShared() {
        withCleanKeyServerPreferences {
            PreferencesManager.shared.enabledKeyServers = [
                KeyServerConfig.keysOpenpgp.hostname,
                KeyServerConfig.ubuntuKeyserver.hostname
            ]
            PreferencesManager.shared.defaultKeyServer = KeyServerConfig.ubuntuKeyserver.hostname

            // Passing nil should behave identically to passing .shared explicitly.
            let viaShared = KeyServerConfig.defaultServer(using: PreferencesManager.shared)
            let viaNil = KeyServerConfig.defaultServer(using: nil)

            #expect(viaShared.hostname == viaNil.hostname)
            #expect(viaNil.hostname == KeyServerConfig.ubuntuKeyserver.hostname)
        }
    }

    @Test("KeyServerConfig.defaultServer(using: nil) falls back to a secure server when stored default is disabled")
    func testDefaultServerNilFallsBackToSecureServer() {
        withCleanKeyServerPreferences {
            // Enable only the secure openpgp server; MIT (insecure) is not enabled.
            PreferencesManager.shared.enabledKeyServers = [KeyServerConfig.keysOpenpgp.hostname]
            // Point defaultKeyServer to a hostname that is NOT in the enabled list.
            UserDefaults.standard.set(KeyServerConfig.mitKeyserver.hostname, forKey: DefaultsKeys.defaultKeyServer)

            let result = KeyServerConfig.defaultServer(using: nil)

            // Must fall back to a secure enabled server, never the disabled MIT server.
            #expect(result.hostname != KeyServerConfig.mitKeyserver.hostname)
            #expect(result.isSecure)
        }
    }
}
