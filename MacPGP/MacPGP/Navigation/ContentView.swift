import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(SessionStateManager.self) private var sessionState
    @State private var selectedSidebarItem: SidebarItem? = .keyring
    @State private var selectedKey: PGPKeyModel?
    @State private var showingKeyGeneration = false
    @State private var showingImportSheet = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var notificationService = NotificationService()

    private var needsDetailColumn: Bool {
        selectedSidebarItem == .keyring
    }

    var body: some View {
        Group {
            if needsDetailColumn {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(selection: $selectedSidebarItem)
                } content: {
                    KeyringView(selectedKey: $selectedKey)
                } detail: {
                    detailView
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationSplitView {
                    SidebarView(selection: $selectedSidebarItem)
                } detail: {
                    contentView
                }
                .navigationSplitViewStyle(.prominentDetail)
            }
        }
        .sheet(isPresented: $showingKeyGeneration) {
            KeyGenerationView()
        }
        .fileImporter(
            isPresented: $showingImportSheet,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKeyGeneration)) { _ in
            showingKeyGeneration = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .importKey)) { _ in
            showingImportSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: ExtensionCommunicationService.encryptFilesNotification)) { notification in
            handleEncryptFiles(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: ExtensionCommunicationService.decryptFilesNotification)) { notification in
            handleDecryptFiles(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .encryptClipboard)) { _ in
            handleEncryptClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .decryptClipboard)) { _ in
            handleDecryptClipboard()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedSidebarItem {
        case .encrypt:
            EncryptView()
        case .decrypt:
            DecryptView()
        case .sign:
            SignView()
        case .verify:
            VerifyView()
        case .webOfTrust:
            WebOfTrustView()
        case .keyring, nil:
            Text(String(localized: "contentview.select_item", comment: "Placeholder text when no sidebar item is selected"))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let key = selectedKey {
            KeyDetailsView(key: key)
        } else {
            ContentUnavailableView(
                String(localized: "contentview.no_key_selected", comment: "Title shown when no PGP key is selected"),
                systemImage: "key",
                description: Text(String(localized: "contentview.select_key_description", comment: "Description prompting user to select a key"))
            )
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let importedKeys = try keyringService.importKey(from: url)
                    if let firstKey = importedKeys.first {
                        selectedKey = firstKey
                    }
                } catch {
                    print("Import failed: \(error)")
                }
            }
        case .failure(let error):
            print("File selection failed: \(error)")
        }
    }

    private func handleEncryptFiles(_ notification: Notification) {
        guard let urls = notification.userInfo?[ExtensionCommunicationService.fileURLsKey] as? [URL],
              !urls.isEmpty else {
            return
        }

        // Switch to encrypt view
        selectedSidebarItem = .encrypt

        // Set file mode and populate files
        sessionState.encryptInputMode = .file
        sessionState.encryptSelectedFiles = urls
    }

    private func handleDecryptFiles(_ notification: Notification) {
        guard let urls = notification.userInfo?[ExtensionCommunicationService.fileURLsKey] as? [URL],
              !urls.isEmpty else {
            return
        }

        // Switch to decrypt view
        selectedSidebarItem = .decrypt

        // Set file mode and populate files
        sessionState.decryptInputMode = .file
        sessionState.decryptSelectedFiles = urls
    }

    private func handleEncryptClipboard() {
        // Check if clipboard has text
        guard let clipboardText = NSPasteboard.general.string(forType: .string),
              !clipboardText.isEmpty else {
            notificationService.showError(
                title: String(localized: "error.clipboard_empty", comment: "Error title when clipboard has no content"),
                message: String(localized: "error.no_text_in_clipboard", comment: "Error message when clipboard has no text")
            )
            return
        }

        // Check if recipients are selected
        guard !sessionState.encryptSelectedRecipients.isEmpty else {
            notificationService.showError(
                title: String(localized: "error.no_recipients", comment: "Error title when no encryption recipients are selected"),
                message: String(localized: "error.select_recipients_first", comment: "Error message prompting user to select recipients")
            )
            return
        }

        let encryptionService = EncryptionService(keyringService: keyringService)
        var passphrase: String?

        // If signing key is selected, try to get passphrase from keychain
        if let signerKey = sessionState.encryptSignerKey {
            passphrase = try? KeychainManager.shared.retrievePassphrase(forKeyID: signerKey.shortKeyID)
            if passphrase == nil {
                notificationService.showError(
                    title: String(localized: "error.passphrase_required", comment: "Error title when passphrase is required for signing"),
                    message: String(localized: "error.enter_passphrase_for_signing", comment: "Error message prompting user to enter passphrase in Encrypt view")
                )
                return
            }
        }

        Task {
            do {
                let recipients = Array(sessionState.encryptSelectedRecipients)
                let encrypted = try encryptionService.encrypt(
                    message: clipboardText,
                    for: recipients,
                    signedBy: sessionState.encryptSignerKey,
                    passphrase: passphrase,
                    armored: sessionState.encryptArmorOutput
                )

                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(encrypted, forType: .string)

                    notificationService.showSuccess(
                        title: String(localized: "success.encryption_successful", comment: "Success title when clipboard encryption completes"),
                        message: String(localized: "success.clipboard_encrypted", comment: "Success message confirming clipboard contents were encrypted")
                    )
                }
            } catch {
                await MainActor.run {
                    notificationService.showError(
                        title: String(localized: "error.encryption_failed", comment: "Error title when encryption operation fails"),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func handleDecryptClipboard() {
        // Check if clipboard has text
        guard let clipboardText = NSPasteboard.general.string(forType: .string),
              !clipboardText.isEmpty else {
            notificationService.showError(
                title: String(localized: "error.clipboard_empty", comment: "Error title when clipboard has no content"),
                message: String(localized: "error.no_text_in_clipboard", comment: "Error message when clipboard has no text")
            )
            return
        }

        // Check if secret keys are available
        guard !keyringService.secretKeys().isEmpty else {
            notificationService.showError(
                title: String(localized: "error.no_secret_keys", comment: "Error title when no secret keys are available"),
                message: String(localized: "error.no_secret_keys_for_decryption", comment: "Error message when no secret keys available for decryption")
            )
            return
        }

        let encryptionService = EncryptionService(keyringService: keyringService)

        Task {
            do {
                guard let data = clipboardText.data(using: .utf8) else {
                    throw OperationError.decryptionFailed(underlying: nil)
                }

                // Try all secret keys with keychain passphrases
                var decrypted: String?
                for key in keyringService.secretKeys() {
                    if let passphrase = try? KeychainManager.shared.retrievePassphrase(forKeyID: key.shortKeyID) {
                        do {
                            decrypted = try encryptionService.decrypt(
                                message: clipboardText,
                                using: key,
                                passphrase: passphrase
                            )
                            break
                        } catch {
                            // Try next key
                            continue
                        }
                    }
                }

                guard let result = decrypted else {
                    throw OperationError.unknownError(message: String(localized: "error.no_valid_passphrase", comment: "Error message when no valid passphrase found in keychain for decryption"))
                }

                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)

                    notificationService.showSuccess(
                        title: String(localized: "success.decryption_successful", comment: "Success title when clipboard decryption completes"),
                        message: String(localized: "success.clipboard_decrypted", comment: "Success message confirming clipboard contents were decrypted")
                    )
                }
            } catch {
                await MainActor.run {
                    notificationService.showError(
                        title: String(localized: "error.decryption_failed", comment: "Error title when decryption operation fails"),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }
}

#Preview {
    let keyringService = KeyringService()
    let trustService = TrustService(keyringService: keyringService)

    return ContentView()
        .environment(keyringService)
        .environment(SessionStateManager())
        .environment(trustService)
}
