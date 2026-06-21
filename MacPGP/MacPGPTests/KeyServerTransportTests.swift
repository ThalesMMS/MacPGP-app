//
//  KeyServerTransportTests.swift
//  MacPGPTests
//
//  Exercises the keyserver transport adapter (logical hkp/hkps -> http/https),
//  HKP record parsing (pub/fpr/uid, algorithm normalization), fetched-key
//  identity validation, and typed timeout mapping (issue #139), driving the real
//  request-building/URL-loading layer via a capturing URLProtocol.
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

/// Captures the outgoing request and returns a fixture, so tests can assert the
/// real (mapped) scheme/port that URLSession is asked to load.
final class CapturingURLProtocol: URLProtocol {
    struct Stub {
        var statusCode: Int = 200
        var body: Data = Data()
        var failure: URLError?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _stub = Stub()
    nonisolated(unsafe) private static var _lastRequestURL: URL?

    static func configure(_ stub: Stub) {
        lock.lock(); _stub = stub; _lastRequestURL = nil; lock.unlock()
    }
    static var lastRequestURL: URL? {
        lock.lock(); defer { lock.unlock() }; return _lastRequestURL
    }
    private static func currentStub() -> Stub {
        lock.lock(); defer { lock.unlock() }; return _stub
    }
    private static func recordRequest(_ url: URL?) {
        lock.lock(); _lastRequestURL = url; lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.recordRequest(request.url)
        let stub = Self.currentStub()
        if let failure = stub.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite("KeyServer transport & identity", .serialized)
struct KeyServerTransportTests {

    private func makeService() -> KeyServerService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingURLProtocol.self]
        return KeyServerService(configuration: config)
    }

    // MARK: - Transport adapter

    @Test("hkps logical scheme maps to https transport, preserving host/port")
    func testHKPSMapsToHTTPS() async throws {
        CapturingURLProtocol.configure(.init(statusCode: 200, body: Data("info:1:0\n".utf8)))
        let service = makeService()
        let server = KeyServerConfig(name: "Secure", hostname: "keys.example.com", port: 8443, protocol: .hkps)

        _ = try await service.search(query: "alice", on: server)

        let url = CapturingURLProtocol.lastRequestURL
        #expect(url?.scheme == "https")
        #expect(url?.host == "keys.example.com")
        #expect(url?.port == 8443)
    }

    @Test("hkp logical scheme maps to http transport after opt-in, preserving port")
    func testHKPMapsToHTTP() async throws {
        CapturingURLProtocol.configure(.init(statusCode: 200, body: Data("info:1:0\n".utf8)))
        let service = makeService()
        let server = KeyServerConfig(name: "Plain", hostname: "hkp.example.com", port: 11371, protocol: .hkp, allowInsecure: true)

        _ = try await service.search(query: "alice", on: server)

        let url = CapturingURLProtocol.lastRequestURL
        #expect(url?.scheme == "http")
        #expect(url?.port == 11371)
    }

    @Test("Insecure transport without opt-in is blocked before any request")
    func testInsecureWithoutOptInBlocked() async {
        CapturingURLProtocol.configure(.init(statusCode: 200, body: Data()))
        let service = makeService()
        let server = KeyServerConfig(name: "Plain", hostname: "hkp.example.com", protocol: .hkp, allowInsecure: false)

        await #expect(throws: KeyServerError.self) {
            _ = try await service.search(query: "alice", on: server)
        }
        // No request should have been issued.
        #expect(CapturingURLProtocol.lastRequestURL == nil)
    }

    // MARK: - HKP record parsing

    @Test("A separate fpr record provides the authoritative full fingerprint")
    func testFprRecordParsing() async throws {
        let fullFingerprint = "ABCDEF0123456789ABCDEF0123456789ABCDEF01"
        let index = """
        info:1:1
        pub:0123456789ABCDEF:1:2048:1640000000::
        fpr:\(fullFingerprint)
        uid:Alice <alice@example.com>:1640000000::
        """
        CapturingURLProtocol.configure(.init(statusCode: 200, body: Data(index.utf8)))
        let service = makeService()
        let server = KeyServerConfig(name: "Secure", hostname: "keys.example.com", protocol: .hkps)

        let results = try await service.search(query: "alice", on: server)

        #expect(results.count == 1)
        #expect(results.first?.fingerprint == fullFingerprint)
    }

