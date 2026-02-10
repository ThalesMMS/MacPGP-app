import Foundation
import ObjectivePGP

/// Represents a node in the trust graph
struct TrustNode: Identifiable, Hashable {
    let id: String
    let key: PGPKeyModel
    let trustLevel: TrustLevel

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TrustNode, rhs: TrustNode) -> Bool {
        lhs.id == rhs.id
    }
}

/// Represents a trust relationship between two keys
struct TrustEdge: Identifiable, Hashable {
    let id: String
    let from: String  // fingerprint
    let to: String    // fingerprint
    let trustLevel: TrustLevel
    let signatureDate: Date?

    init(from: String, to: String, trustLevel: TrustLevel, signatureDate: Date? = nil) {
        self.from = from
        self.to = to
        self.trustLevel = trustLevel
        self.signatureDate = signatureDate
        self.id = "\(from)-\(to)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TrustEdge, rhs: TrustEdge) -> Bool {
        lhs.id == rhs.id
    }
}

/// Represents a path of trust from one key to another
struct TrustPath {
    let nodes: [TrustNode]
    let edges: [TrustEdge]

    var isValid: Bool {
        // A path is valid if it starts from an ultimately trusted key
        guard let firstNode = nodes.first else { return false }
        return firstNode.trustLevel == .ultimate
    }

    var effectiveTrust: TrustLevel {
        // Calculate the effective trust based on the path
        guard isValid else { return .unknown }

        // Find the minimum trust level in the path
        var minTrust = TrustLevel.ultimate
        for node in nodes {
            if node.trustLevel.trustValue < minTrust.trustValue {
                minTrust = node.trustLevel
            }
        }

        return minTrust
    }

    var length: Int {
        nodes.count
    }
}

/// Service for calculating trust relationships and paths in the Web of Trust
@Observable
final class TrustService {
    private let keyringService: KeyringService

    init(keyringService: KeyringService) {
        self.keyringService = keyringService
    }

    // MARK: - Trust Path Calculation

    /// Find all trust paths from ultimately trusted keys to the target key
    func findTrustPaths(to targetKey: PGPKeyModel) -> [TrustPath] {
        var paths: [TrustPath] = []
        let ultimateKeys = getUltimatelyTrustedKeys()

        // For each ultimately trusted key, try to find a path to the target
        for ultimateKey in ultimateKeys {
            if let path = findShortestPath(from: ultimateKey, to: targetKey) {
                paths.append(path)
            }
        }

        return paths
    }

    /// Find the shortest trust path between two keys using breadth-first search
    func findShortestPath(from source: PGPKeyModel, to target: PGPKeyModel) -> TrustPath? {
        // If source and target are the same, return a single-node path
        if source.fingerprint == target.fingerprint {
            let node = TrustNode(id: source.fingerprint, key: source, trustLevel: source.trustLevel)
            return TrustPath(nodes: [node], edges: [])
        }

        // Build the trust graph to perform BFS
        let graph = buildTrustGraph()

        // BFS data structures
        var queue: [(fingerprint: String, path: [TrustNode], edges: [TrustEdge])] = []
        var visited: Set<String> = []

        // Start from the source key
        let sourceNode = TrustNode(id: source.fingerprint, key: source, trustLevel: source.trustLevel)
        queue.append((source.fingerprint, [sourceNode], []))
        visited.insert(source.fingerprint)

        // BFS loop
        while !queue.isEmpty {
            let (currentFingerprint, currentPath, currentEdges) = queue.removeFirst()

            // Find all outgoing edges from current node
            for edge in graph.edges where edge.from == currentFingerprint {
                let nextFingerprint = edge.to

                // Skip if already visited
                if visited.contains(nextFingerprint) {
                    continue
                }

                // Find the next node
                guard let nextNode = graph.nodes.first(where: { $0.id == nextFingerprint }) else {
                    continue
                }

                // Build the new path
                var newPath = currentPath
                newPath.append(nextNode)

                var newEdges = currentEdges
                newEdges.append(edge)

                // Check if we found the target
                if nextFingerprint == target.fingerprint {
                    return TrustPath(nodes: newPath, edges: newEdges)
                }

                // Add to queue for further exploration
                queue.append((nextFingerprint, newPath, newEdges))
                visited.insert(nextFingerprint)
            }
        }

        // No path found
        return nil
    }

    /// Check if a key has a valid trust path from any ultimately trusted key
    func hasValidTrustPath(_ key: PGPKeyModel) -> Bool {
        // A key has a valid trust path if:
        // 1. It is ultimately trusted (own key), OR
        // 2. It has a trust path from an ultimately trusted key

        if key.trustLevel == .ultimate {
            return true
        }

        let paths = findTrustPaths(to: key)
        return !paths.isEmpty
    }

    /// Calculate the effective trust for a key based on all trust paths
    func calculateEffectiveTrust(for key: PGPKeyModel) -> TrustLevel {
        // If the key is set to "never", that overrides everything
        if key.trustLevel == .never {
            return .never
        }

        // If the key is ultimately trusted, that's the highest level
        if key.trustLevel == .ultimate {
            return .ultimate
        }

        // Find all trust paths to this key
        let paths = findTrustPaths(to: key)

        // If no paths exist, return unknown
        guard !paths.isEmpty else {
            return .unknown
        }

        // In PGP Web of Trust:
        // - 1 fully trusted signature is sufficient
        // - 3 marginally trusted signatures are needed
        var hasFullTrust = false
        var marginalTrustCount = 0

        for path in paths {
            let trust = path.effectiveTrust
            if trust == .full || trust == .ultimate {
                hasFullTrust = true
                break
            } else if trust == .marginal {
                marginalTrustCount += 1
            }
        }

        if hasFullTrust {
            return .full
        } else if marginalTrustCount >= 3 {
            return .marginal
        } else {
            return .unknown
        }
    }

