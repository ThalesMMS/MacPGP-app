import Foundation

/// Deterministic `URLProtocol` used only when `KeyServerUITestSupport.isEnabled`.
///
/// It answers HKP search (`op=index`) and fetch (`op=get`) requests with fixed
/// fixtures so Keyserver UI tests never depend on internet availability or live
/// keyservers. The scenario is selected by `KeyServerUITestSupport.scenario`.
nonisolated final class KeyServerStubURLProtocol: URLProtocol {
    /// Indicates that this protocol can initialize with any URL request.
    /// - Returns: `true` always.
    override static func canInit(with request: URLRequest) -> Bool { true }

    /// Provides the canonical form of the request without modification.
    /// - Returns: The same request passed as input.
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let scenario = KeyServerUITestSupport.scenario
        let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let op = components?.queryItems?.first(where: { $0.name == "op" })?.value
        let isSearch = op == "index"
        let isFetch = op == "get"

        switch scenario {
        case .serverError:
            respond(statusCode: 500, body: Data())

        case .networkTimeout:
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))

        case .noResults:
            if isSearch {
                respond(statusCode: 200, body: Data(Self.emptyIndex.utf8))
            } else {
                respond(statusCode: 404, body: Data())
            }

        case .successMultiple, .importSuccess:
            if isSearch {
                respond(statusCode: 200, body: Data(Self.multiResultIndex.utf8))
            } else if isFetch {
                respond(statusCode: 200, body: Data(Self.fixturePublicKey.utf8))
            } else {
                respond(statusCode: 200, body: Data())
            }

        case .malformedKey:
            if isSearch {
                respond(statusCode: 200, body: Data(Self.multiResultIndex.utf8))
            } else if isFetch {
                respond(statusCode: 200, body: Data(Self.malformedKeyData.utf8))
            } else {
                respond(statusCode: 200, body: Data())
            }
        }
    }

    override func stopLoading() {}

    private func respond(statusCode: Int, body: Data) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    // MARK: - Fixtures

    static let emptyIndex = "info:1:0\n"

    /// Two deterministic results in HKP machine-readable index format. The first
    /// fingerprint matches `fixturePublicKey` so the import scenario is coherent.
    static let multiResultIndex = """
    info:1:2
    pub:6321642B5EF963758C991DE4B9EA5EB0777879D4:22:256:1554400000::
    uid:Alice (Test ecc key) <alice@example.org>:1554400000::
    pub:AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555:1:4096:1600000000::
    uid:Bob Example <bob@example.org>:1600000000::
    """

    static let malformedKeyData = "this is not a valid OpenPGP key"

    /// A real, importable EdDSA public key (synthetic identity), embedded so the
    /// import scenario succeeds without any network or test-bundle resource.
    static let fixturePublicKey = """
    -----BEGIN PGP PUBLIC KEY BLOCK-----

    mDMEXKbiLhYJKwYBBAHaRw8BAQdAeh9cNZ3kMofVDD6RKfRqGx4Xf2QP6NeAKX63
    tz2nXNi0KEFsaWNlIChUZXN0IGVjYyBrZXkpIDxhbGljZUBleGFtcGxlLm9yZz6I
    kAQTFgoAOBYhBGMhZCte+WN1jJkd5LnqXrB3eHnUBQJcpuIuAhsDBQsJCAcDBRUK
    CQgLBRYCAwEAAh4BAheAAAoJELnqXrB3eHnUn5QBAJXdRSLGHkgy7ssy77AmpQCE
    XoKoy/JDPFT8JPjmCxOyAP4tgt+muqjeJztSGX5pjD7nCMHVnyemd4c/6cQw+dSi
    D7g4BFym4i4SCisGAQQBl1UBBQEBB0CbRCmt6q4m2mOcE3oB2Q7FPRRiPIHFZ8xf
    u4fpx2vucQMBCAeIeAQYFgoAIBYhBGMhZCte+WN1jJkd5LnqXrB3eHnUBQJcpuIu
    AhsMAAoJELnqXrB3eHnUFtkBAJD/18TpbKGAUB2t94p/ETrYJmriZQUkBPFcRd++
    3nAEAP9tzCRCiYNBSsQRmSAZcyVqSRqQzy39cPm+Rn35jqdVAA==
    =fjlK
    -----END PGP PUBLIC KEY BLOCK-----
    """
}
