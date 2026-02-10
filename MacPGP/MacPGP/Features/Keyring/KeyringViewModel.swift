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
    case name = "Name"
    case date = "Date"
    case keyID = "Key ID"

    var id: String { rawValue }
}

enum KeyFilterType: String, CaseIterable, Identifiable {
    case all = "All Keys"
    case secret = "Secret Keys"
    case `public` = "Public Keys"
    case expired = "Expired"
    case revoked = "Revoked"

    var id: String { rawValue }
}
