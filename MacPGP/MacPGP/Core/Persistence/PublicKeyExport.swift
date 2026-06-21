import Foundation
import RNPKit

nonisolated enum PublicKeyExport {
    /// Exports the public representation of a key.
    /// - Parameters:
    ///   - key: The key to export.
    /// - Returns: The exported public key as `Data`.
    static func export(_ key: Key) throws -> Data {
        try key.exportPublic()
    }

    static func exportAll(_ keys: [Key]) throws -> Data {
        var exportedKeys = Data()

        for key in keys {
            exportedKeys.append(try export(key))
        }

        return exportedKeys
    }
}
