import Foundation
import RNPKit

nonisolated private enum UploadFailureReason {
    case sanitizeArmoredKey
    case armorKey
    case multipleKeysBundled
    case invalidKeyData
    case encodeArmoredKeyData

    var localizedDescription: String {
        switch self {
        case .sanitizeArmoredKey:
            return NSLocalizedString("error.upload_failed.reason.sanitize_armored_key", comment: "Reason when armored key data could not be sanitized before upload")
        case .armorKey:
            return NSLocalizedString("error.upload_failed.reason.armor_key", comment: "Reason when key data could not be armored before upload")
        case .multipleKeysBundled:
            return NSLocalizedString("error.upload_failed.reason.multiple_keys_bundled", comment: "Reason when multiple keys are bundled in a single upload payload")
        case .invalidKeyData:
            return NSLocalizedString("error.upload_failed.reason.invalid_key_data", comment: "Reason when uploaded key data cannot be parsed")
        case .encodeArmoredKeyData:
            return NSLocalizedString("error.upload_failed.reason.encode_armored_key_data", comment: "Reason when armored key data cannot be encoded for upload")
        }
    }
}

nonisolated enum KeyServerError: LocalizedError {
    case invalidURL
    case networkError(underlying: Error)
    case serverError(statusCode: Int)
    case invalidResponse
    case keyNotFound
    case uploadFailed(reason: String)
    case timeout
    case noEnabledServers
    case insecureTransportNotAllowed(host: String)
    case insecureUploadProhibited(host: String)
    /// The key material returned by the server did not contain the full
    /// fingerprint of the search result the user selected.
    case fingerprintMismatch

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("error.invalid_url.description", comment: "Error description when the keyserver URL is invalid")
        case .networkError(let error):
            return String(format: NSLocalizedString("error.network_error.description", comment: "Error description when a network error occurs connecting to keyserver"), error.localizedDescription)
        case .serverError(let statusCode):
            return String(format: NSLocalizedString("error.server_error.description", comment: "Error description when the keyserver returns an HTTP error"), statusCode)
        case .invalidResponse:
            return NSLocalizedString("error.invalid_response.description", comment: "Error description when the keyserver returns an invalid response")
        case .keyNotFound:
            return NSLocalizedString("error.key_not_found_server.description", comment: "Error description when a key is not found on the keyserver")
        case .uploadFailed(let reason):
            return String(format: NSLocalizedString("error.upload_failed.description", comment: "Error description when key upload to keyserver fails"), reason)
        case .timeout:
            return NSLocalizedString("error.timeout.description", comment: "Error description when keyserver request times out")
        case .noEnabledServers:
            return NSLocalizedString("error.no_enabled_servers.description", comment: "Error description when no keyservers are enabled in configuration")
        case .insecureTransportNotAllowed(let host):
            return String(format: NSLocalizedString("error.insecure_transport.description", comment: "Error description when a keyserver request is blocked because it uses insecure transport"), host)
        case .insecureUploadProhibited(let host):
            return String(format: NSLocalizedString("error.insecure_upload.description", comment: "Error description when a key upload is blocked because the keyserver uses insecure transport"), host)
        case .fingerprintMismatch:
            return NSLocalizedString("error.fingerprint_mismatch.description", comment: "Error description when a fetched key does not match the selected search result's fingerprint")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("error.invalid_url.recovery", comment: "Recovery suggestion when the keyserver URL is invalid")
        case .networkError:
            return NSLocalizedString("error.network_error.recovery", comment: "Recovery suggestion when a network error occurs")
        case .serverError:
            return NSLocalizedString("error.server_error.recovery", comment: "Recovery suggestion when the keyserver returns an error")
        case .invalidResponse:
            return NSLocalizedString("error.invalid_response.recovery", comment: "Recovery suggestion when the keyserver returns invalid data")
        case .keyNotFound:
            return NSLocalizedString("error.key_not_found_server.recovery", comment: "Recovery suggestion when a key is not found on the keyserver")
        case .uploadFailed:
            return NSLocalizedString("error.upload_failed.recovery", comment: "Recovery suggestion when key upload fails")
        case .timeout:
            return NSLocalizedString("error.timeout.recovery", comment: "Recovery suggestion when keyserver request times out")
        case .noEnabledServers:
            return NSLocalizedString("error.no_enabled_servers.recovery", comment: "Recovery suggestion when no keyservers are enabled")
        case .insecureTransportNotAllowed:
            return NSLocalizedString("error.insecure_transport.recovery", comment: "Recovery suggestion when a keyserver request is blocked because it uses insecure transport")
        case .insecureUploadProhibited:
            return NSLocalizedString("error.insecure_upload.recovery", comment: "Recovery suggestion when a key upload is blocked because the keyserver uses insecure transport")
        case .fingerprintMismatch:
            return NSLocalizedString("error.fingerprint_mismatch.recovery", comment: "Recovery suggestion when a fetched key does not match the selected search result")
        }
    }
}

