import Foundation
import RNPKit

@Observable
final class KeyringService {
    private(set) var keys: [PGPKeyModel] = []
    private(set) var isLoading = false
    private(set) var lastError: OperationError?

    private let persistence: any KeyringPersisting
    private let autoSaveProvider: () -> Bool
    private var rawKeys: [Key] = []

    init(
        persistence: any KeyringPersisting = KeyringPersistence(),
        autoSave: @escaping () -> Bool = { PreferencesManager.shared.autoSaveKeyring }
    ) {
        self.persistence = persistence
        self.autoSaveProvider = autoSave
        loadKeys()
    }

    func loadKeys() {
        isLoading = true
        lastError = nil

        do {
            rawKeys = try persistence.loadKeys()
            if persistence.shouldSyncSharedContainer {
                syncLoadedKeysToSharedContainer()
            }
            reloadKeysWithVerificationStatus()
        } catch {
            lastError = .persistenceError(underlying: error)
            keys = []
        }

        isLoading = false
    }

    func saveKeys() throws {
        try persistence.saveKeys(rawKeys)
    }

    /// Commits a proposed raw-key set transactionally (issue #144): when
    /// auto-save is on, the proposed set is persisted as one atomic generation
    /// *before* it becomes the published in-memory state, so a persistence failure
    /// throws and leaves `rawKeys` (and the UI) at the previous committed state.
    /// When auto-save is off, the proposed set becomes the in-memory working copy
    /// and is persisted later by an explicit `saveKeys()`.
    private func commit(_ proposed: [Key]) throws {
        if autoSaveProvider() {
            try persistence.saveKeys(proposed)
        }
        rawKeys = proposed
        reloadKeysWithVerificationStatus()
    }

    private func merge(_ key: Key, into keys: inout [Key]) {
        if let existingIndex = keys.firstIndex(where: { $0.fingerprint == key.fingerprint }) {
            // Never downgrade an existing secret key to a public-only import.
            if key.isSecret && !keys[existingIndex].isSecret {
                keys[existingIndex] = key
            }
        } else {
            keys.append(key)
        }
    }

    func addKey(_ key: Key) throws {
        var proposed = rawKeys
        merge(key, into: &proposed)
        try commit(proposed)
    }

    func replaceKey(_ key: Key) throws {
        var proposed = rawKeys
        if let existingIndex = proposed.firstIndex(where: { $0.fingerprint == key.fingerprint }) {
            let existingKey = proposed[existingIndex]
            if existingKey.isSecret && !key.isSecret {
                proposed[existingIndex] = existingKey
            } else {
                proposed[existingIndex] = key
            }
        } else {
            proposed.append(key)
        }
        try commit(proposed)
    }

    /// Adds several keys as a single all-or-nothing transaction: either every key
    /// is committed together or none are (issue #144). Returns the models for the
    /// imported fingerprints.
    private func addKeys(_ newKeys: [Key]) throws -> [PGPKeyModel] {
        var proposed = rawKeys
        for key in newKeys {
            merge(key, into: &proposed)
        }
        try commit(proposed)

        let importedFingerprints = Set(newKeys.map(\.fingerprint))
        return keys.filter { importedFingerprints.contains($0.fingerprint) }
    }

    // Import is all-or-nothing: every key in the source commits as one
    // transaction, or the keyring is left untouched (issue #144).
    func importKey(from url: URL) throws -> [PGPKeyModel] {
        try addKeys(persistence.importKey(from: url))
    }

    func importKey(from data: Data) throws -> [PGPKeyModel] {
        try addKeys(persistence.importKey(from: data))
    }

    func importKey(fromArmored string: String) throws -> [PGPKeyModel] {
        try addKeys(persistence.importKey(fromArmored: string))
    }

    func exportKey(_ keyModel: PGPKeyModel, includeSecretKey: Bool = false, armored: Bool = true) throws -> Data {
        guard let key = rawKey(for: keyModel) else {
            throw OperationError.keyNotFound(keyID: keyModel.shortKeyID)
        }

        if includeSecretKey && key.isSecret {
            return try persistence.exportKey(key, armored: armored)
        } else {
            return try persistence.exportPublicKey(key, armored: armored)
        }
    }

    func deleteKey(_ keyModel: PGPKeyModel) throws {
        // The keyring deletion is authoritative and is committed first (issue
        // #144): only if the proposed key removal persists do we touch the
        // auxiliary metadata / Keychain state, so a persistence failure can never
        // strip metadata or the passphrase while leaving the key on disk.
        var proposed = rawKeys
        proposed.removeAll { $0.fingerprint == keyModel.fingerprint }
        try commit(proposed)

        // Auxiliary cleanup AFTER the authoritative commit. The key is already
        // gone from the committed keyring, so a cleanup failure is reported and
        // retryable rather than corrupting keyring state. Metadata is keyed by
        // fingerprint and harmlessly ignores a stale entry until retried.
        try? persistence.removeVerificationStatus(forFingerprint: keyModel.fingerprint)
        try? persistence.removeTrustLevel(forFingerprint: keyModel.fingerprint)

        do {
            try KeychainManager.shared.deletePassphrase(for: keyModel)
        } catch {
            NSLog("[KeyringService] Passphrase cleanup after deleting \(keyModel.shortKeyID) failed: \(error.localizedDescription)")
            lastError = .persistenceError(underlying: error)
        }
    }

