import Foundation
import CryptoKit

/// Result of parsing/validating a backup payload off the MainActor.
nonisolated struct BackupParseResult: Sendable {
    let backup: BackupFormat
    let keyData: Data
    /// True when the backup omitted a checksum (older format); the caller decides
    /// whether to warn. A checksum *mismatch* throws instead of setting this.
    let checksumMissing: Bool
}

/// Pure, MainActor-free serialization/validation of the MacPGP backup payload.
/// Kept separate so the heavy work runs off the MainActor (see `BackupWorker`).
nonisolated enum BackupPayloadCodec {
    private static let beginMarker = "-----BEGIN MACPGP BACKUP-----\n"
    private static let metadataEndMarker = "\n-----END MACPGP BACKUP METADATA-----\n"
    private static let endMarker = "-----END MACPGP BACKUP-----\n"

    static func checksumHex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func makeBackupData(
        exportedData: Data,
        keyFingerprints: [String],
        useEncryption: Bool,
        name: String?,
        description: String?
    ) throws -> Data {
        let backupFormat = BackupFormat(
            keyFingerprints: keyFingerprints,
            encryptionType: useEncryption ? .aes256 : .none,
            createdBy: NSFullUserName(),
            metadata: BackupMetadata(name: name, description: description)
        )
        let backupWithChecksum = backupFormat.withChecksum(checksumHex(for: exportedData))

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let metadataJSON = try encoder.encode(backupWithChecksum)

        var combined = Data()
        combined.append(Data(beginMarker.utf8))
        combined.append(metadataJSON)
        combined.append(Data(metadataEndMarker.utf8))
        combined.append(exportedData)
        combined.append(Data(endMarker.utf8))
        return combined
    }

    static func parseMetadata(from data: Data) throws -> BackupFormat {
        guard let content = String(data: data, encoding: .utf8) else {
            throw OperationError.invalidKeyData
        }
        guard let metadataStart = content.range(of: beginMarker),
              let metadataEnd = content.range(of: metadataEndMarker) else {
            throw OperationError.invalidKeyData
        }
        let metadataString = String(content[metadataStart.upperBound..<metadataEnd.lowerBound])
        guard let metadataData = metadataString.data(using: .utf8) else {
            throw OperationError.invalidKeyData
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFormat.self, from: metadataData)
    }

    static func extractKeys(from data: Data) throws -> Data {
        guard let content = String(data: data, encoding: .utf8) else {
            throw OperationError.invalidKeyData
        }
        // Key data lies strictly between the metadata-end and backup-end markers;
        // this must match makeBackupData so the checksum (computed over the
        // exported key data alone) verifies.
        guard let keysStart = content.range(of: metadataEndMarker),
              let keysEnd = content.range(of: endMarker) else {
            throw OperationError.invalidKeyData
        }
        let keysString = String(content[keysStart.upperBound..<keysEnd.lowerBound])
        guard let keyData = keysString.data(using: .utf8) else {
            throw OperationError.invalidKeyData
        }
        return keyData
    }

    /// Outcome of checking a backup's embedded integrity checksum.
    enum ChecksumStatus {
        /// A checksum was present and matched the key data.
        case verified
        /// No checksum was present (e.g. a backup from an older MacPGP version);
        /// integrity could not be verified, but the backup is still usable.
        case absent
    }

    /// Validates the embedded checksum against the key data.
    /// - Throws: `OperationError` on checksum mismatch (corrupted/modified backup).
    /// - Returns: `.verified` when a checksum is present and matches, `.absent`
    ///   when the backup carries no checksum.
    static func checksumStatus(backup: BackupFormat, keyData: Data) throws -> ChecksumStatus {
        guard let expected = backup.checksum else { return .absent }
        guard checksumHex(for: keyData) == expected else {
            throw OperationError.unknownError(message: "Backup checksum mismatch. The backup contents may be corrupted or modified.")
        }
        return .verified
    }
}

/// Performs the CPU- and IO-heavy backup work (KDF/AES via
/// `EncryptedBackupEnvelope`, JSON serialization, parsing, and checksum) off the
/// MainActor. Injected into `BackupViewModel` so tests can substitute a
/// controllable worker.
nonisolated protocol BackupWorking: Sendable {
    func makePayload(
        exportedData: Data,
        keyFingerprints: [String],
        useEncryption: Bool,
        name: String?,
        description: String?,
        passphrase: String,
        createdAt: Date
    ) async throws -> Data

    func parse(data: Data, isEncrypted: Bool, passphrase: String) async throws -> BackupParseResult
}

nonisolated struct BackupWorker: BackupWorking {
    func makePayload(
        exportedData: Data,
        keyFingerprints: [String],
        useEncryption: Bool,
        name: String?,
        description: String?,
        passphrase: String,
        createdAt: Date
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let backupData = try BackupPayloadCodec.makeBackupData(
                exportedData: exportedData,
                keyFingerprints: keyFingerprints,
                useEncryption: useEncryption,
                name: name,
                description: description
            )
            guard useEncryption else { return backupData }
            return try EncryptedBackupEnvelope.seal(backupData, passphrase: passphrase, createdAt: createdAt)
        }.value
    }

    func parse(data: Data, isEncrypted: Bool, passphrase: String) async throws -> BackupParseResult {
        try await Task.detached(priority: .userInitiated) {
            let plaintext = isEncrypted
                ? try EncryptedBackupEnvelope.open(data, passphrase: passphrase)
                : data
            let backup = try BackupPayloadCodec.parseMetadata(from: plaintext)
            let keyData = try BackupPayloadCodec.extractKeys(from: plaintext)
            let checksumMissing = try BackupPayloadCodec.checksumStatus(backup: backup, keyData: keyData) == .absent
            return BackupParseResult(backup: backup, keyData: keyData, checksumMissing: checksumMissing)
        }.value
    }
}
