import Foundation
import RNPKit

/// Analyzes PGP files to determine encryption status and file type without performing decryption
final class PGPFileAnalyzer {
    private static let defaultHeaderByteLimit = 4096

    /// Represents the type of PGP file
    enum FileType {
        case encrypted
        case signed
        case encryptedAndSigned
        case publicKey
        case privateKey
        case unknown

        var description: String {
            switch self {
            case .encrypted:
                return "Encrypted"
            case .signed:
                return "Signed"
            case .encryptedAndSigned:
                return "Encrypted & Signed"
            case .publicKey:
                return "Public Key"
            case .privateKey:
                return "Private Key"
            case .unknown:
                return "Unknown"
            }
        }
    }

    /// Represents the encoding format of the PGP file
    enum EncodingFormat {
        case binary
        case asciiArmored
        case unknown

        var description: String {
            switch self {
            case .binary:
                return "Binary"
            case .asciiArmored:
                return "ASCII Armored"
            case .unknown:
                return "Unknown"
            }
        }
    }

    /// Result of file analysis
    struct AnalysisResult {
        let fileType: FileType
        let encodingFormat: EncodingFormat
        let isEncrypted: Bool
        let isSigned: Bool
        let fileSize: Int64
    }

    /// Analyzes a PGP file at the given URL
    /// - Parameter url: The URL of the file to analyze
    /// - Returns: Analysis result containing file type and encryption status
    /// - Throws: Error if file cannot be read or analyzed
    func analyze(fileAt url: URL) throws -> AnalysisResult {
        let data: Data
        do {
            data = try SecureScopedFileAccess.readData(from: url)
        } catch let error as OperationError {
            throw error
        } catch {
            throw OperationError.fileAccessError(path: url.path)
        }

        return try analyze(data: data, fileURL: url)
    }

    /// Analyzes only a bounded prefix of a PGP file for extension metadata.
    /// - Parameters:
    ///   - url: The URL of the file to analyze
    ///   - maxBytes: Maximum number of bytes to read from the start of the file
    /// - Returns: Analysis result based on the file header and the actual file size
    /// - Throws: Error if the header cannot be read
    func analyzeHeader(
        fileAt url: URL,
        maxBytes: Int = PGPFileAnalyzer.defaultHeaderByteLimit
    ) throws -> AnalysisResult {
        let data: Data
        let fileSize: Int64
        do {
            data = try SecureScopedFileAccess.readPrefix(from: url, maxBytes: maxBytes)
            fileSize = try SecureScopedFileAccess.fileSize(of: url)
        } catch let error as OperationError {
            throw error
        } catch {
            throw OperationError.fileAccessError(path: url.path)
        }

        return analyzeHeader(data: data, fileURL: url, fileSize: fileSize)
    }

    /// Analyzes PGP data
    /// - Parameters:
    ///   - data: The PGP data to analyze
    ///   - fileURL: Optional file URL for additional context
    /// - Returns: Analysis result containing file type and encryption status
    /// - Throws: Error if data cannot be analyzed
    func analyze(data: Data, fileURL: URL? = nil) throws -> AnalysisResult {
        let encodingFormat = detectEncodingFormat(data: data, url: fileURL)
        let fileType = try detectFileType(data: data, encodingFormat: encodingFormat)

        let isEncrypted = fileType == .encrypted || fileType == .encryptedAndSigned
        let isSigned = fileType == .signed || fileType == .encryptedAndSigned

        return AnalysisResult(
            fileType: fileType,
            encodingFormat: encodingFormat,
            isEncrypted: isEncrypted,
            isSigned: isSigned,
            fileSize: Int64(data.count)
        )
    }

    /// Checks if a PGP file header indicates encryption without reading the full file.
    /// - Parameter url: The URL to check
    /// - Returns: True if the bounded header indicates an encrypted PGP file, false otherwise
    func isEncryptedHeader(fileAt url: URL) -> Bool {
        guard let result = try? analyzeHeader(fileAt: url) else {
            return false
        }
        return result.isEncrypted
    }

