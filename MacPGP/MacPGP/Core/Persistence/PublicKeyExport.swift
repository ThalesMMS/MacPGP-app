import Foundation
import RNPKit

enum PublicKeyExport {
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
