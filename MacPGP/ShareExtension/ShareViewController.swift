import Cocoa
import SwiftUI

class ShareViewController: NSViewController {

    // MARK: - Properties

    private var fileURLs: [URL] = []
    private let services = ExtensionServices.shared
    private var hostingController: NSHostingController<AnyView>?

    // MARK: - Lifecycle

    override var nibName: NSNib.Name? {
        return NSNib.Name("ShareViewController")
    }

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 600))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Initialize encryption services and load keys
        services.reloadKeys()

        // Set up the view controller
        setupUI()

        Task {
            await extractSharedFiles()
        }
    }

    // MARK: - Setup

    private func setupUI() {
        // Configure the view appearance
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    // MARK: - Extension Context Handling

    /// Extracts file URLs from the NSExtensionContext input items
    private func extractSharedFiles() async {
        guard let extensionContext = self.extensionContext else {
            NSLog("ShareViewController: No extension context available")
            showErrorMessage("MacPGP could not access the shared item. Try sharing the file again.")
            return
        }

        guard let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            NSLog("ShareViewController: No input items found")
            showErrorMessage("No shared items were found. Try sharing the file again.")
            return
        }

        let urlsToProcess = await ShareItemFileLoader.fileURLs(from: inputItems)
        if urlsToProcess.isEmpty {
            NSLog("ShareViewController: No files found in shared items")
            showErrorMessage("No supported files were available to encrypt. Try sharing a file from Finder or exporting it as a file first.")
            return
        }

        // Store the extracted file URLs
        self.fileURLs = urlsToProcess
        NSLog("ShareViewController: Extracted \(fileURLs.count) file(s) to encrypt")

        updateUIWithFiles()
    }

    /// Updates the UI to show the selected files
    private func updateUIWithFiles() {
        let shareView = ShareExtensionView(
            fileURLs: fileURLs,
            onEncrypt: { [weak self] recipients in
                self?.encryptSharedFiles(for: recipients)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )
        .environment(services.keyringService)

        let hostingController = NSHostingController(rootView: AnyView(shareView))
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        self.hostingController?.removeFromParent()
        view.subviews.forEach { $0.removeFromSuperview() }
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.hostingController = hostingController
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
            let error = OperationError.encryptionFailed(underlying: nil)
            showErrorMessage(error.userFacingMessage)
            throw error
        }

        guard !recipients.isEmpty else {
            let error = OperationError.recipientKeyMissing
            showErrorMessage(error.userFacingMessage)
            throw error
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
                showErrorMessage("Unable to encrypt \(fileURL.lastPathComponent).\n\n\(error.userFacingMessage)")
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
            let error = OperationError.encryptionFailed(underlying: nil)
            showErrorMessage(error.userFacingMessage)
            throw error
        }

        guard !recipients.isEmpty else {
            let error = OperationError.recipientKeyMissing
            showErrorMessage(error.userFacingMessage)
            throw error
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

            do {
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
            } catch {
                NSLog("ShareViewController: Failed to encrypt file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                showErrorMessage("Unable to encrypt \(fileURL.lastPathComponent).\n\n\(error.userFacingMessage)")
                throw error
            }
        }

        return encryptedURLs
    }

    // MARK: - Actions

    private func encryptSharedFiles(for recipients: Set<PGPKeyModel>) {
        Task {
            do {
                let encryptedURLs = try await encryptFilesAsync(for: Array(recipients))
                complete(with: encryptedURLs)
            } catch {
                NSLog("ShareViewController: Encryption failed: \(error.localizedDescription)")
            }
        }
    }

    /// Cancels the share extension operation
    func cancel() {
        guard let extensionContext = self.extensionContext else { return }
        extensionContext.cancelRequest(withError: NSError(domain: "com.macpgp.ShareExtension", code: -1, userInfo: nil))
    }

    private func showErrorMessage(_ message: String) {
        DispatchQueue.main.async {
            self.hostingController?.removeFromParent()
            self.hostingController = nil
            self.view.subviews.forEach { $0.removeFromSuperview() }

            let titleLabel = NSTextField(labelWithString: "Unable to Encrypt")
            titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
            titleLabel.alignment = .center

            let messageLabel = NSTextField(wrappingLabelWithString: message)
            messageLabel.alignment = .center
            messageLabel.textColor = .secondaryLabelColor

            let closeButton = NSButton(title: "Close", target: self, action: #selector(self.closeAfterError))
            closeButton.bezelStyle = .rounded

            let stackView = NSStackView(views: [titleLabel, messageLabel, closeButton])
            stackView.orientation = .vertical
            stackView.alignment = .centerX
            stackView.spacing = 16
            stackView.translatesAutoresizingMaskIntoConstraints = false

            self.view.addSubview(stackView)
            NSLayoutConstraint.activate([
                stackView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                stackView.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
                stackView.leadingAnchor.constraint(greaterThanOrEqualTo: self.view.leadingAnchor, constant: 32),
                stackView.trailingAnchor.constraint(lessThanOrEqualTo: self.view.trailingAnchor, constant: -32),
                messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
            ])
        }
    }

    @objc private func closeAfterError() {
        cancel()
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
