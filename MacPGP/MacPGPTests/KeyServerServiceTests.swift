//
//  KeyServerServiceTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 10/02/26.
//

import Testing
import Foundation
import RNPKit
@testable import MacPGP

nonisolated private func waitForSemaphore(
    _ semaphore: DispatchSemaphore,
    timeout: DispatchTime
) -> DispatchTimeoutResult {
    semaphore.wait(timeout: timeout)
}

// MARK: - Mock URLSession Support

class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var asyncRequestHandler: ((MockURLProtocol, URLRequest) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        if let asyncRequestHandler = MockURLProtocol.asyncRequestHandler {
            asyncRequestHandler(self, request)
            return
        }

        guard let handler = MockURLProtocol.requestHandler else {
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op
    }

    func complete(response: HTTPURLResponse, data: Data) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
@Suite("KeyServerService Tests", .serialized)
struct KeyServerServiceTests {
    private static let cachedUploadArmoredKeys: (publicKey: String, secretKey: String) = {
        let keyGenerator = KeyGenerator()
        keyGenerator.keyBitsLength = 2048

        let key = try! keyGenerator.generate(for: "upload@example.com", passphrase: "testpass")
        let publicKeyData = try! PublicKeyExport.export(key)
        let secretKeyData = try! key.export()

        return (
            publicKey: try! Armor.armored(publicKeyData, as: .publicKey),
            secretKey: try! Armor.armored(secretKeyData, as: .secretKey)
        )
    }()
    private static let cachedAlternateArmoredPublicKey: String = {
        let keyGenerator = KeyGenerator()
        keyGenerator.keyBitsLength = 2048

        let key = try! keyGenerator.generate(for: "upload-alt@example.com", passphrase: "testpass")
        let publicKeyData = try! PublicKeyExport.export(key)
        return try! Armor.armored(publicKeyData, as: .publicKey)
    }()

    // MARK: - Test Configuration

    init() {
        // Clean up any previous test state
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.asyncRequestHandler = nil
    }

    func createMockService() -> KeyServerService {
        // Reset handler before creating service to ensure clean state
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.asyncRequestHandler = nil

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return KeyServerService(configuration: config)
    }

    func createTestServer() -> KeyServerConfig {
        return KeyServerConfig(
            name: "Test Server",
            hostname: "test.keyserver.com",
            protocol: .hkps
        )
    }

    func createArmoredPublicKey() -> String {
        Self.cachedUploadArmoredKeys.publicKey
    }

    func createArmoredSecretKey() -> String {
        Self.cachedUploadArmoredKeys.secretKey
    }

    nonisolated static func requestBodyString(from request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8) ?? ""
        }

        guard let stream = request.httpBodyStream else {
            return ""
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            guard bytesRead > 0 else { break }
            data.append(buffer, count: bytesRead)
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func waitForSignal(_ semaphore: DispatchSemaphore, context: String) async {
        let result = await Task.detached {
            waitForSemaphore(semaphore, timeout: .now() + 5)
        }.value

        if result != .success {
            Issue.record("Timed out waiting for \(context)")
        }
    }

    // MARK: - Initialization Tests

    @Test("KeyServerService initializes correctly")
    func testInitialization() {
        let service = KeyServerService()

        #expect(!service.isSearching)
        #expect(!service.isUploading)
        #expect(!service.isFetching)
        #expect(service.lastError == nil)
        #expect(service.searchResults.isEmpty)
    }

    // MARK: - Search Operation Tests

    @Test("Search with empty query returns empty results")
    func testSearchEmptyQuery() async throws {
        let service = createMockService()
        let server = createTestServer()

        let results = try await service.search(query: "", on: server)

        #expect(results.isEmpty)
        #expect(!service.isSearching)
    }

    @Test("Search with valid query returns results")
    func testSearchValidQuery() async throws {
        let service = createMockService()
        let server = createTestServer()

        // Mock successful search response
        let mockResponse = """
        info:1:1
        pub:ABCD1234EFGH5678:1:2048:1640000000:1735689600:
        uid:Test User <test@example.com>:1640000000::
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, mockResponse.data(using: .utf8)!)
        }

        let results = try await service.search(query: "test@example.com", on: server)

        #expect(!results.isEmpty)
        #expect(results.count == 1)
        #expect(results[0].fingerprint == "ABCD1234EFGH5678")
        #expect(results[0].userIDs.contains("Test User <test@example.com>"))
        #expect(!service.isSearching)
    }

    @Test("Search with 404 response throws keyNotFound error")
    func testSearchKeyNotFound() async throws {
        let service = createMockService()
        let server = createTestServer()

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        await #expect(throws: KeyServerError.self) {
            _ = try await service.search(query: "nonexistent", on: server)
        }

        #expect(service.lastError != nil)
        #expect(!service.isSearching)
    }

    @Test("Search with server error throws serverError")
    func testSearchServerError() async throws {
        let service = createMockService()
        let server = createTestServer()

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        await #expect(throws: KeyServerError.self) {
            _ = try await service.search(query: "test", on: server)
        }

        #expect(!service.isSearching)
    }

    @Test("Search with multiple keys returns all results")
    func testSearchMultipleKeys() async throws {
        let service = createMockService()
        let server = createTestServer()

        let mockResponse = """
        info:1:2
        pub:AAAA1111BBBB2222:1:2048:1640000000::
        uid:User One <user1@example.com>:1640000000::
        pub:CCCC3333DDDD4444:1:4096:1641000000::
        uid:User Two <user2@example.com>:1641000000::
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, mockResponse.data(using: .utf8)!)
        }

        let results = try await service.search(query: "example.com", on: server)

        #expect(results.count == 2)
        #expect(results[0].fingerprint == "AAAA1111BBBB2222")
        #expect(results[1].fingerprint == "CCCC3333DDDD4444")
    }

    @Test("Search with revoked key marks it correctly")
    func testSearchRevokedKey() async throws {
        let service = createMockService()
        let server = createTestServer()

        let mockResponse = """
        info:1:1
        pub:REVOKED123456789:1:2048:1640000000::r
        uid:Revoked User <revoked@example.com>:1640000000::
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, mockResponse.data(using: .utf8)!)
        }

        let results = try await service.search(query: "revoked", on: server)

        #expect(results.count == 1)
        #expect(results[0].isRevoked == true)
    }

    // MARK: - Fetch Operation Tests

    @Test("Fetch key with valid fingerprint returns data")
    func testFetchKeySuccess() async throws {
        let service = createMockService()
        let server = createTestServer()

        let mockKeyData = "-----BEGIN PGP PUBLIC KEY BLOCK-----\ntest\n-----END PGP PUBLIC KEY BLOCK-----"

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, mockKeyData.data(using: .utf8)!)
        }

        let data = try await service.fetchKey(fingerprint: "ABCD1234", from: server)

        #expect(!data.isEmpty)
        #expect(!service.isFetching)
    }

    @Test("Fetch key with 404 throws keyNotFound")
    func testFetchKeyNotFound() async throws {
        let service = createMockService()
        let server = createTestServer()

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        await #expect(throws: KeyServerError.self) {
            _ = try await service.fetchKey(fingerprint: "NONEXISTENT", from: server)
        }

        #expect(!service.isFetching)
    }

    @Test("Fetch key by keyID calls fetchKey")
    func testFetchKeyByKeyID() async throws {
        let service = createMockService()
        let server = createTestServer()

        let mockKeyData = "-----BEGIN PGP PUBLIC KEY BLOCK-----\ntest\n-----END PGP PUBLIC KEY BLOCK-----"

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, mockKeyData.data(using: .utf8)!)
        }

        let data = try await service.fetchKey(keyID: "12345678", from: server)

        #expect(!data.isEmpty)
    }

    @Test("Refresh key calls fetchKey")
    func testRefreshKey() async throws {
        let service = createMockService()
        let server = createTestServer()

        let mockKeyData = "-----BEGIN PGP PUBLIC KEY BLOCK-----\ntest\n-----END PGP PUBLIC KEY BLOCK-----"

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, mockKeyData.data(using: .utf8)!)
        }

        let data = try await service.refreshKey(fingerprint: "ABCD1234", from: server)

        #expect(!data.isEmpty)
        #expect(!service.isFetching)
    }

    // MARK: - Upload Operation Tests

    @Test("Upload armored key succeeds")
    func testUploadArmoredKey() async throws {
        let service = createMockService()
        let server = createTestServer()

        let armoredKey = createArmoredPublicKey()

        MockURLProtocol.requestHandler = { request in
            let body = Self.requestBodyString(from: request)
            #expect(body.contains("BEGIN PGP PUBLIC KEY BLOCK"))
            #expect(!body.contains("BEGIN PGP PRIVATE KEY BLOCK"))

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        try await service.uploadKey(armoredKey.data(using: .utf8)!, to: server)

        #expect(!service.isUploading)
        #expect(service.lastError == nil)
    }

    @Test("Upload with server error throws serverError")
    func testUploadServerError() async throws {
        let service = createMockService()
        let server = createTestServer()

        let armoredKey = createArmoredPublicKey()

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        await #expect(throws: KeyServerError.self) {
            try await service.uploadKey(armoredKey.data(using: .utf8)!, to: server)
        }

        #expect(!service.isUploading)
    }

    // MARK: - URL Building Tests

    @Test("Search URL is built correctly")
    func testSearchURLBuilding() async throws {
        let service = createMockService()
        let server = KeyServerConfig(
            name: "Test Server",
            hostname: "test.keyserver.com",
            protocol: .hkps,
            timeout: 12
        )

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/pks/lookup")
            #expect(request.url?.query?.contains("op=index") == true)
            #expect(request.url?.query?.contains("options=mr") == true)
            #expect(request.timeoutInterval == 12)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "info:1:0\n".data(using: .utf8)!)
        }

        _ = try await service.search(query: "test", on: server)
    }

    @Test("Fetch URL is built correctly")
    func testFetchURLBuilding() async throws {
        let service = createMockService()
        let server = KeyServerConfig(
            name: "Test Server",
            hostname: "test.keyserver.com",
            protocol: .hkps,
            timeout: 12
        )

        let testFingerprint = "ABCD1234EFGH5678"

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/pks/lookup")
            #expect(request.url?.query?.contains("op=get") == true)
            #expect(request.url?.query?.contains("0x\(testFingerprint)") == true)
            #expect(request.timeoutInterval == 12)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "test".data(using: .utf8)!)
        }

        _ = try await service.fetchKey(fingerprint: testFingerprint, from: server)
    }

    @Test("Upload URL is built correctly")
    func testUploadURLBuilding() async throws {
        let service = createMockService()
        let server = createTestServer()

        let armoredKey = createArmoredPublicKey()

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/pks/add")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        try await service.uploadKey(armoredKey.data(using: .utf8)!, to: server)
    }

    @Test("Upload sanitizes armored private key payloads to public key data")
    func testUploadSanitizesPrivateKeyPayload() async throws {
        let service = createMockService()
        let server = createTestServer()

        let armoredKey = createArmoredSecretKey()

        MockURLProtocol.requestHandler = { request in
            let body = Self.requestBodyString(from: request)
            #expect(body.contains("BEGIN PGP PUBLIC KEY BLOCK"))
            #expect(!body.contains("BEGIN PGP PRIVATE KEY BLOCK"))
            #expect(!body.contains("BEGIN PGP SECRET KEY BLOCK"))

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        try await service.uploadKey(armoredKey.data(using: .utf8)!, to: server)
    }

    @Test("Upload rejects bundled key payloads")
    func testUploadRejectsBundledKeys() async throws {
        let service = createMockService()
        let server = createTestServer()

        let firstKey = createArmoredPublicKey()
        let secondKey = Self.cachedAlternateArmoredPublicKey
        let bundledKeys = "\(firstKey)\n\(secondKey)"

        MockURLProtocol.requestHandler = { _ in
            Issue.record("Upload should fail before issuing a network request")
            throw URLError(.badServerResponse)
        }

        do {
            try await service.uploadKey(bundledKeys.data(using: .utf8)!, to: server)
            Issue.record("Expected uploadFailed error")
        } catch let error as KeyServerError {
            if case .uploadFailed(let reason) = error {
                #expect(!reason.isEmpty)
            } else {
                Issue.record("Expected uploadFailed, got \(error)")
            }
        }

        if case .uploadFailed(let reason)? = service.lastError {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("Expected lastError to capture bundled key upload failure")
        }
    }

    // MARK: - Error Handling Tests

    @Test("Network error is wrapped correctly")
    func testNetworkErrorWrapping() async throws {
        let service = createMockService()
        let server = createTestServer()

        MockURLProtocol.requestHandler = { request in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await service.search(query: "test", on: server)
            Issue.record("Expected error to be thrown")
        } catch let error as KeyServerError {
            if case .networkError = error {
                // Expected
            } else {
                Issue.record("Expected networkError, got \(error)")
            }
        }

        #expect(service.lastError != nil)
    }

    @Test("Invalid response is detected")
    func testInvalidResponseDetection() async throws {
        let service = createMockService()
        let server = createTestServer()

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            // Return invalid non-UTF8 data
            return (response, Data([0xFF, 0xFE, 0xFD]))
        }

        await #expect(throws: KeyServerError.self) {
            _ = try await service.search(query: "test", on: server)
        }
    }

    // MARK: - State Management Tests

    @Test("Searching state is managed correctly")
    func testSearchingState() async throws {
        let service = createMockService()
        let server = createTestServer()
        let requestStarted = DispatchSemaphore(value: 0)
        let allowResponse = DispatchSemaphore(value: 0)

        MockURLProtocol.requestHandler = { request in
            requestStarted.signal()
            _ = allowResponse.wait(timeout: .now() + 5)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "info:1:0\n".data(using: .utf8)!)
        }

        #expect(service.isSearching == false)
        let task = Task {
            try await service.search(query: "test", on: server)
        }

        await waitForSignal(requestStarted, context: "search request")
        #expect(service.isSearching == true)
        allowResponse.signal()

        _ = try await task.value
        #expect(service.isSearching == false)
    }

    @Test("Latest overlapping search response remains published when an older search finishes last")
    func testLatestSearchResponseWinsWhenOlderRequestFinishesLast() async throws {
        let service = createMockService()
        let server = createTestServer()
        let oldStarted = DispatchSemaphore(value: 0)
        let newStarted = DispatchSemaphore(value: 0)
        let pendingQueue = DispatchQueue(label: "KeyServerServiceTests.pendingSearchRequests")
        var oldRequest: MockURLProtocol?
        var newRequest: MockURLProtocol?

        MockURLProtocol.asyncRequestHandler = { loader, request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "search" })?
                .value

            switch query {
            case "old":
                pendingQueue.sync {
                    oldRequest = loader
                }
                oldStarted.signal()
            case "new":
                pendingQueue.sync {
                    newRequest = loader
                }
                newStarted.signal()
            default:
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                )!
                loader.complete(response: response, data: Data())
            }
        }

        let oldTask = Task {
            try await service.search(query: "old", on: server)
        }
        await waitForSignal(oldStarted, context: "old search request")

        let newTask = Task {
            try await service.search(query: "new", on: server)
        }
        await waitForSignal(newStarted, context: "new search request")

        let capturedNewRequest = pendingQueue.sync {
            newRequest
        }
        guard let capturedNewRequest else {
            Issue.record("New search request was not captured")
            return
        }
        let (newResponse, newData) = Self.searchResponse(
            request: capturedNewRequest.request,
            fingerprint: "NEW1234NEW1234",
            userID: "New User <new@example.com>"
        )
        capturedNewRequest.complete(response: newResponse, data: newData)

        let newResults = try await newTask.value
        #expect(newResults.first?.fingerprint == "NEW1234NEW1234")
        #expect(service.searchResults.first?.fingerprint == "NEW1234NEW1234")

        let capturedOldRequest = pendingQueue.sync {
            oldRequest
        }
        guard let capturedOldRequest else {
            Issue.record("Old search request was not captured")
            return
        }
        let (oldResponse, oldData) = Self.searchResponse(
            request: capturedOldRequest.request,
            fingerprint: "OLD1234OLD1234",
            userID: "Old User <old@example.com>"
        )
        capturedOldRequest.complete(response: oldResponse, data: oldData)

        let oldResults = try await oldTask.value
        #expect(oldResults.first?.fingerprint == "OLD1234OLD1234")
        #expect(service.searchResults.first?.fingerprint == "NEW1234NEW1234")
        #expect(service.lastError == nil)
        #expect(!service.isSearching)
    }

    @Test("Fetching state is managed correctly")
    func testFetchingState() async throws {
        let service = createMockService()
        let server = createTestServer()
        let requestStarted = DispatchSemaphore(value: 0)
        let allowResponse = DispatchSemaphore(value: 0)

        MockURLProtocol.requestHandler = { request in
            requestStarted.signal()
            _ = allowResponse.wait(timeout: .now() + 5)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "test".data(using: .utf8)!)
        }

        #expect(service.isFetching == false)
        let task = Task {
            try await service.fetchKey(fingerprint: "TEST", from: server)
        }

        await waitForSignal(requestStarted, context: "fetch request")
        #expect(service.isFetching == true)
        allowResponse.signal()

        _ = try await task.value
        #expect(service.isFetching == false)
    }

    @Test("Uploading state is managed correctly")
    func testUploadingState() async throws {
        let service = createMockService()
        let server = createTestServer()

        let armoredKey = createArmoredPublicKey()
        let requestStarted = DispatchSemaphore(value: 0)
        let allowResponse = DispatchSemaphore(value: 0)

        MockURLProtocol.requestHandler = { request in
            requestStarted.signal()
            _ = allowResponse.wait(timeout: .now() + 5)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        #expect(service.isUploading == false)
        let task = Task {
            try await service.uploadKey(armoredKey.data(using: .utf8)!, to: server)
        }

        await waitForSignal(requestStarted, context: "upload request")
        #expect(service.isUploading == true)
        allowResponse.signal()

        try await task.value
        #expect(service.isUploading == false)
    }

    // MARK: - Utility Function Tests

    @Test("Clear results empties search results")
    func testClearResults() async throws {
        let service = createMockService()
        let server = createTestServer()

        let mockResponse = """
        info:1:1
        pub:ABCD1234EFGH5678:1:2048:1640000000::
        uid:Test User <test@example.com>:1640000000::
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, mockResponse.data(using: .utf8)!)
        }

        _ = try await service.search(query: "test", on: server)
        #expect(!service.searchResults.isEmpty)

        service.clearResults()
        #expect(service.searchResults.isEmpty)
    }

    @Test("Clear error removes last error")
    func testClearError() async throws {
        let service = createMockService()
        let server = createTestServer()

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await service.search(query: "test", on: server)
        } catch {
            // Expected
        }

        #expect(service.lastError != nil)
        service.clearError()
        #expect(service.lastError == nil)
    }

    // MARK: - KeySearchResult Tests

    @Test("KeySearchResult computes displayName correctly")
    func testKeySearchResultDisplayName() {
        let resultWithUID = KeySearchResult(
            id: "test1",
            fingerprint: "ABCD1234",
            shortKeyID: "1234",
            userIDs: ["Test User <test@example.com>"],
            algorithm: "1",
            keySize: 2048,
            creationDate: nil,
            expirationDate: nil,
            isRevoked: false,
            keyData: nil
        )

        #expect(resultWithUID.displayName == "Test User <test@example.com>")

        let resultWithoutUID = KeySearchResult(
            id: "test2",
            fingerprint: "EFGH5678",
            shortKeyID: "5678",
            userIDs: [],
            algorithm: "1",
            keySize: 2048,
            creationDate: nil,
            expirationDate: nil,
            isRevoked: false,
            keyData: nil
        )

        #expect(resultWithoutUID.displayName == "5678")
    }

    @Test("KeySearchResult hash and equality work correctly")
    func testKeySearchResultHashAndEquality() {
        let result1 = KeySearchResult(
            id: "same",
            fingerprint: "ABCD",
            shortKeyID: "1234",
            userIDs: [],
            algorithm: "1",
            keySize: 2048,
            creationDate: nil,
            expirationDate: nil,
            isRevoked: false,
            keyData: nil
        )

        let result2 = KeySearchResult(
            id: "same",
            fingerprint: "EFGH",
            shortKeyID: "5678",
            userIDs: [],
            algorithm: "1",
            keySize: 4096,
            creationDate: nil,
            expirationDate: nil,
            isRevoked: false,
            keyData: nil
        )

        let result3 = KeySearchResult(
            id: "different",
            fingerprint: "IJKL",
            shortKeyID: "9012",
            userIDs: [],
            algorithm: "1",
            keySize: 2048,
            creationDate: nil,
            expirationDate: nil,
            isRevoked: false,
            keyData: nil
        )

        #expect(result1 == result2)
        #expect(result1 != result3)
    }

    // MARK: - Response Parsing Tests

    @Test("Parse response with multiple UIDs")
    func testParseMultipleUIDs() async throws {
        let service = createMockService()
        let server = createTestServer()

        let mockResponse = """
        info:1:1
        pub:ABCD1234:1:2048:1640000000::
        uid:Primary User <primary@example.com>:1640000000::
        uid:Secondary User <secondary@example.com>:1640000000::
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, mockResponse.data(using: .utf8)!)
        }

        let results = try await service.search(query: "test", on: server)

        #expect(results.count == 1)
        #expect(results[0].userIDs.count == 2)
        #expect(results[0].userIDs.contains("Primary User <primary@example.com>"))
        #expect(results[0].userIDs.contains("Secondary User <secondary@example.com>"))
    }

    @Test("Parse response with percent-encoded UIDs")
    func testParsePercentEncodedUIDs() async throws {
        let service = createMockService()
        let server = createTestServer()

        let mockResponse = """
        info:1:1
        pub:ABCD1234:1:2048:1640000000::
        uid:Test%20User%20%3Ctest%40example.com%3E:1640000000::
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, mockResponse.data(using: .utf8)!)
        }

        let results = try await service.search(query: "test", on: server)

        #expect(results.count == 1)
        #expect(results[0].userIDs.first == "Test User <test@example.com>")
    }

    private static func searchResponse(
        request: URLRequest,
        fingerprint: String,
        userID: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let body = """
        info:1:1
        pub:\(fingerprint):1:2048:1640000000::
        uid:\(userID):1640000000::
        """
        return (response, body.data(using: .utf8)!)
    }
}
