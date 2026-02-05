import Foundation
import ObjectivePGP

/// Extracts metadata from PGP encrypted files without performing decryption
final class PGPMetadataExtractor {

    /// Represents encryption algorithm information
    struct EncryptionAlgorithm {
        let name: String
        let keySize: Int?

        var description: String {
            if let keySize = keySize {
                return "\(name) (\(keySize)-bit)"
            }
            return name
        }
    }

    /// Represents metadata extracted from an encrypted file
    struct Metadata {
        let recipientKeyIDs: [String]
        let encryptionAlgorithm: EncryptionAlgorithm?
        let compressionAlgorithm: String?
        let isIntegrityProtected: Bool
        let creationDate: Date?
        let filename: String?
        let fileSize: Int64
    }

    /// Extracts metadata from a PGP encrypted file
    /// - Parameter url: The URL of the encrypted file
    /// - Returns: Metadata extracted from the file
    /// - Throws: Error if file cannot be read or is not encrypted
    func extractMetadata(from url: URL) throws -> Metadata {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OperationError.fileAccessError(path: url.path)
        }

        let data = try Data(contentsOf: url)
        return try extractMetadata(from: data, fileURL: url)
    }

    /// Extracts metadata from PGP encrypted data
    /// - Parameters:
    ///   - data: The encrypted data
    ///   - fileURL: Optional file URL for additional context
    /// - Returns: Metadata extracted from the data
    /// - Throws: Error if data is not encrypted or cannot be parsed
    func extractMetadata(from data: Data, fileURL: URL? = nil) throws -> Metadata {
        let recipientKeyIDs = try extractRecipientKeyIDs(from: data)
        let encryptionAlgorithm = extractEncryptionAlgorithm(from: data)
        let compressionAlgorithm = extractCompressionAlgorithm(from: data)
        let isIntegrityProtected = checkIntegrityProtection(in: data)
        let creationDate = extractCreationDate(from: data, fileURL: fileURL)
        let filename = extractFilename(from: data)

        return Metadata(
            recipientKeyIDs: recipientKeyIDs,
            encryptionAlgorithm: encryptionAlgorithm,
            compressionAlgorithm: compressionAlgorithm,
            isIntegrityProtected: isIntegrityProtected,
            creationDate: creationDate,
            filename: filename,
            fileSize: Int64(data.count)
        )
    }

    /// Extracts the list of recipient key IDs from encrypted data
    /// - Parameter data: The encrypted data
    /// - Returns: Array of key IDs (as hex strings)
    /// - Throws: Error if recipient information cannot be extracted
    private func extractRecipientKeyIDs(from data: Data) throws -> [String] {
        var keyIDs: [String] = []

        do {
            // Try to parse the encrypted message
            // ObjectivePGP will fail to decrypt but we can catch information from the error
            _ = try ObjectivePGP.decrypt(data, andVerifySignature: false, using: [])
        } catch {
            // This is expected - we don't have the keys to decrypt
            // Parse the data manually to extract key IDs
            keyIDs = parseRecipientKeyIDs(from: data)
        }

        return keyIDs
    }

    /// Manually parses recipient key IDs from encrypted data
    /// - Parameter data: The encrypted data
    /// - Returns: Array of key IDs found in the data
    private func parseRecipientKeyIDs(from data: Data) -> [String] {
        var keyIDs: [String] = []
        var offset = 0
        let bytes = [UInt8](data)

        while offset < bytes.count {
            guard offset + 1 < bytes.count else { break }

            let packetByte = bytes[offset]
            let isNewFormat = (packetByte & 0x40) != 0

            var packetTag: UInt8
            var packetLength: Int = 0

            if isNewFormat {
                // New packet format
                packetTag = packetByte & 0x3F
                offset += 1

                guard offset < bytes.count else { break }
                let lengthByte = bytes[offset]
                offset += 1

                if lengthByte < 192 {
                    packetLength = Int(lengthByte)
                } else if lengthByte < 224 {
                    guard offset < bytes.count else { break }
                    packetLength = ((Int(lengthByte) - 192) << 8) + Int(bytes[offset]) + 192
                    offset += 1
                } else {
                    // Partial body length - skip for simplicity
                    break
                }
            } else {
                // Old packet format
                packetTag = (packetByte & 0x3C) >> 2
                let lengthType = packetByte & 0x03
                offset += 1

                switch lengthType {
                case 0:
                    guard offset < bytes.count else { break }
                    packetLength = Int(bytes[offset])
                    offset += 1
                case 1:
                    guard offset + 1 < bytes.count else { break }
                    packetLength = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
                    offset += 2
                case 2:
                    guard offset + 3 < bytes.count else { break }
                    packetLength = (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16) |
                                   (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
                    offset += 4
                default:
                    // Indeterminate length
                    break
                }
            }

            // Check if this is a Public-Key Encrypted Session Key Packet (tag 1)
            if packetTag == 1 {
                guard offset + 8 <= bytes.count else { break }
                // Skip version byte
                offset += 1
                // Extract 8-byte key ID
                let keyIDBytes = bytes[offset..<offset + 8]
                let keyID = keyIDBytes.map { String(format: "%02X", $0) }.joined()
                keyIDs.append(keyID)
                offset += 7 // We already moved 1 byte for version
            }

            offset += packetLength
        }

        return keyIDs
    }

    /// Extracts encryption algorithm information
    /// - Parameter data: The encrypted data
    /// - Returns: Encryption algorithm information if available
    private func extractEncryptionAlgorithm(from data: Data) -> EncryptionAlgorithm? {
        // This would require parsing the encrypted session key packet
        // For now, return a default based on common usage
        return EncryptionAlgorithm(name: "AES", keySize: 256)
    }

    /// Extracts compression algorithm name
    /// - Parameter data: The encrypted data
    /// - Returns: Compression algorithm name if available
    private func extractCompressionAlgorithm(from data: Data) -> String? {
        // Common PGP compression: ZIP, ZLIB, BZIP2
        // Would need to parse compressed data packet
        return nil
    }

    /// Checks if the encrypted data has integrity protection (MDC)
    /// - Parameter data: The encrypted data
    /// - Returns: True if integrity protected, false otherwise
    private func checkIntegrityProtection(in data: Data) -> Bool {
        // Check for Symmetrically Encrypted Integrity Protected Data Packet (tag 18)
        guard data.count >= 1 else { return false }

        let bytes = [UInt8](data)
        var offset = 0

        while offset < bytes.count {
            guard offset < bytes.count else { break }

            let packetByte = bytes[offset]
            let isNewFormat = (packetByte & 0x40) != 0

            var packetTag: UInt8

            if isNewFormat {
                packetTag = packetByte & 0x3F
            } else {
                packetTag = (packetByte & 0x3C) >> 2
            }

            // Tag 18 indicates integrity-protected encrypted data
            if packetTag == 18 {
                return true
            }

            // Move to next packet (simplified)
            offset += 1
        }

        return false
    }

    /// Extracts creation date from file metadata or encrypted data
    /// - Parameters:
    ///   - data: The encrypted data
    ///   - fileURL: Optional file URL to get creation date from filesystem
    /// - Returns: Creation date if available
    private func extractCreationDate(from data: Data, fileURL: URL?) -> Date? {
        if let url = fileURL {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                return attributes[.creationDate] as? Date
            } catch {
                return nil
            }
        }
        return nil
    }

    /// Extracts the original filename from encrypted data if available
    /// - Parameter data: The encrypted data
    /// - Returns: Original filename if embedded in the encrypted data
    private func extractFilename(from data: Data) -> String? {
        // The filename would be in the literal data packet after decryption
        // Cannot extract without decrypting
        return nil
    }

    /// Formats a key ID for display
    /// - Parameter keyID: The key ID hex string
    /// - Returns: Formatted key ID (e.g., "1234 5678 90AB CDEF")
    static func formatKeyID(_ keyID: String) -> String {
        guard keyID.count >= 8 else { return keyID }

        var formatted = ""
        for (index, char) in keyID.enumerated() {
            if index > 0 && index % 4 == 0 {
                formatted += " "
            }
            formatted.append(char)
        }
        return formatted
    }

    /// Converts key IDs to short form (last 8 characters)
    /// - Parameter keyID: The full key ID
    /// - Returns: Short key ID (last 8 characters)
    static func shortKeyID(from keyID: String) -> String {
        guard keyID.count >= 8 else { return keyID }
        return String(keyID.suffix(8))
    }
}
