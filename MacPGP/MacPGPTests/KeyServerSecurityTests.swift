//
//  KeyServerSecurityTests.swift
//  MacPGPTests
//
//  Coverage for issue #129: insecure HKP/HTTP keyserver transport is gated behind
//  an explicit, service-enforced opt-in, and key upload over plaintext is prohibited.
//

import Foundation
import Testing
import RNPKit
@testable import MacPGP

/// Dedicated URL protocol mock so this suite never shares static state with
/// `MockURLProtocol` used by `KeyServerServiceTests`.
final class KeyServerSecurityMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var responder: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        KeyServerSecurityMockURLProtocol.requestCount += 1
        do {
            if let responder = KeyServerSecurityMockURLProtocol.responder {
                let (response, data) = try responder(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } else {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
@Suite("Keyserver Transport Security Tests", .serialized, .serializedGlobalDefaults)
struct KeyServerSecurityTests {
    private static let preferencesLock = NSLock()

    private enum DefaultsKeys {
        static let defaultKeyServer = "defaultKeyServer"
        static let enabledKeyServers = "enabledKeyServers"
        static let insecureKeyServersAllowed = "insecureKeyServersAllowed"
    }

    private let preferenceKeys = [
        DefaultsKeys.defaultKeyServer,
        DefaultsKeys.enabledKeyServers,
        DefaultsKeys.insecureKeyServersAllowed
    ]

    init() {
        KeyServerSecurityMockURLProtocol.requestCount = 0
        KeyServerSecurityMockURLProtocol.responder = nil
    }

    private func makeService() -> KeyServerService {
        KeyServerSecurityMockURLProtocol.requestCount = 0
        KeyServerSecurityMockURLProtocol.responder = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [KeyServerSecurityMockURLProtocol.self]
        return KeyServerService(configuration: config)
    }

    private func insecureServer(allowInsecure: Bool) -> KeyServerConfig {
        KeyServerConfig(name: "Insecure", hostname: "insecure.example.test", protocol: .hkp, allowInsecure: allowInsecure)
    }

    private func secureServer() -> KeyServerConfig {
        KeyServerConfig(name: "Secure", hostname: "secure.example.test", protocol: .hkps)
    }

    private func withCleanKeyServerPreferences(_ body: () throws -> Void) throws {
        Self.preferencesLock.lock()
        defer { Self.preferencesLock.unlock() }

        let defaults = UserDefaults.standard
        let saved = Dictionary(uniqueKeysWithValues: preferenceKeys.map { ($0, defaults.object(forKey: $0)) })
        for key in preferenceKeys { defaults.removeObject(forKey: key) }

        defer {
            for key in preferenceKeys {
                if let value = saved[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            _ = PreferencesManager.shared.enabledKeyServers
            _ = PreferencesManager.shared.defaultKeyServer
        }

        try body()
    }

    // MARK: - Transport Classification

    @Test("Protocol classification distinguishes secure and insecure transports")
    func testProtocolClassification() {
        #expect(KeyServerConfig(name: "a", hostname: "h", protocol: .hkps).isSecure)
        #expect(KeyServerConfig(name: "a", hostname: "h", protocol: .https).isSecure)
        #expect(!KeyServerConfig(name: "a", hostname: "h", protocol: .hkp).isSecure)
        #expect(!KeyServerConfig(name: "a", hostname: "h", protocol: .http).isSecure)
        #expect(KeyServerConfig(name: "a", hostname: "h", protocol: .hkp).requiresInsecureOptIn)
        #expect(!KeyServerConfig(name: "a", hostname: "h", protocol: .hkps).requiresInsecureOptIn)
        #expect(!KeyServerConfig.keysOpenpgp.requiresInsecureOptIn)
        #expect(KeyServerConfig.mitKeyserver.requiresInsecureOptIn)
    }

    // MARK: - Service Boundary Enforcement

    @Test("Insecure search is rejected before any request when not opted in")
    func testInsecureSearchRejectedWithoutOptIn() async {
        let service = makeService()

        await #expect(throws: KeyServerError.self) {
            _ = try await service.search(query: "test@example.com", on: insecureServer(allowInsecure: false))
        }

        #expect(KeyServerSecurityMockURLProtocol.requestCount == 0)
        if case .insecureTransportNotAllowed = service.lastError {} else {
            Issue.record("Expected insecureTransportNotAllowed, got \(String(describing: service.lastError))")
        }
    }

    @Test("Insecure fetch is rejected before any request when not opted in")
    func testInsecureFetchRejectedWithoutOptIn() async {
        let service = makeService()

        await #expect(throws: KeyServerError.self) {
            _ = try await service.fetchKey(fingerprint: "ABCD1234", from: insecureServer(allowInsecure: false))
        }

        #expect(KeyServerSecurityMockURLProtocol.requestCount == 0)
    }

    @Test("Insecure refresh is rejected before any request when not opted in")
    func testInsecureRefreshRejectedWithoutOptIn() async {
        let service = makeService()

        await #expect(throws: KeyServerError.self) {
            _ = try await service.refreshKey(fingerprint: "ABCD1234", from: insecureServer(allowInsecure: false))
        }

        #expect(KeyServerSecurityMockURLProtocol.requestCount == 0)
    }

    @Test("Insecure search proceeds when explicitly opted in")
    func testInsecureSearchAllowedWithOptIn() async throws {
        let service = makeService()
        KeyServerSecurityMockURLProtocol.responder = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            info:1:1
            pub:ABCD1234EFGH5678:1:2048:1640000000::
            uid:Test User <test@example.com>:1640000000::
            """
            return (response, body.data(using: .utf8)!)
        }

        let results = try await service.search(query: "test@example.com", on: insecureServer(allowInsecure: true))

        #expect(results.count == 1)
        #expect(KeyServerSecurityMockURLProtocol.requestCount == 1)
    }

    @Test("Insecure upload is prohibited even when opted in")
    func testInsecureUploadProhibitedEvenWithOptIn() async {
        let service = makeService()

        await #expect(throws: KeyServerError.self) {
            try await service.uploadKey(Data("-----BEGIN PGP PUBLIC KEY BLOCK-----\n".utf8), to: insecureServer(allowInsecure: true))
        }

        #expect(KeyServerSecurityMockURLProtocol.requestCount == 0)
        if case .insecureUploadProhibited = service.lastError {} else {
            Issue.record("Expected insecureUploadProhibited, got \(String(describing: service.lastError))")
        }
    }

    @Test("Secure server search is allowed")
    func testSecureSearchAllowed() async throws {
        let service = makeService()
        KeyServerSecurityMockURLProtocol.responder = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "info:1:0\n".data(using: .utf8)!)
        }

        _ = try await service.search(query: "test@example.com", on: secureServer())

        #expect(KeyServerSecurityMockURLProtocol.requestCount == 1)
    }

    // MARK: - Opt-In Persistence

    @Test("Insecure opt-in persists for known insecure hosts only")
    func testInsecureOptInPersistence() throws {
        try withCleanKeyServerPreferences {
            let preferences = PreferencesManager.shared
            #expect(!preferences.isInsecureKeyServerAllowed(KeyServerConfig.mitKeyserver.hostname))

            preferences.setInsecureKeyServer(KeyServerConfig.mitKeyserver.hostname, allowed: true)
            #expect(preferences.isInsecureKeyServerAllowed(KeyServerConfig.mitKeyserver.hostname))

            // Secure and unknown hosts are never recorded.
            preferences.setInsecureKeyServer(KeyServerConfig.keysOpenpgp.hostname, allowed: true)
            preferences.setInsecureKeyServer("unknown.example.test", allowed: true)
            #expect(!preferences.isInsecureKeyServerAllowed(KeyServerConfig.keysOpenpgp.hostname))
            #expect(!preferences.isInsecureKeyServerAllowed("unknown.example.test"))

            preferences.setInsecureKeyServer(KeyServerConfig.mitKeyserver.hostname, allowed: false)
            #expect(!preferences.isInsecureKeyServerAllowed(KeyServerConfig.mitKeyserver.hostname))
        }
    }

    @Test("enabledServers carries the persisted insecure opt-in into the effective config")
    func testEnabledServersResolveOptIn() throws {
        try withCleanKeyServerPreferences {
            let preferences = PreferencesManager.shared
            preferences.enabledKeyServers = [
                KeyServerConfig.keysOpenpgp.hostname,
                KeyServerConfig.mitKeyserver.hostname
            ]

            let withoutOptIn = KeyServerConfig.enabledServers(using: preferences)
            let mitWithout = withoutOptIn.first { $0.hostname == KeyServerConfig.mitKeyserver.hostname }
            #expect(mitWithout?.allowInsecure == false)

            preferences.setInsecureKeyServer(KeyServerConfig.mitKeyserver.hostname, allowed: true)
            let withOptIn = KeyServerConfig.enabledServers(using: preferences)
            let mitWith = withOptIn.first { $0.hostname == KeyServerConfig.mitKeyserver.hostname }
            #expect(mitWith?.allowInsecure == true)

            // Secure servers are never marked insecure-allowed.
            let secure = withOptIn.first { $0.hostname == KeyServerConfig.keysOpenpgp.hostname }
            #expect(secure?.allowInsecure == false)
        }
    }

    // MARK: - Secure Default / Fallback

    @Test("Default server fallback never selects an insecure server")
    func testDefaultServerFallbackPrefersSecure() throws {
        try withCleanKeyServerPreferences {
            let preferences = PreferencesManager.shared
            preferences.enabledKeyServers = [
                KeyServerConfig.ubuntuKeyserver.hostname,
                KeyServerConfig.mitKeyserver.hostname
            ]
            // Force an invalid stored default so the fallback path runs.
            UserDefaults.standard.set("unknown.example.test", forKey: DefaultsKeys.defaultKeyServer)

            let fallback = KeyServerConfig.defaultServer(using: preferences)
            #expect(fallback.isSecure)
            #expect(fallback.hostname == KeyServerConfig.ubuntuKeyserver.hostname)
        }
    }

    @Test("Explicitly chosen insecure default is still respected")
    func testExplicitInsecureDefaultRespected() throws {
        try withCleanKeyServerPreferences {
            let preferences = PreferencesManager.shared
            preferences.enabledKeyServers = [
                KeyServerConfig.ubuntuKeyserver.hostname,
                KeyServerConfig.mitKeyserver.hostname
            ]
            preferences.defaultKeyServer = KeyServerConfig.mitKeyserver.hostname

            let chosen = KeyServerConfig.defaultServer(using: preferences)
            #expect(chosen.hostname == KeyServerConfig.mitKeyserver.hostname)
        }
    }
}
