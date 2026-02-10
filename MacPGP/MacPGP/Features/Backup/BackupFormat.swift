import Foundation
import CryptoKit

enum BackupVersion: String, Codable {
    case v1 = "1.0"
}

enum BackupEncryptionType: String, Codable {
    case none = "none"
    case aes256 = "aes256"
}

struct BackupFormat: Codable, Identifiable {
    let id: UUID
    let version: BackupVersion
    let createdDate: Date
    let createdBy: String
    let keyFingerprints: [String]
    let encryptionType: BackupEncryptionType
    let checksum: String?
    let metadata: BackupMetadata

    init(
        version: BackupVersion = .v1,
        keyFingerprints: [String],
        encryptionType: BackupEncryptionType,
        createdBy: String,
        metadata: BackupMetadata = BackupMetadata()
    ) {
        self.id = UUID()
        self.version = version
        self.createdDate = Date()
        self.createdBy = createdBy
        self.keyFingerprints = keyFingerprints
        self.encryptionType = encryptionType
        self.checksum = nil
        self.metadata = metadata
    }

    var isEncrypted: Bool {
        encryptionType != .none
    }

    var keyCount: Int {
        keyFingerprints.count
    }

    var formattedCreatedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdDate)
    }

    var displayDescription: String {
        let keyText = keyCount == 1 ? "key" : "keys"
        let encryptionText = isEncrypted ? "Encrypted" : "Unencrypted"
        return "\(encryptionText) backup of \(keyCount) \(keyText)"
    }

    func withChecksum(_ checksum: String) -> BackupFormat {
        var copy = self
        return BackupFormat(
            id: copy.id,
            version: copy.version,
            createdDate: copy.createdDate,
            createdBy: copy.createdBy,
            keyFingerprints: copy.keyFingerprints,
            encryptionType: copy.encryptionType,
            checksum: checksum,
            metadata: copy.metadata
        )
    }

    private init(
        id: UUID,
        version: BackupVersion,
        createdDate: Date,
        createdBy: String,
        keyFingerprints: [String],
        encryptionType: BackupEncryptionType,
        checksum: String?,
        metadata: BackupMetadata
    ) {
        self.id = id
        self.version = version
        self.createdDate = createdDate
        self.createdBy = createdBy
        self.keyFingerprints = keyFingerprints
        self.encryptionType = encryptionType
        self.checksum = checksum
        self.metadata = metadata
    }
}

struct BackupMetadata: Codable {
    let name: String?
    let description: String?
    let deviceName: String

    init(
        name: String? = nil,
        description: String? = nil,
        deviceName: String? = nil
    ) {
        self.name = name
        self.description = description
        self.deviceName = deviceName ?? Host.current().localizedName ?? "Unknown Device"
    }
}

extension BackupFormat {
    static var preview: BackupFormat {
        BackupFormat(
            keyFingerprints: [
                "ABCD1234EFGH5678IJKL9012MNOP3456",
                "QRST7890UVWX1234YZAB5678CDEF9012"
            ],
            encryptionType: .aes256,
            createdBy: "preview@example.com",
            metadata: BackupMetadata(
                name: "My Keys Backup",
                description: "Backup of my primary PGP keys",
                deviceName: "MacBook Pro"
            )
        )
    }
}
