//
//  KeyServerStubTests.swift
//  MacPGPTests
//
//  Validates the deterministic Keyserver UI-test seam (issue #125) at the unit
//  level, independent of XCUITest: the stub protocol serves correct fixtures and
//  the embedded fixture key is importable.
//

import Foundation
import Testing
import RNPKit
@testable import MacPGP

@MainActor
@Suite("Keyserver Stub Tests", .serialized)
struct KeyServerStubTests {
    private func stubService() -> KeyServerService {
        KeyServerUITestSupport.makeKeyServerService()
    }

    private func server() -> KeyServerConfig {
        KeyServerConfig(name: "Stub", hostname: "stub.local", protocol: .hkps)
    }

    @Test("Stub default scenario serves deterministic multi-key search results")
    func testStubSearchReturnsFixtures() async throws {
        let results = try await stubService().search(query: "alice@example.org", on: server())

        #expect(results.count == 2)
        #expect(results.contains { ($0.primaryUserID ?? "").contains("alice@example.org") })
        #expect(results.contains { ($0.primaryUserID ?? "").contains("bob@example.org") })
    }

    @Test("Stub fetch serves an importable fixture public key")
    func testStubFetchReturnsImportableKey() async throws {
        let data = try await stubService().fetchKey(
            fingerprint: "6321642B5EF963758C991DE4B9EA5EB0777879D4",
            from: server()
        )

        let armored = String(data: data, encoding: .utf8) ?? ""
        #expect(armored.contains("BEGIN PGP PUBLIC KEY BLOCK"))

        // The embedded fixture key must parse so the import UI scenario succeeds.
        let keys = try KeyringPersistence().importKey(from: data)
        #expect(keys.count == 1)
    }

    @Test("Default scenario is a successful multi-key search")
    func testDefaultScenario() {
        #expect(KeyServerUITestSupport.scenario == .successMultiple)
    }
}
