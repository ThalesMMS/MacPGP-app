import Cocoa

class ShareViewController: NSViewController {

    // MARK: - Properties

    private var fileURLs: [URL] = []
    private let services = ExtensionServices.shared

    // MARK: - Lifecycle

    override var nibName: NSNib.Name? {
        return NSNib.Name("ShareViewController")
    }

    override func loadView() {
        // Create a default view if no nib is found
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Initialize encryption services and load keys
        services.reloadKeys()

        // Set up the view controller
        setupUI()

        // Extract files from the extension context
        extractSharedFiles()
    }

    // MARK: - Setup

    private func setupUI() {
        // Configure the view appearance
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // UI will be implemented in subtask-2-2 (SwiftUI view)
    }

    // MARK: - Extension Context Handling

    /// Extracts file URLs from the NSExtensionContext input items
    private func extractSharedFiles() {
        guard let extensionContext = self.extensionContext else {
            NSLog("ShareViewController: No extension context available")
            cancel()
            return
        }

        guard let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            NSLog("ShareViewController: No input items found")
            cancel()
            return
        }

        // Process each input item to extract file URLs
        var urlsToProcess: [URL] = []

        for item in inputItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                // Check if this is a file URL
                if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                    let semaphore = DispatchSemaphore(value: 0)

                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                        defer { semaphore.signal() }

                        if let error = error {
                            NSLog("ShareViewController: Error loading file URL: \(error.localizedDescription)")
                            return
                        }

                        if let url = item as? URL {
                            urlsToProcess.append(url)
                        } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            urlsToProcess.append(url)
                        }
                    }

                    semaphore.wait()
                }
            }
        }

        if urlsToProcess.isEmpty {
            NSLog("ShareViewController: No files found in shared items")
            cancel()
            return
        }

        // Store the extracted file URLs
        self.fileURLs = urlsToProcess
        NSLog("ShareViewController: Extracted \(fileURLs.count) file(s) to encrypt")

        // Update UI with the files (will be implemented in subtask-2-2)
        updateUIWithFiles()
    }

    /// Updates the UI to show the selected files
    /// This will be implemented in subtask-2-2 with SwiftUI
    private func updateUIWithFiles() {
        // Placeholder for UI update
        // SwiftUI view will be integrated here
    }

    // MARK: - Encryption

    /// Encrypts the shared files with the specified recipients
    /// Call this method to encrypt files for recipients using PGP encryption
    /// - Parameters:
    ///   - recipients: Array of PGP key models to encrypt for
    ///   - signer: Optional secret key to sign the files with
    ///   - passphrase: Passphrase for the signing key (required if signer is provided)
    ///   - armored: Whether to use ASCII armored output (default: false for files)
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Array of URLs pointing to the encrypted files
    /// - Throws: OperationError if encryption fails
    func encryptFiles(
        for recipients: [PGPKeyModel],
        signedBy signer: PGPKeyModel? = nil,
        passphrase: String? = nil,
        armored: Bool = false,
        progressCallback: ((Double) -> Void)? = nil
    ) throws -> [URL] {
        guard !fileURLs.isEmpty else {
            throw OperationError.encryptionFailed(underlying: nil)
        }

        guard !recipients.isEmpty else {
            throw OperationError.recipientKeyMissing
        }

        var encryptedURLs: [URL] = []
        let totalFiles = fileURLs.count

        for (index, fileURL) in fileURLs.enumerated() {
            do {
                // Calculate progress for this file
                let fileProgress: ((Double) -> Void)? = progressCallback != nil ? { progress in
                    let overallProgress = (Double(index) + progress) / Double(totalFiles)
                    progressCallback?(overallProgress)
                } : nil

                // Encrypt the file using the encryption service
                let encryptedURL = try services.encryptionService.encrypt(
                    file: fileURL,
                    for: recipients,
                    signedBy: signer,
                    passphrase: passphrase,
                    outputURL: nil,
                    armored: armored,
                    progressCallback: fileProgress
                )

                encryptedURLs.append(encryptedURL)
                NSLog("ShareViewController: Encrypted file \(index + 1)/\(totalFiles): \(fileURL.lastPathComponent)")
            } catch {
                NSLog("ShareViewController: Failed to encrypt file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                throw error
            }
        }

        return encryptedURLs
    }

    /// Encrypts files asynchronously with the specified recipients
    /// - Parameters:
    ///   - recipients: Array of PGP key models to encrypt for
    ///   - signer: Optional secret key to sign the files with
    ///   - passphrase: Passphrase for the signing key (required if signer is provided)
    ///   - armored: Whether to use ASCII armored output (default: false for files)
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Array of URLs pointing to the encrypted files
    func encryptFilesAsync(
        for recipients: [PGPKeyModel],
        signedBy signer: PGPKeyModel? = nil,
        passphrase: String? = nil,
        armored: Bool = false,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [URL] {
        guard !fileURLs.isEmpty else {
            throw OperationError.encryptionFailed(underlying: nil)
        }

        guard !recipients.isEmpty else {
            throw OperationError.recipientKeyMissing
        }

        var encryptedURLs: [URL] = []
        let totalFiles = fileURLs.count

        for (index, fileURL) in fileURLs.enumerated() {
            // Calculate progress for this file
            let fileProgress: (@Sendable (Double) -> Void)? = if let callback = progressCallback {
                { (progress: Double) in
                    let overallProgress = (Double(index) + progress) / Double(totalFiles)
                    callback(overallProgress)
                }
            } else {
                nil
            }

            // Encrypt the file using the encryption service
            let encryptedURL = try await services.encryptionService.encryptAsync(
                file: fileURL,
                for: recipients,
                signedBy: signer,
                passphrase: passphrase,
                outputURL: nil,
                armored: armored,
                progressCallback: fileProgress
            )

            encryptedURLs.append(encryptedURL)
            NSLog("ShareViewController: Encrypted file \(index + 1)/\(totalFiles): \(fileURL.lastPathComponent)")
        }

        return encryptedURLs
    }

    // MARK: - Actions

    /// Cancels the share extension operation
    func cancel() {
        guard let extensionContext = self.extensionContext else { return }
        extensionContext.cancelRequest(withError: NSError(domain: "com.macpgp.ShareExtension", code: -1, userInfo: nil))
    }

    /// Completes the share extension operation with encrypted files
    /// - Parameter encryptedFileURLs: The URLs of the encrypted files to return
    func complete(with encryptedFileURLs: [URL]) {
        guard let extensionContext = self.extensionContext else { return }

        // Create output items for the encrypted files
        let outputItems: [NSExtensionItem] = encryptedFileURLs.compactMap { url in
            guard let provider = NSItemProvider(contentsOf: url) else { return nil }
            let item = NSExtensionItem()
            item.attachments = [provider]
            return item
        }

        // Complete the request with the encrypted files
        extensionContext.completeRequest(returningItems: outputItems, completionHandler: nil)
    }
}
