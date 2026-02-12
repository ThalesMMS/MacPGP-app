import Foundation
import SwiftUI

@Observable
final class KeyringViewModel {
    var searchText: String = ""
    var sortOrder: KeySortOrder = .name
    var filterType: KeyFilterType = .all
    var showingDeleteConfirmation = false
    var keyToDelete: PGPKeyModel?
    var alertMessage: String?
    var showingAlert = false

    private let keyringService: KeyringService

    init(keyringService: KeyringService) {
        self.keyringService = keyringService
    }

    var filteredKeys: [PGPKeyModel] {
        var keys = keyringService.keys

        if !searchText.isEmpty {
            keys = keyringService.search(searchText)
        }

        switch filterType {
        case .all:
            break
        case .secret:
            keys = keys.filter { $0.isSecretKey }
        case .public:
            keys = keys.filter { !$0.isSecretKey }
        case .expired:
            keys = keys.filter { $0.isExpired }
        case .revoked:
            keys = keys.filter { $0.isRevoked }
        }

        switch sortOrder {
        case .name:
            keys.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .date:
            keys.sort { $0.creationDate > $1.creationDate }
        case .keyID:
            keys.sort { $0.shortKeyID < $1.shortKeyID }
        }

        return keys
    }

    func confirmDelete(_ key: PGPKeyModel) {
        keyToDelete = key
        showingDeleteConfirmation = true
    }

    func deleteKey() {
        guard let key = keyToDelete else { return }

        do {
            try keyringService.deleteKey(key)
        } catch {
            alertMessage = "Failed to delete key: \(error.localizedDescription)"
            showingAlert = true
        }

        keyToDelete = nil
    }

    func exportKey(_ key: PGPKeyModel, includeSecret: Bool) throws -> Data {
        try keyringService.exportKey(key, includeSecretKey: includeSecret, armored: true)
    }
}

enum KeySortOrder: String, CaseIterable, Identifiable {
    case name
    case date
    case keyID

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: return String(localized: "keyring.sort.name", defaultValue: "Name", comment: "Sort keys by name")
        case .date: return String(localized: "keyring.sort.date", defaultValue: "Date", comment: "Sort keys by date")
        case .keyID: return String(localized: "keyring.sort.key_id", defaultValue: "Key ID", comment: "Sort keys by key ID")
        }
    }
}

enum KeyFilterType: String, CaseIterable, Identifiable {
    case all
    case secret
    case `public`
    case expired
    case revoked

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return String(localized: "keyring.filter.all", defaultValue: "All Keys", comment: "Filter to show all keys")
        case .secret: return String(localized: "keyring.filter.secret", defaultValue: "Secret Keys", comment: "Filter to show secret keys only")
        case .public: return String(localized: "keyring.filter.public", defaultValue: "Public Keys", comment: "Filter to show public keys only")
        case .expired: return String(localized: "keyring.filter.expired", defaultValue: "Expired", comment: "Filter to show expired keys only")
        case .revoked: return String(localized: "keyring.filter.revoked", defaultValue: "Revoked", comment: "Filter to show revoked keys only")
        }
    }
}
