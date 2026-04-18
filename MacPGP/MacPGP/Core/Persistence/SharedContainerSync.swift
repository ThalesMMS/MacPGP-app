import Foundation
import ObjectivePGP

enum SharedContainerSync {
    static func syncKeysToContainer(keys: [Key]) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedConfiguration.appGroupIdentifier
        ) else {
            NSLog("[SharedContainerSync] Shared container unavailable for app group \(SharedConfiguration.appGroupIdentifier)")
            return
        }

        var exportedKeys = Data()
        for key in keys {
            exportedKeys.append(try key.export())
        }

        let keysURL = containerURL.appendingPathComponent(SharedConfiguration.sharedKeysFileName)
        try exportedKeys.write(to: keysURL, options: .atomic)
    }
}
