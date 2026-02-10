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
            Text("Select an item")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let key = selectedKey {
            KeyDetailsView(key: key)
        } else {
            ContentUnavailableView(
                "No Key Selected",
                systemImage: "key",
                description: Text("Select a key to view its details")
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
                title: "Clipboard Empty",
                message: "No text found in clipboard"
            )
            return
        }

        // Check if recipients are selected
        guard !sessionState.encryptSelectedRecipients.isEmpty else {
            notificationService.showError(
                title: "No Recipients",
                message: "Please select recipients in the Encrypt view first"
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
                    title: "Passphrase Required",
                    message: "Please enter passphrase in the Encrypt view for signing key"
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
                        title: "Encryption Successful",
                        message: "Clipboard contents have been encrypted"
                    )
                }
            } catch {
                await MainActor.run {
                    notificationService.showError(
                        title: "Encryption Failed",
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
                title: "Clipboard Empty",
                message: "No text found in clipboard"
            )
            return
        }

        // Check if secret keys are available
        guard !keyringService.secretKeys().isEmpty else {
            notificationService.showError(
                title: "No Secret Keys",
                message: "No secret keys available for decryption"
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
                    throw OperationError.unknownError(message: "No valid passphrase found in keychain. Please decrypt manually in the Decrypt view.")
                }

                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)

                    notificationService.showSuccess(
                        title: "Decryption Successful",
                        message: "Clipboard contents have been decrypted"
                    )
                }
            } catch {
                await MainActor.run {
                    notificationService.showError(
                        title: "Decryption Failed",
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