nonisolated struct KeySearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let fingerprint: String
    let shortKeyID: String
    let userIDs: [String]
    let algorithm: String
    let keySize: Int
    let creationDate: Date?
    let expirationDate: Date?
    let isRevoked: Bool
    let keyData: Data?

    var primaryUserID: String? {
        userIDs.first
    }

    var displayName: String {
        primaryUserID ?? shortKeyID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: KeySearchResult, rhs: KeySearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
@Observable
final class KeyServerService {
    private(set) var isSearching = false
    private(set) var isUploading = false
    private(set) var isFetching = false
    private(set) var lastError: KeyServerError?
    private(set) var searchResults: [KeySearchResult] = []

    private let urlSession: URLSession
    private var currentTask: URLSessionTask?
    private var activeSearchID: UUID?

    init(configuration: URLSessionConfiguration = .default) {
        self.urlSession = URLSession(configuration: configuration)
    }

    // MARK: - Transport Security

    /// Enforces MacPGP's insecure-transport policy at the service boundary so that an
    /// enabled server toggle alone can never trigger a plaintext request:
    /// - Secure (HKPS/HTTPS) servers are always allowed.
    /// - Insecure (HKP/HTTP) search/fetch/refresh requires an explicit opt-in
    ///   (`server.allowInsecure`).
    /// - Uploading key material over insecure transport is always prohibited,
    ///   regardless of the opt-in.
    private func ensureTransportAllowed(for server: KeyServerConfig, isUpload: Bool) throws {
        guard !server.isSecure else { return }

        let error: KeyServerError
        if isUpload {
            error = .insecureUploadProhibited(host: server.hostname)
        } else if server.allowInsecure {
            return
        } else {
            error = .insecureTransportNotAllowed(host: server.hostname)
        }

        lastError = error
        throw error
    }

    /// Maps a transport-layer error to a typed `KeyServerError`, so an actual
    /// request timeout surfaces the `.timeout` case (and its recovery copy)
    /// rather than a generic `.networkError`.
    private nonisolated static func mapTransportError(_ error: Error) -> KeyServerError {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return .timeout
        }
        return .networkError(underlying: error)
    }

    // MARK: - Search Operations

    func search(query: String, on server: KeyServerConfig) async throws -> [KeySearchResult] {
        guard !query.isEmpty else { return [] }

        try ensureTransportAllowed(for: server, isUpload: false)

        let searchID = UUID()
        activeSearchID = searchID
        isSearching = true
        lastError = nil
        defer { finishSearch(searchID) }

        // Build search URL using HKP protocol
        guard let searchURL = buildSearchURL(query: query, server: server) else {
            throw KeyServerError.invalidURL
        }

        var request = URLRequest(url: searchURL)
        request.timeoutInterval = server.timeout

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw KeyServerError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 404 {
                    throw KeyServerError.keyNotFound
                }
                throw KeyServerError.serverError(statusCode: httpResponse.statusCode)
            }

            let results = try await Self.parseSearchResults(data)
            if isCurrentSearch(searchID) {
                searchResults = results
            }
            return results

        } catch let error as KeyServerError {
            if isCurrentSearch(searchID) {
                lastError = error
            }
            throw error
        } catch {
            let wrappedError = Self.mapTransportError(error)
            if isCurrentSearch(searchID) {
                lastError = wrappedError
            }
            throw wrappedError
        }
    }

    private func isCurrentSearch(_ searchID: UUID) -> Bool {
        activeSearchID == searchID
    }

    private func finishSearch(_ searchID: UUID) {
        guard isCurrentSearch(searchID) else { return }
        isSearching = false
        activeSearchID = nil
    }

    // MARK: - Fetch Operations

    func fetchKey(fingerprint: String, from server: KeyServerConfig) async throws -> Data {
        try ensureTransportAllowed(for: server, isUpload: false)

        isFetching = true
        lastError = nil
        defer { isFetching = false }

        guard let fetchURL = buildFetchURL(fingerprint: fingerprint, server: server) else {
            throw KeyServerError.invalidURL
        }

        var request = URLRequest(url: fetchURL)
        request.timeoutInterval = server.timeout

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw KeyServerError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 404 {
                    throw KeyServerError.keyNotFound
                }
                throw KeyServerError.serverError(statusCode: httpResponse.statusCode)
            }

            return data

        } catch let error as KeyServerError {
            lastError = error
            throw error
        } catch {
            let wrappedError = Self.mapTransportError(error)
            lastError = wrappedError
            throw wrappedError
        }
    }

    func fetchKey(keyID: String, from server: KeyServerConfig) async throws -> Data {
        return try await fetchKey(fingerprint: keyID, from: server)
    }

    func refreshKey(fingerprint: String, from server: KeyServerConfig) async throws -> Data {
        return try await fetchKey(fingerprint: fingerprint, from: server)
    }

    /// Fetches a key and binds it to the search result the user selected: the
    /// returned material must contain a key whose fingerprint matches
    /// `expectedFingerprint`. Returns the armored public key of only the matching
    /// key, so a server response that bundles or substitutes keys cannot import
    /// anything the user did not select. Throws `.fingerprintMismatch` otherwise.
    func fetchValidatedKey(matching expectedFingerprint: String, from server: KeyServerConfig) async throws -> Data {
        let data = try await fetchKey(fingerprint: expectedFingerprint, from: server)
        do {
            return try await Self.validatedKeyData(data, matching: expectedFingerprint)
        } catch let error as KeyServerError {
            lastError = error
            throw error
        }
    }

    private nonisolated static func validatedKeyData(_ data: Data, matching expectedFingerprint: String) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let keys: [Key]
            do {
                keys = try RNP.readKeys(from: data)
            } catch {
                throw KeyServerError.invalidResponse
            }

            let expected = normalizeFingerprint(expectedFingerprint)
            guard !expected.isEmpty else { throw KeyServerError.fingerprintMismatch }

            guard let match = keys.first(where: { key in
                let actual = normalizeFingerprint(key.fingerprint)
                // Exact full-fingerprint match, or suffix match when the selected
                // result only carried a key ID.
                return actual == expected || actual.hasSuffix(expected)
            }) else {
                throw KeyServerError.fingerprintMismatch
            }

            // Re-export only the matching key (armored) so bundled extras are dropped.
            let publicKeyData = try PublicKeyExport.export(match)
            let armored = try Armor.armored(publicKeyData, as: .publicKey)
            guard let armoredData = armored.data(using: .utf8) else {
                throw KeyServerError.invalidResponse
            }
            return armoredData
        }.value
    }

    private nonisolated static func normalizeFingerprint(_ fingerprint: String) -> String {
        fingerprint.uppercased().filter(\.isHexDigit)
    }

    // MARK: - Upload Operations

    func uploadKey(_ keyData: Data, to server: KeyServerConfig) async throws {
        try ensureTransportAllowed(for: server, isUpload: true)

        isUploading = true
        lastError = nil
        defer { isUploading = false }

        guard let uploadURL = buildUploadURL(server: server) else {
            throw KeyServerError.invalidURL
        }

        let armoredPayload = String(data: keyData, encoding: .utf8)
        let isArmoredPayload = armoredPayload?.contains("-----BEGIN PGP") == true

        let armoredData: Data
        do {
            armoredData = try await Self.sanitizedPublicArmoredKeyData(from: keyData)
        } catch let error as KeyServerError {
            lastError = error
            throw error
        } catch {
            let reason: UploadFailureReason = isArmoredPayload ? .sanitizeArmoredKey : .armorKey
            let wrappedError = KeyServerError.uploadFailed(reason: reason.localizedDescription)
            lastError = wrappedError
            throw wrappedError
        }

        // Prepare form data for HKP upload
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = server.timeout

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"keytext\"\r\n\r\n".data(using: .utf8)!)
        body.append(armoredData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        do {
            let (_, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw KeyServerError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw KeyServerError.serverError(statusCode: httpResponse.statusCode)
            }

        } catch let error as KeyServerError {
            lastError = error
            throw error
        } catch {
            let wrappedError = Self.mapTransportError(error)
            lastError = wrappedError
            throw wrappedError
        }
    }

    private nonisolated static func sanitizedPublicArmoredKeyData(from keyData: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try sanitizedPublicArmoredKeyDataSynchronously(from: keyData)
        }.value
    }

    private nonisolated static func sanitizedPublicArmoredKeyDataSynchronously(from keyData: Data) throws -> Data {
        let keys = try KeyringPersistence().importKey(from: keyData)
        guard keys.count <= 1 else {
            throw KeyServerError.uploadFailed(reason: UploadFailureReason.multipleKeysBundled.localizedDescription)
        }
        guard let firstKey = keys.first else {
            throw KeyServerError.uploadFailed(reason: UploadFailureReason.invalidKeyData.localizedDescription)
        }

        let publicKeyData = try PublicKeyExport.export(firstKey)
        let armoredString = try Armor.armored(publicKeyData, as: .publicKey)
        guard let armoredData = armoredString.data(using: .utf8) else {
            throw KeyServerError.uploadFailed(reason: UploadFailureReason.encodeArmoredKeyData.localizedDescription)
        }

        return armoredData
    }

    // MARK: - URL Building

    private func buildSearchURL(query: String, server: KeyServerConfig) -> URL? {
        guard let baseURL = server.transportURL else { return nil }

        // HKP search endpoint: /pks/lookup?op=index&search=<query>
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/pks/lookup"
        components?.queryItems = [
            URLQueryItem(name: "op", value: "index"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "options", value: "mr") // Machine-readable format
        ]

        return components?.url
    }

    private func buildFetchURL(fingerprint: String, server: KeyServerConfig) -> URL? {
        guard let baseURL = server.transportURL else { return nil }

        // HKP fetch endpoint: /pks/lookup?op=get&search=0x<fingerprint>
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/pks/lookup"
        components?.queryItems = [
            URLQueryItem(name: "op", value: "get"),
            URLQueryItem(name: "search", value: "0x\(fingerprint)"),
            URLQueryItem(name: "options", value: "mr")
        ]

        return components?.url
    }

    private func buildUploadURL(server: KeyServerConfig) -> URL? {
        guard let baseURL = server.transportURL else { return nil }

        // HKP upload endpoint: /pks/add
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/pks/add"

        return components?.url
    }

    // MARK: - Response Parsing

    private nonisolated static func parseSearchResults(_ data: Data) async throws -> [KeySearchResult] {
        try await Task.detached(priority: .userInitiated) {
            try parseSearchResultsSynchronously(data)
        }.value
    }

    /// Accumulates the records of one key from an HKP machine-readable response.
    nonisolated private struct HKPKeyRecord {
        /// The identifier from the `pub` record's first field (a key ID on
        /// standard servers, or a full fingerprint on some).
        var pubField: String
        /// The full fingerprint from a following `fpr` record, when present.
        var fpr: String?
        var algo: String
        var keylen: Int
        var creation: Date?
        var expiration: Date?
        var revoked: Bool
        var uids: [String] = []

        /// The authoritative fingerprint: the `fpr` record if the server provided
        /// one, otherwise the `pub` field.
        var fingerprint: String { fpr ?? pubField }
    }

    private nonisolated static func parseSearchResultsSynchronously(_ data: Data) throws -> [KeySearchResult] {
        // Parse the HKP machine-readable format:
        //   info:<version>:<count>
        //   pub:<keyid|fingerprint>:<algo>:<keylen>:<creation>:<expiration>:<flags>
        //   fpr:<fingerprint>                      (optional, follows its pub)
        //   uid:<escaped uid>:<creation>:<expiration>:<flags>

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw KeyServerError.invalidResponse
        }

        var results: [KeySearchResult] = []
        var currentKey: HKPKeyRecord?

        func flush() {
            if let key = currentKey {
                results.append(createSearchResult(from: key))
            }
        }

        let lines = responseString.components(separatedBy: .newlines)

        for line in lines {
            let components = line.components(separatedBy: ":")
            guard let recordType = components.first else { continue }

            switch recordType {
            case "pub":
                flush()

                guard components.count >= 6 else {
                    currentKey = nil
                    continue
                }
                let pubField = components[1]
                let algo = components[2]
                let keylen = Int(components[3]) ?? 0
                let creationTimestamp = TimeInterval(components[4]) ?? 0
                let creation = creationTimestamp > 0 ? Date(timeIntervalSince1970: creationTimestamp) : nil

                var expiration: Date?
                if !components[5].isEmpty, let expirationTimestamp = TimeInterval(components[5]) {
                    expiration = Date(timeIntervalSince1970: expirationTimestamp)
                }

                let revoked = components.count >= 7 && components[6].contains("r")

                currentKey = HKPKeyRecord(
                    pubField: pubField,
                    fpr: nil,
                    algo: algo,
                    keylen: keylen,
                    creation: creation,
                    expiration: expiration,
                    revoked: revoked
                )

            case "fpr":
                // The fpr record carries the full fingerprint and is authoritative
                // over the pub field's identifier.
                guard components.count >= 2, !components[1].isEmpty else { continue }
                currentKey?.fpr = components[1]

            case "uid":
                guard components.count >= 2 else { continue }
                let uid = components[1].removingPercentEncoding ?? components[1]
                // A revoked uid flag does not revoke the key; key revocation comes
                // from the pub record's flags.
                currentKey?.uids.append(uid)

            default:
                continue
            }
        }

        flush()
        return results
    }

    private nonisolated static func createSearchResult(from key: HKPKeyRecord) -> KeySearchResult {
        let fingerprint = key.fingerprint

        return KeySearchResult(
            id: fingerprint,
            fingerprint: fingerprint,
            shortKeyID: String(fingerprint.suffix(16)),
            userIDs: key.uids,
            algorithm: normalizedAlgorithm(key.algo),
            keySize: key.keylen,
            creationDate: key.creation,
            expirationDate: key.expiration,
            isRevoked: key.revoked,
            keyData: nil
        )
    }

    /// Maps an OpenPGP public-key algorithm identifier (RFC 4880 §9.1) from an
    /// HKP record to a user-facing name, so search results never display a raw
    /// numeric code.
    private nonisolated static func normalizedAlgorithm(_ raw: String) -> String {
        switch raw {
        case "1", "2", "3": return "RSA"
        case "16", "20": return "ElGamal"
        case "17": return "DSA"
        case "18": return "ECDH"
        case "19": return "ECDSA"
        case "22": return "EdDSA"
        default: return raw.isEmpty ? "Unknown" : "Algorithm \(raw)"
        }
    }

    // MARK: - Utility

    func clearResults() {
        searchResults = []
    }

    func clearError() {
        lastError = nil
    }
}