    @Test("Algorithm identifiers are normalized to user-facing names")
    func testAlgorithmNormalization() async throws {
        let index = """
        info:1:2
        pub:AAAA000000000000:1:2048:1640000000::
        uid:RSA User:1640000000::
        pub:BBBB000000000000:22:256:1640000000::
        uid:EdDSA User:1640000000::
        """
        CapturingURLProtocol.configure(.init(statusCode: 200, body: Data(index.utf8)))
        let service = makeService()
        let server = KeyServerConfig(name: "Secure", hostname: "keys.example.com", protocol: .hkps)

        let results = try await service.search(query: "user", on: server)

        #expect(results.first(where: { $0.fingerprint == "AAAA000000000000" })?.algorithm == "RSA")
        #expect(results.first(where: { $0.fingerprint == "BBBB000000000000" })?.algorithm == "EdDSA")
    }

    @Test("Percent-encoded UID content is decoded")
    func testPercentEncodedUID() async throws {
        let index = """
        info:1:1
        pub:CCCC000000000000:1:2048:1640000000::
        uid:Alice%20%3Calice%40example.com%3E:1640000000::
        """
        CapturingURLProtocol.configure(.init(statusCode: 200, body: Data(index.utf8)))
        let service = makeService()
        let server = KeyServerConfig(name: "Secure", hostname: "keys.example.com", protocol: .hkps)

        let results = try await service.search(query: "alice", on: server)
        #expect(results.first?.userIDs.first == "Alice <alice@example.com>")
    }

    // MARK: - Fetched-key identity validation

    @Test("A fetched key matching the selected fingerprint is accepted")
    func testFetchValidatedKeyMatches() async throws {
        let generator = KeyGenerator()
        generator.keyBitsLength = 2048
        let key = try generator.generate(for: "fetch-match@example.com", passphrase: "p")
        let armored = try Armor.armored(try PublicKeyExport.export(key), as: .publicKey)

        CapturingURLProtocol.configure(.init(statusCode: 200, body: Data(armored.utf8)))
        let service = makeService()
        let server = KeyServerConfig(name: "Secure", hostname: "keys.example.com", protocol: .hkps)

        let data = try await service.fetchValidatedKey(matching: key.fingerprint, from: server)
        let imported = try RNP.readKeys(from: data)
        #expect(imported.first?.fingerprint == key.fingerprint)
    }

    @Test("A fetched key whose fingerprint differs from the selection is rejected")
    func testFetchValidatedKeyMismatchRejected() async throws {
        let generator = KeyGenerator()
        generator.keyBitsLength = 2048
        let key = try generator.generate(for: "fetch-mismatch@example.com", passphrase: "p")
        let armored = try Armor.armored(try PublicKeyExport.export(key), as: .publicKey)

        CapturingURLProtocol.configure(.init(statusCode: 200, body: Data(armored.utf8)))
        let service = makeService()
        let server = KeyServerConfig(name: "Secure", hostname: "keys.example.com", protocol: .hkps)

        await #expect(throws: KeyServerError.self) {
            _ = try await service.fetchValidatedKey(matching: "0000000000000000000000000000000000000000", from: server)
        }
    }

    // MARK: - Timeout mapping

    @Test("A request timeout surfaces the typed .timeout error")
    func testTimeoutMapping() async {
        CapturingURLProtocol.configure(.init(failure: URLError(.timedOut)))
        let service = makeService()
        let server = KeyServerConfig(name: "Secure", hostname: "keys.example.com", protocol: .hkps)

        do {
            _ = try await service.search(query: "alice", on: server)
            Issue.record("Expected a timeout error")
        } catch let error as KeyServerError {
            guard case .timeout = error else {
                Issue.record("Expected .timeout, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected KeyServerError, got \(error)")
        }
    }
}