    func key(withFingerprint fingerprint: String) -> PGPKeyModel? {
        keys.first { $0.fingerprint == fingerprint }
    }

    func key(withShortID shortID: String) -> PGPKeyModel? {
        keys.first { $0.shortKeyID.hasSuffix(shortID) || shortID.hasSuffix($0.shortKeyID) }
    }

    func rawKey(for model: PGPKeyModel) -> Key? {
        rawKeys.first { $0.fingerprint == model.fingerprint }
    }

    func secretKeys() -> [PGPKeyModel] {
        keys.filter { $0.isSecretKey }
    }

    func publicKeys(asOf now: Date = Date()) -> [PGPKeyModel] {
        keys.filter { $0.isUsableForEncryption(asOf: now) }
    }

    func validKeysForEncryption(asOf now: Date = Date()) -> [PGPKeyModel] {
        keys.filter { $0.isUsableForEncryption(asOf: now) }
    }

    func signingKeys(asOf now: Date = Date()) -> [PGPKeyModel] {
        keys.filter { $0.isUsableForSigning(asOf: now) }
    }

    /// Re-publishes the in-memory key list so SwiftUI views re-evaluate
    /// time-dependent validity (expiration) after the wall clock advances past a
    /// boundary, the system clock changes, or the app reactivates. The models are
    /// unchanged; republishing only triggers `@Observable` invalidation so derived
    /// filters and banners recompute against the current time.
    func refreshKeyValidity() {
        guard !isLoading else { return }
        reloadKeysWithVerificationStatus()
    }

    func search(_ query: String) -> [PGPKeyModel] {
        guard !query.isEmpty else { return keys }

        let lowercasedQuery = query.lowercased()
        return keys.filter { key in
            key.displayName.lowercased().contains(lowercasedQuery) ||
            key.email?.lowercased().contains(lowercasedQuery) == true ||
            key.shortKeyID.lowercased().contains(lowercasedQuery) ||
            key.fingerprint.lowercased().contains(lowercasedQuery)
        }
    }

    // MARK: - Verification Status

    func markKeyAsVerified(_ keyModel: PGPKeyModel, method: FingerprintVerificationMethod) throws {
        try persistence.updateVerificationStatus(
            forFingerprint: keyModel.fingerprint,
            isVerified: true,
            verificationDate: Date(),
            verificationMethod: method.rawValue
        )

        reloadKeysWithVerificationStatus()
    }

    func clearVerificationStatus(_ keyModel: PGPKeyModel) throws {
        try persistence.removeVerificationStatus(forFingerprint: keyModel.fingerprint)
        reloadKeysWithVerificationStatus()
    }

    // MARK: - Trust Level

    func updateTrustLevel(_ keyModel: PGPKeyModel, trustLevel: TrustLevel, notes: String? = nil) throws {
        try persistence.updateTrustLevel(
            forFingerprint: keyModel.fingerprint,
            trustLevel: trustLevel,
            notes: notes
        )
        updateKeyInPlace(fingerprint: keyModel.fingerprint, trustLevel: trustLevel)
    }

    func clearTrustLevel(_ keyModel: PGPKeyModel) throws {
        try persistence.removeTrustLevel(forFingerprint: keyModel.fingerprint)
        updateKeyInPlace(fingerprint: keyModel.fingerprint, trustLevel: .unknown)
    }

    private func updateKeyInPlace(fingerprint: String, trustLevel: TrustLevel) {
        if let index = keys.firstIndex(where: { $0.fingerprint == fingerprint }) {
            keys[index] = PGPKeyModel(copying: keys[index], trustLevel: trustLevel)
        } else {
            reloadKeysWithVerificationStatus()
        }
    }

    private func reloadKeysWithVerificationStatus() {
        let metadata = persistence.loadMetadata()

        keys = rawKeys.map { key in
            let fingerprint = key.fingerprint

            // Load verification status
            let verification = metadata.verifications[fingerprint]
            let isVerified = verification?.isVerified ?? false
            let verificationDate = verification?.verificationDate
            let verificationMethod = verification?.verificationMethod.flatMap {
                FingerprintVerificationMethod(rawValue: $0)
            }

            // Load trust level
            let trustLevel = metadata.trusts[fingerprint]?.trustLevel ?? .unknown

            return PGPKeyModel(
                from: key,
                isVerified: isVerified,
                verificationDate: verificationDate,
                verificationMethod: verificationMethod,
                trustLevel: trustLevel
            )
        }
    }

    private func syncLoadedKeysToSharedContainer() {
        guard persistence.shouldSyncSharedContainer else { return }

        do {
            try SharedContainerSync.syncKeysToContainer(keys: rawKeys)
        } catch {
            NSLog("[KeyringService] Failed to sync loaded keys to shared container: \(error.localizedDescription)")
        }
    }
}
