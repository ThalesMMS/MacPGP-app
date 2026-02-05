import Foundation
import AppKit

/// Handles communication between app extensions (FinderSync, QuickLook, Thumbnail) and the main application
/// This service processes file operations triggered from Finder context menus and other extension interfaces
final class ExtensionCommunicationService: NSObject {

    // MARK: - Notification Names

    /// Posted when files should be opened for encryption
    static let encryptFilesNotification = Notification.Name("com.macpgp.encryptFiles")

    /// Posted when files should be opened for decryption
    static let decryptFilesNotification = Notification.Name("com.macpgp.decryptFiles")

    /// UserInfo key for file URLs array
    static let fileURLsKey = "fileURLs"

    // MARK: - Properties

    private let fileAnalyzer = PGPFileAnalyzer()

    // MARK: - Initialization

    override init() {
        super.init()
        registerForEvents()
    }

    // MARK: - Registration

    /// Registers the service to handle file opening events
    private func registerForEvents() {
        // The main app will call handleOpenFiles when extensions trigger file operations
        NSLog("[ExtensionCommunicationService] Registered for file opening events")
    }

    // MARK: - File Handling

    /// Handles files opened from extensions or Finder
    /// Determines the appropriate operation (encrypt/decrypt) based on file type
    /// - Parameter urls: Array of file URLs to process
    func handleOpenFiles(_ urls: [URL]) {
        guard !urls.isEmpty else {
            NSLog("[ExtensionCommunicationService] No files to handle")
            return
        }

        NSLog("[ExtensionCommunicationService] Handling \(urls.count) file(s)")

        // Separate encrypted files from regular files
        let encryptedFiles = urls.filter { url in
            PGPFileAnalyzer.isPGPFile(url: url) && fileAnalyzer.isEncrypted(fileAt: url)
        }

        let regularFiles = urls.filter { url in
            !PGPFileAnalyzer.isPGPFile(url: url) || !fileAnalyzer.isEncrypted(fileAt: url)
        }

        // Handle decryption for encrypted files
        if !encryptedFiles.isEmpty {
            NSLog("[ExtensionCommunicationService] Triggering decrypt for \(encryptedFiles.count) encrypted file(s)")
            postDecryptNotification(for: encryptedFiles)
        }

        // Handle encryption for regular files
        if !regularFiles.isEmpty {
            NSLog("[ExtensionCommunicationService] Triggering encrypt for \(regularFiles.count) regular file(s)")
            postEncryptNotification(for: regularFiles)
        }
    }

    // MARK: - Notification Posting

    /// Posts notification to trigger encryption workflow
    /// - Parameter urls: Files to encrypt
    private func postEncryptNotification(for urls: [URL]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.encryptFilesNotification,
                object: nil,
                userInfo: [Self.fileURLsKey: urls]
            )
        }
    }

    /// Posts notification to trigger decryption workflow
    /// - Parameter urls: Files to decrypt
    private func postDecryptNotification(for urls: [URL]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.decryptFilesNotification,
                object: nil,
                userInfo: [Self.fileURLsKey: urls]
            )
        }
    }
}

// MARK: - Document Type Handling

extension ExtensionCommunicationService {

    /// Determines if a URL represents an encrypted PGP file
    /// - Parameter url: File URL to check
    /// - Returns: True if the file is encrypted
    func isEncryptedFile(_ url: URL) -> Bool {
        return PGPFileAnalyzer.isPGPFile(url: url) && fileAnalyzer.isEncrypted(fileAt: url)
    }

    /// Returns appropriate operation for a given file
    /// - Parameter url: File URL to analyze
    /// - Returns: Operation type (encrypt or decrypt)
    func operationType(for url: URL) -> OperationType {
        if isEncryptedFile(url) {
            return .decrypt
        } else {
            return .encrypt
        }
    }
}

// MARK: - Supporting Types

extension ExtensionCommunicationService {
    enum OperationType {
        case encrypt
        case decrypt
    }
}
