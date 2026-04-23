import Foundation
import RNPKit

enum SharedContainerSync {
    static func syncKeysToContainer(keys: [Key]) throws {
        guard let keysURL = sharedKeysURL() else {
            return
        }

        try migrateOrCleanupSharedProjection(at: keysURL, writeChanges: false)
        let exportedKeys = try PublicKeyExport.exportAll(keys)
        try exportedKeys.write(to: keysURL, options: .atomic)
    }

    static func migrateOrCleanupSharedProjection() throws {
        guard let keysURL = sharedKeysURL() else {
            return
        }

        try migrateOrCleanupSharedProjection(at: keysURL, writeChanges: true)
    }

    static func sanitizeSharedProjectionData(_ data: Data) throws -> (data: Data, removedSecretFingerprints: [String]) {
        guard !data.isEmpty else {
            return (Data(), [])
        }

        let keys: [Key] = try RNP.readKeys(from: data)
        let removedSecretFingerprints: [String] = keys.reduce(into: []) { result, key in
            guard key.isSecret else {
                return
            }

            result.append(key.publicKey?.fingerprint.description ?? "unknown")
        }

        return (
            try PublicKeyExport.exportAll(keys),
            removedSecretFingerprints
        )
    }

    private static func migrateOrCleanupSharedProjection(at keysURL: URL, writeChanges: Bool) throws {
        guard FileManager.default.fileExists(atPath: keysURL.path) else {
            return
        }

        let existingData = try Data(contentsOf: keysURL)
        let cleanup = try sanitizeSharedProjectionData(existingData)

        guard !cleanup.removedSecretFingerprints.isEmpty else {
            return
        }

        if writeChanges {
            try cleanup.data.write(to: keysURL, options: .atomic)
        }

        NSLog("[SharedContainerSync] \(redactedRemovalSummary(for: cleanup.removedSecretFingerprints))")
    }

    private static func redactedRemovalSummary(for fingerprints: [String]) -> String {
        let suffixes = fingerprints.map { fingerprint in
            String(fingerprint.suffix(4))
        }
        let suffixSummary = suffixes.isEmpty ? "none" : suffixes.joined(separator: ", ")
        return "Removed \(fingerprints.count) secret-key entr\(fingerprints.count == 1 ? "y" : "ies") from shared projection (suffixes: \(suffixSummary))"
    }

    private static func sharedKeysURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedConfiguration.appGroupIdentifier
        ) else {
            NSLog("[SharedContainerSync] Shared container unavailable for app group \(SharedConfiguration.appGroupIdentifier)")
            return nil
        }

        return containerURL.appendingPathComponent(SharedConfiguration.sharedKeysFileName)
    }
}
