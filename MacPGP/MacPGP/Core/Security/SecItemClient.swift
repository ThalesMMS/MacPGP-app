import Foundation
import Security

/// Thin seam over the `SecItem*` Keychain Services functions so `KeychainManager`
/// query paths (including the missing-entitlement branch) can be asserted in
/// tests without depending on the test host's actual signing/entitlements.
nonisolated protocol SecItemClient: Sendable {
    func add(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

/// Default client backed by the system Keychain Services.
nonisolated struct SystemSecItemClient: SecItemClient {
    func add(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemAdd(attributes, result)
    }
    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemCopyMatching(query, result)
    }
    func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributesToUpdate)
    }
    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}