    // MARK: - Trust Graph

    /// Build the complete trust graph for all keys
    func buildTrustGraph() -> (nodes: [TrustNode], edges: [TrustEdge]) {
        var nodes: [TrustNode] = []
        var edges: [TrustEdge] = []
        var edgeSet: Set<String> = [] // Track unique edges

        // Create nodes for all keys
        for key in keyringService.keys {
            let node = TrustNode(id: key.fingerprint, key: key, trustLevel: key.trustLevel)
            nodes.append(node)
        }

        // Build edges based on key signatures
        // For each key, find who has signed it and create edges
        for targetKey in keyringService.keys {
            let signers = getKeySigners(targetKey)

            for signer in signers {
                // Create an edge from signer to target
                let edgeId = "\(signer.fingerprint)-\(targetKey.fingerprint)"

                // Avoid duplicate edges
                if !edgeSet.contains(edgeId) {
                    let edge = TrustEdge(
                        from: signer.fingerprint,
                        to: targetKey.fingerprint,
                        trustLevel: signer.trustLevel,
                        signatureDate: nil // TODO: Extract signature date from ObjectivePGP
                    )
                    edges.append(edge)
                    edgeSet.insert(edgeId)
                }
            }
        }

        return (nodes: nodes, edges: edges)
    }

    /// Get all keys that are connected to a given key in the trust graph
    func getConnectedKeys(to key: PGPKeyModel) -> [PGPKeyModel] {
        var connected: [PGPKeyModel] = []

        // Find all keys that have signed this key
        let signers = getKeySigners(key)
        connected.append(contentsOf: signers)

        // Find all keys that this key has signed
        let signees = getKeysSignedBy(key)
        connected.append(contentsOf: signees)

        return connected
    }

    /// Get all keys that have signed the given key
    func getKeySigners(_ key: PGPKeyModel) -> [PGPKeyModel] {
        // Extract signature information from the key's certifications
        // ObjectivePGP stores signatures in the key's publicKey.users array
        // Each user ID can have multiple certifications (signatures)

        let signerFingerprints: Set<String> = []

        // Access the raw key to get signature information
        guard let rawKey = keyringService.rawKey(for: key) else {
            return []
        }

        // Try to extract signer key IDs from the key's user certifications
        // Note: ObjectivePGP's API for signature extraction is limited
        // This is a placeholder implementation that will need enhancement
        // when more ObjectivePGP signature APIs are discovered

        if let users = rawKey.publicKey?.users {
            for _ in users {
                // Each user can have certifications (signatures)
                // The user object contains signatures but accessing them requires
                // diving into ObjectivePGP's internal structures
                // For now, we return an empty list as signature extraction
                // requires deeper ObjectivePGP API exploration

                // TODO: Implement full signature extraction using ObjectivePGP API
                // This requires accessing user.signatures or similar properties
                // Example: user.signatures.forEach { sig in signerFingerprints.insert(sig.issuerKeyID) }
            }
        }

        // Map fingerprints to keys
        return keyringService.keys.filter { signerFingerprints.contains($0.fingerprint) }
    }

    /// Get all keys that the given key has signed
    func getKeysSignedBy(_ key: PGPKeyModel) -> [PGPKeyModel] {
        // To find keys signed by this key, we need to check all other keys
        // and see if they have a signature from this key

        var signedKeys: [PGPKeyModel] = []

        for otherKey in keyringService.keys {
            // Skip self
            if otherKey.fingerprint == key.fingerprint {
                continue
            }

            // Check if key has signed otherKey
            let signers = getKeySigners(otherKey)
            if signers.contains(where: { $0.fingerprint == key.fingerprint }) {
                signedKeys.append(otherKey)
            }
        }

        return signedKeys
    }

    // MARK: - Helper Methods

    /// Get all keys that are ultimately trusted (user's own keys)
    private func getUltimatelyTrustedKeys() -> [PGPKeyModel] {
        keyringService.keys.filter { $0.trustLevel == .ultimate }
    }

    /// Get all keys that can certify others (fully or ultimately trusted)
    func getCertifyingKeys() -> [PGPKeyModel] {
        keyringService.keys.filter { $0.trustLevel.canCertify }
    }

    /// Check if a key can be used to encrypt to a recipient
    func isKeyValidForEncryption(_ key: PGPKeyModel) -> Bool {
        // A key is valid for encryption if:
        // 1. It's not expired or revoked
        // 2. It's not marked as "never trust"
        // 3. It has a valid trust path (for strict mode) OR has any trust level set (for permissive mode)

        if key.isExpired || key.isRevoked {
            return false
        }

        if key.trustLevel == .never {
            return false
        }

        // For now, allow encryption to any key that's not marked as "never"
        // This can be made stricter based on user preferences
        return true
    }

    /// Get a warning message for encrypting to a key with questionable trust
    func getTrustWarning(for key: PGPKeyModel) -> String? {
        if key.trustLevel == .never {
            return "This key is marked as 'Never Trust'. Encryption is not recommended."
        }

        if key.trustLevel == .unknown && !hasValidTrustPath(key) {
            return "This key has unknown trust and no trust path from your keys."
        }

        if key.isExpired {
            return "This key has expired."
        }

        if key.isRevoked {
            return "This key has been revoked."
        }

        return nil
    }
}
