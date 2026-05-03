import Foundation
import RNPKit

enum SharedKeyringLoader {
    enum LoadError: LocalizedError {
        case sharedContainerUnavailable
        case readFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .sharedContainerUnavailable:
                return "Shared key container is unavailable"
            case .readFailed(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    nonisolated static func loadKeys() throws -> [Key] {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: SharedConfiguration.appGroupIdentifier
        ) else {
            NSLog("SharedKeyringLoader: Shared container unavailable for app group \(SharedConfiguration.appGroupIdentifier)")
            throw LoadError.sharedContainerUnavailable
        }

        let keysURL = containerURL.appendingPathComponent(SharedConfiguration.sharedKeysFileName)
        guard fileManager.fileExists(atPath: keysURL.path) else {
            return []
        }

        do {
            let keysData = try Data(contentsOf: keysURL)
            guard !keysData.isEmpty else {
                return []
            }

            return try RNP.readKeys(from: keysData)
        } catch {
            NSLog("SharedKeyringLoader: Failed to read keys: \(error.localizedDescription)")
            throw LoadError.readFailed(underlying: error)
        }
    }
}
