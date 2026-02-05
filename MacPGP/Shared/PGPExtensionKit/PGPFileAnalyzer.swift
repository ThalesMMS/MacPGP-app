import Foundation
import ObjectivePGP

/// Analyzes PGP files to determine encryption status and file type without performing decryption
final class PGPFileAnalyzer {

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
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OperationError.fileAccessError(path: url.path)
        }

        let data = try Data(contentsOf: url)
        return try analyze(data: data, fileURL: url)
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

    /// Detects whether the file is ASCII armored or binary
    /// - Parameters:
    ///   - data: The file data
    ///   - url: Optional file URL for extension-based detection
    /// - Returns: The detected encoding format
    private func detectEncodingFormat(data: Data, url: URL?) -> EncodingFormat {
        // Check file extension first
        if let url = url {
            let ext = url.pathExtension.lowercased()
            if ext == "asc" {
                return .asciiArmored
            } else if ext == "gpg" || ext == "pgp" {
                // .gpg and .pgp are typically binary, but could be armored
                // Check content to be sure
            }
        }

        // Check if data starts with ASCII armor header
        if let prefix = String(data: data.prefix(50), encoding: .utf8) {
            if prefix.contains("-----BEGIN PGP") {
                return .asciiArmored
            }
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
        do {
            // Try to parse as encrypted message
            let parsedData = try ObjectivePGP.decrypt(data, andVerifySignature: false, using: [])
            // If we got here without a key error, it's likely encrypted
            // (will fail with missing key error)
            return .encrypted
        } catch {
            // Check error to determine file type
            let nsError = error as NSError

            // If it's a key-related error, the file is likely encrypted
            if nsError.domain == "ObjectivePGP" {
                // Try to detect if it's a key file
                if encodingFormat == .asciiArmored {
                    if let content = String(data: data, encoding: .utf8) {
                        if content.contains("-----BEGIN PGP PUBLIC KEY BLOCK-----") {
                            return .publicKey
                        } else if content.contains("-----BEGIN PGP PRIVATE KEY BLOCK-----") {
                            return .privateKey
                        } else if content.contains("-----BEGIN PGP SIGNATURE-----") {
                            return .signed
                        } else if content.contains("-----BEGIN PGP MESSAGE-----") {
                            return .encrypted
                        }
                    }
                }

                // For binary format, check packet types
                if data.count >= 2 {
                    let firstByte = data[0]
                    let packetTag = (firstByte & 0x3F) >> 2

                    switch packetTag {
                    case 6: // Public key packet
                        return .publicKey
                    case 5: // Secret key packet
                        return .privateKey
                    case 2: // Signature packet
                        return .signed
                    case 1, 18: // Encrypted data packets
                        return .encrypted
                    default:
                        break
                    }
                }
            }
        }

        return .unknown
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
    /// - Returns: True if the extension is .gpg, .pgp, or .asc
    static func isPGPFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "gpg" || ext == "pgp" || ext == "asc"
    }
}
