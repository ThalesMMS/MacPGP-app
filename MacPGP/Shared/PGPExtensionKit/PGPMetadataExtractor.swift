import Foundation
import RNPKit

/// Extracts metadata from PGP encrypted files without performing decryption
nonisolated final class PGPMetadataExtractor {

    /// Represents encryption algorithm information
    nonisolated struct EncryptionAlgorithm {
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
    nonisolated struct Metadata {
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
    /// Default bounded header read for file-based metadata extraction. OpenPGP
    /// encryption metadata (PKESK recipients, SEIPD integrity/version) lives at
    /// the very start of the message, so a generous header prefix is sufficient
    /// for the metadata Quick Look can show. Generous enough for hundreds of
    /// recipients without approaching whole-file reads on large inputs.
    static let defaultMetadataHeaderByteLimit = 512 * 1024

    func extractMetadata(from url: URL, maxHeaderBytes: Int = PGPMetadataExtractor.defaultMetadataHeaderByteLimit) throws -> Metadata {
        // Read a bounded header prefix rather than the whole file (issue #142):
        // Quick Look only needs header-derived metadata. For small files the
        // prefix IS the whole file; for large files we use header-only metadata
        // and fall back to a full read only if the bounded header is insufficient
        // to identify the encrypted message, so correctness is never worse than
        // the previous whole-file behavior.
        let actualFileSize = (try? SecureScopedFileAccess.fileSize(of: url)) ?? 0

        let prefix: Data
        do {
            prefix = try SecureScopedFileAccess.readPrefix(from: url, maxBytes: maxHeaderBytes)
        } catch let error as OperationError {
            throw error
        } catch {
            throw OperationError.fileAccessError(path: url.path)
        }

        // Whole file already in hand (file no larger than the prefix).
        if Int64(prefix.count) >= actualFileSize {
            return try extractMetadata(from: prefix, fileURL: url)
        }

        // Large file: prefer header-only metadata; only fall back to a full read
        // if the bounded header cannot be parsed as an encrypted message.
        if let metadata = try? extractMetadata(from: prefix, fileURL: url, fileSizeOverride: actualFileSize) {
            return metadata
        }

        let data: Data
        do {
            data = try SecureScopedFileAccess.readData(from: url)
        } catch let error as OperationError {
            throw error
        } catch {
            throw OperationError.fileAccessError(path: url.path)
        }
        return try extractMetadata(from: data, fileURL: url)
    }

    /// Extracts metadata from PGP encrypted data
    /// - Parameters:
    ///   - data: The encrypted data (may be a bounded header prefix for large files)
    ///   - fileURL: Optional file URL for additional context
    ///   - fileSizeOverride: Real file size to report when `data` is only a header
    ///     prefix; defaults to `data.count` for whole-buffer callers.
    /// - Returns: Metadata extracted from the data
    /// - Throws: Error if data is not encrypted or cannot be parsed
    func extractMetadata(from data: Data, fileURL: URL? = nil, fileSizeOverride: Int64? = nil) throws -> Metadata {
        let inspection = try RNP.inspect(data)
        guard inspection.isEncrypted else {
            throw OperationError.decryptionFailed(underlying: nil)
        }
        let recipientKeyIDs = inspection.recipientKeyIDs
        let encryptionAlgorithm = extractEncryptionAlgorithm(from: inspection)
        let compressionAlgorithm = extractCompressionAlgorithm(from: inspection)
        let isIntegrityProtected = checkIntegrityProtection(in: inspection)
        let creationDate = inspection.literalMTime ?? extractCreationDate(from: fileURL)
        let filename = inspection.literalFilename

        return Metadata(
            recipientKeyIDs: recipientKeyIDs,
            encryptionAlgorithm: encryptionAlgorithm,
            compressionAlgorithm: compressionAlgorithm,
            isIntegrityProtected: isIntegrityProtected,
            creationDate: creationDate,
            filename: filename,
            fileSize: fileSizeOverride ?? Int64(data.count)
        )
    }

    /// Extracts encryption algorithm information
    /// - Parameter inspection: Metadata returned by the OpenPGP inspection pass
    /// - Returns: Encryption algorithm information if available
    private func extractEncryptionAlgorithm(from inspection: MessageInspection) -> EncryptionAlgorithm? {
        guard let cipher = inspection.protection?.cipher else {
            return nil
        }
        return EncryptionAlgorithm(name: cipher, keySize: nil)
    }

    /// Extracts compression algorithm name
    /// - Parameter inspection: Metadata returned by the OpenPGP inspection pass
    /// - Returns: Compression algorithm name if available
    private func extractCompressionAlgorithm(from inspection: MessageInspection) -> String? {
        _ = inspection
        return nil
    }

    /// Checks if the encrypted data has integrity protection (MDC)
    /// - Parameter inspection: Metadata returned by the OpenPGP inspection pass
    /// - Returns: True if integrity protected, false otherwise
    private func checkIntegrityProtection(in inspection: MessageInspection) -> Bool {
        guard let mode = inspection.protection?.mode else {
            return false
        }

        let normalizedMode = mode.uppercased()
        return normalizedMode.contains("MDC") || normalizedMode.contains("AEAD")
    }

    /// Extracts creation date from file metadata or encrypted data
    /// - Parameter fileURL: Optional file URL to get creation date from filesystem
    /// - Returns: Creation date if available
    private func extractCreationDate(from fileURL: URL?) -> Date? {
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
