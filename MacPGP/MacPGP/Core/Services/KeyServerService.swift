import Foundation
import ObjectivePGP

enum KeyServerError: LocalizedError {
    case invalidURL
    case networkError(underlying: Error)
    case serverError(statusCode: Int)
    case invalidResponse
    case keyNotFound
    case uploadFailed(reason: String)
    case timeout
    case noEnabledServers

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
        }
    }
}

struct KeySearchResult: Identifiable, Hashable {
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

@Observable
final class KeyServerService {
    private(set) var isSearching = false
    private(set) var isUploading = false
    private(set) var isFetching = false
    private(set) var lastError: KeyServerError?
    private(set) var searchResults: [KeySearchResult] = []

    private let urlSession: URLSession
    private var currentTask: URLSessionTask?

    init(configuration: URLSessionConfiguration = .default) {
        self.urlSession = URLSession(configuration: configuration)
    }

    // MARK: - Search Operations

    func search(query: String, on server: KeyServerConfig) async throws -> [KeySearchResult] {
        guard !query.isEmpty else { return [] }

        isSearching = true
        lastError = nil
        defer { isSearching = false }

        // Build search URL using HKP protocol
        guard let searchURL = buildSearchURL(query: query, server: server) else {
            throw KeyServerError.invalidURL
        }

        do {
            let (data, response) = try await urlSession.data(from: searchURL)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw KeyServerError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 404 {
                    throw KeyServerError.keyNotFound
                }
                throw KeyServerError.serverError(statusCode: httpResponse.statusCode)
            }

            let results = try parseSearchResults(data)
            searchResults = results
            return results

        } catch let error as KeyServerError {
            lastError = error
            throw error
        } catch {
            let wrappedError = KeyServerError.networkError(underlying: error)
            lastError = wrappedError
            throw wrappedError
        }
    }

    // MARK: - Fetch Operations

    func fetchKey(fingerprint: String, from server: KeyServerConfig) async throws -> Data {
        isFetching = true
        lastError = nil
        defer { isFetching = false }

        guard let fetchURL = buildFetchURL(fingerprint: fingerprint, server: server) else {
            throw KeyServerError.invalidURL
        }

        do {
            let (data, response) = try await urlSession.data(from: fetchURL)

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
            let wrappedError = KeyServerError.networkError(underlying: error)
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

    // MARK: - Upload Operations

    func uploadKey(_ keyData: Data, to server: KeyServerConfig) async throws {
        isUploading = true
        lastError = nil
        defer { isUploading = false }

        guard let uploadURL = buildUploadURL(server: server) else {
            throw KeyServerError.invalidURL
        }

        // Convert binary key data to ASCII armored format for upload
        let armoredData: Data
        if let armoredString = String(data: keyData, encoding: .utf8),
           armoredString.contains("-----BEGIN PGP") {
            // Already armored
            armoredData = keyData
        } else {
            // Need to armor the key
            do {
                let keys = try KeyringPersistence().importKey(from: keyData)
                guard let firstKey = keys.first else {
                    throw KeyServerError.uploadFailed(reason: "Invalid key data")
                }
                let armoredString = Armor.armored(try firstKey.export(), as: .publicKey)
                armoredData = armoredString.data(using: .utf8) ?? keyData
            } catch {
                throw KeyServerError.uploadFailed(reason: "Failed to armor key data")
            }
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
            let wrappedError = KeyServerError.networkError(underlying: error)
            lastError = wrappedError
            throw wrappedError
        }
    }

    // MARK: - URL Building

    private func buildSearchURL(query: String, server: KeyServerConfig) -> URL? {
        guard let baseURL = server.url else { return nil }

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
        guard let baseURL = server.url else { return nil }

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
        guard let baseURL = server.url else { return nil }

        // HKP upload endpoint: /pks/add
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/pks/add"

        return components?.url
    }

    // MARK: - Response Parsing

    private func parseSearchResults(_ data: Data) throws -> [KeySearchResult] {
        // Parse machine-readable format from HKP server
        // Format: info:1:1
        //         pub:fingerprint:algo:keylen:creationdate:expirationdate:flags
        //         uid:escaped uid string:creationdate:expirationdate:flags

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw KeyServerError.invalidResponse
        }

        var results: [KeySearchResult] = []
        var currentKey: (fingerprint: String, algo: String, keylen: Int, creation: Date?, expiration: Date?, revoked: Bool)?
        var currentUIDs: [String] = []

        let lines = responseString.components(separatedBy: .newlines)

        for line in lines {
            let components = line.components(separatedBy: ":")
            guard !components.isEmpty else { continue }

            let recordType = components[0]

            switch recordType {
            case "pub":
                // Save previous key if exists
                if let key = currentKey {
                    let result = createSearchResult(
                        fingerprint: key.fingerprint,
                        algo: key.algo,
                        keylen: key.keylen,
                        creation: key.creation,
                        expiration: key.expiration,
                        revoked: key.revoked,
                        uids: currentUIDs
                    )
                    results.append(result)
                }

                // Parse new key
                guard components.count >= 6 else { continue }
                let fingerprint = components[1]
                let algo = components[2]
                let keylen = Int(components[3]) ?? 0
                let creationTimestamp = TimeInterval(components[4]) ?? 0
                let creation = creationTimestamp > 0 ? Date(timeIntervalSince1970: creationTimestamp) : nil

                var expiration: Date?
                if components.count >= 6, !components[5].isEmpty,
                   let expirationTimestamp = TimeInterval(components[5]) {
                    expiration = Date(timeIntervalSince1970: expirationTimestamp)
                }

                let revoked = components.count >= 7 && components[6].contains("r")

                currentKey = (fingerprint, algo, keylen, creation, expiration, revoked)
                currentUIDs = []

            case "uid":
                guard components.count >= 2 else { continue }
                let uid = components[1].removingPercentEncoding ?? components[1]
                currentUIDs.append(uid)

            default:
                continue
            }
        }

        // Add last key
        if let key = currentKey {
            let result = createSearchResult(
                fingerprint: key.fingerprint,
                algo: key.algo,
                keylen: key.keylen,
                creation: key.creation,
                expiration: key.expiration,
                revoked: key.revoked,
                uids: currentUIDs
            )
            results.append(result)
        }

        return results
    }

    private func createSearchResult(
        fingerprint: String,
        algo: String,
        keylen: Int,
        creation: Date?,
        expiration: Date?,
        revoked: Bool,
        uids: [String]
    ) -> KeySearchResult {
        let shortKeyID = String(fingerprint.suffix(16))

        return KeySearchResult(
            id: fingerprint,
            fingerprint: fingerprint,
            shortKeyID: shortKeyID,
            userIDs: uids,
            algorithm: algo,
            keySize: keylen,
            creationDate: creation,
            expirationDate: expiration,
            isRevoked: revoked,
            keyData: nil
        )
    }

    // MARK: - Utility

    func clearResults() {
        searchResults = []
    }

    func clearError() {
        lastError = nil
    }
}