    /// Detects whether the file is ASCII armored or binary
    /// - Parameters:
    ///   - data: The file data
    ///   - url: Optional file URL for extension-based detection
    /// - Returns: The detected encoding format
    private func detectEncodingFormat(data: Data, url: URL?) -> EncodingFormat {
        // Check file extension first
        if let url = url {
            let ext = url.pathExtension.lowercased()
            if ext == PGPFileExtensions.asciiArmored {
                return .asciiArmored
            } else if PGPFileExtensions.isPGPFileExtension(ext) {
                // .gpg and .pgp are typically binary, but could be armored
                // Check content to be sure
            }
        }

        // Check if data starts with ASCII armor header
        if let prefix = String(data: data.prefix(128), encoding: .utf8),
           PGPArmorDetector.detectedBlock(in: prefix) != nil {
            return .asciiArmored
        }

        // Check for binary PGP marker
        if data.count >= 2 {
            let bytes = [UInt8](data.prefix(2))
            // OpenPGP binary format starts with specific packet tags
            // Common packet tags: 0x85 (public key), 0x95 (secret key), 0x84 (signature), 0xC1 (encrypted)
            if bytes[0] & 0x80 != 0 {
                return .binary
            }
        }

        return .unknown
    }

    /// Detects the type of PGP file
    /// - Parameters:
    ///   - data: The file data
    ///   - encodingFormat: The encoding format (ASCII or binary)
    /// - Returns: The detected file type
    /// - Throws: Error if file type cannot be determined
    private func detectFileType(data: Data, encodingFormat: EncodingFormat) throws -> FileType {
        if encodingFormat == .asciiArmored,
           let content = String(data: data, encoding: .utf8) {
            switch PGPArmorDetector.detectedBlock(in: content) {
            case .publicKey:
                return .publicKey
            case .privateKey:
                return .privateKey
            case .signedMessage, .signature:
                return .signed
            case .message:
                let inspection = try RNP.inspect(data)
                if inspection.isEncrypted && inspection.isSigned {
                    return .encryptedAndSigned
                }
                return inspection.isEncrypted ? .encrypted : .unknown
            case nil:
                break
            }
        }

        if let keys = try? RNP.readKeys(from: data), !keys.isEmpty {
            return keys.contains(where: \.isSecret) ? .privateKey : .publicKey
        }

        let inspection = try RNP.inspect(data)
        if inspection.isEncrypted && inspection.isSigned {
            return .encryptedAndSigned
        }
        if inspection.isEncrypted {
            return .encrypted
        }
        if inspection.isSigned {
            return .signed
        }

        return .unknown
    }

    private func analyzeHeader(data: Data, fileURL: URL?, fileSize: Int64) -> AnalysisResult {
        let encodingFormat = detectEncodingFormat(data: data, url: fileURL)
        let fileType = detectHeaderFileType(data: data, encodingFormat: encodingFormat)
        let isEncrypted = fileType == .encrypted || fileType == .encryptedAndSigned
        let isSigned = fileType == .signed || fileType == .encryptedAndSigned

        return AnalysisResult(
            fileType: fileType,
            encodingFormat: encodingFormat,
            isEncrypted: isEncrypted,
            isSigned: isSigned,
            fileSize: fileSize
        )
    }

    private func detectHeaderFileType(data: Data, encodingFormat: EncodingFormat) -> FileType {
        if encodingFormat == .asciiArmored,
           let content = String(data: data, encoding: .utf8),
           let block = PGPArmorDetector.detectedBlock(in: content) {
            switch block {
            case .publicKey:
                return .publicKey
            case .privateKey:
                return .privateKey
            case .signedMessage, .signature:
                return .signed
            case .message:
                return .encrypted
            }
        }

        guard encodingFormat == .binary,
              let packetTag = firstPacketTag(in: data) else {
            return .unknown
        }

        switch packetTag {
        case 1, 3, 9, 18, 20:
            return .encrypted
        case 2, 4:
            return .signed
        case 5, 7:
            return .privateKey
        case 6, 14:
            return .publicKey
        default:
            return .unknown
        }
    }

    private func firstPacketTag(in data: Data) -> UInt8? {
        guard let header = data.first, header & 0x80 != 0 else {
            return nil
        }

        if header & 0x40 != 0 {
            return header & 0x3F
        }

        return (header & 0x3C) >> 2
    }

    /// Checks if a file at the given URL is a PGP encrypted file
    /// - Parameter url: The URL to check
    /// - Returns: True if the file is encrypted, false otherwise
    func isEncrypted(fileAt url: URL) -> Bool {
        guard let result = try? analyze(fileAt: url) else {
            return false
        }
        return result.isEncrypted
    }

    /// Checks if a file extension indicates a PGP file
    /// - Parameter url: The URL to check
    /// - Returns: True if the extension is a supported PGP extension
    static func isPGPFile(url: URL) -> Bool {
        PGPFileExtensions.isPGPFileExtension(url.pathExtension)
    }
}
