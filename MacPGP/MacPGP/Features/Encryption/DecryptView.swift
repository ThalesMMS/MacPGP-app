import SwiftUI

struct DecryptView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(SessionStateManager.self) private var sessionState
    @Environment(NotificationService.self) private var notificationService

    @State private var viewModel: DecryptViewModel?

    var body: some View {
        @Bindable var state = sessionState

        HSplitView {
            inputPane
            outputPane
        }
        .navigationTitle("sidebar.decrypt")
        .toolbar {
            ToolbarItemGroup {
                Picker("encrypt.mode", selection: $state.decryptInputMode) {
                    Text("encrypt.text").tag(InputMode.text)
                    Text("encrypt.file").tag(InputMode.file)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Button {
                    viewModel?.decryptFromClipboard()
                } label: {
                    Label("decrypt.from_clipboard", systemImage: "doc.on.clipboard.fill")
                }
                .disabled(!(viewModel?.canDecryptFromClipboard ?? false))

                Button {
                    viewModel?.requestPassphraseAndDecrypt(fromClipboard: false)
                } label: {
                    Label("sidebar.decrypt", systemImage: "lock.open.fill")
                }
                .disabled(!canDecrypt || viewModel?.isProcessing == true)
            }
        }
        .passphrasePromptAlert(
            isPresented: Binding(
                get: { viewModel?.showingPassphrasePrompt ?? false },
                set: { viewModel?.showingPassphrasePrompt = $0 }
            ),
            passphrase: Binding(
                get: { viewModel?.passphrase ?? "" },
                set: { viewModel?.passphrase = $0 }
            ),
            message: passphrasePromptMessage,
            submitTitle: "Decrypt",
            onCancel: { viewModel?.cancelPassphrasePrompt() },
            onSubmit: { viewModel?.didSubmitPassphrase() }
        )
        .cryptoErrorAlert(
            title: viewModel?.alert?.title ?? "Error",
            message: viewModel?.alert?.message,
            isPresented: Binding(
                get: { viewModel?.showingAlert ?? false },
                set: { viewModel?.showingAlert = $0 }
            )
        )
        .onChange(of: viewModel?.requestOutputFolderPicker ?? false) { _, shouldPresent in
            guard shouldPresent else { return }
            presentOutputFolderPicker()
        }
        .onAppear {
            if viewModel == nil {
                viewModel = DecryptViewModel(
                    keyringService: keyringService,
                    sessionState: sessionState,
                    notificationService: notificationService
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPGPDidLock)) { _ in
            viewModel?.handleLock()
        }
        .onDisappear {
            viewModel?.cancel()
            viewModel = nil
        }
    }

    private func presentOutputFolderPicker() {
        let panel = NSOpenPanel()
        panel.canCreateDirectories = true
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Choose Output Folder"
        panel.message = "Select where decrypted files will be saved"

        if panel.runModal() == .OK {
            viewModel?.didChooseOutputLocation(panel.url)
        } else {
            viewModel?.didChooseOutputLocation(nil)
        }
    }

    private var passphrasePromptMessage: String {
        if let key = viewModel?.passphrasePromptKey {
            return "Enter passphrase for \(key.displayName)"
        }
        return "Enter passphrase to decrypt"
    }

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            keySelectionSection

            Divider()

            Group {
                switch sessionState.decryptInputMode {
                case .text:
                    textInputSection
                case .file:
                    fileInputSection
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 300, idealWidth: 400, maxWidth: 500)
    }

    private var keySelectionSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("decrypt.decryption_key")
                    .font(.headline)

                Spacer()

                Toggle("decrypt.auto_detect", isOn: $state.decryptAutoDetectKey)
                    .toggleStyle(.checkbox)
            }

            if !sessionState.decryptAutoDetectKey {
                Picker("decrypt.select_key", selection: $state.decryptSelectedKey) {
                    Text("decrypt.select_key_placeholder").tag(nil as PGPKeyModel?)
                    ForEach(keyringService.secretKeys()) { key in
                        Text(key.displayName).tag(key as PGPKeyModel?)
                    }
                }
                .labelsHidden()
            } else {
                Text("decrypt.will_try_all_available_secret_keys")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if keyringService.secretKeys().isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("content.no_secret_keys_decryption")
                        .font(.caption)
                }
            }
        }
    }

    private var textInputSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("decrypt.encrypted_message")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel?.pasteFromClipboard()
                } label: {
                    Label("sign.paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
            }

            TextEditor(text: $state.decryptInputText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)
                .border(Color(nsColor: .separatorColor))
        }
    }

    private var fileInputSection: some View {
        @Bindable var state = sessionState

        return CryptoMultipleFileInputSection(
            title: "Encrypted Files",
            selectedFiles: $state.decryptSelectedFiles,
            outputLocation: sessionState.decryptOutputLocation,
            onChooseOutputLocation: { viewModel?.requestChoosingOutputLocation() }
        )
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("decrypt.decrypted_output")
                    .font(.headline)
                Spacer()

                if !sessionState.decryptOutputFiles.isEmpty {
                    Button {
                        viewModel?.revealOutputFilesInFinder()
                    } label: {
                        Label(sessionState.decryptOutputFiles.count == 1 ? "Reveal" : "Reveal All", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                }

                if !sessionState.decryptOutputText.isEmpty || !sessionState.decryptOutputFiles.isEmpty {
                    Button {
                        viewModel?.copyOutputToClipboard()
                    } label: {
                        Label(sessionState.decryptOutputFiles.isEmpty ? "Copy" : "Copy Paths", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if viewModel?.isProcessing ?? false {
                CryptoProgressOverlay(
                    actionTitle: "Decrypting",
                    progress: sessionState.decryptInputMode == .file ? sessionState.decryptionProgress : nil,
                    fileCount: sessionState.decryptSelectedFiles.count
                )
            } else if sessionState.decryptOutputText.isEmpty && sessionState.decryptOutputFiles.isEmpty {
                ContentUnavailableView(
                    "No Output",
                    systemImage: "lock.fill",
                    description: Text(sessionState.decryptInputMode == .file ? "Decrypted files will appear here" : "Decrypted message will appear here")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !sessionState.decryptOutputFiles.isEmpty {
                FileResultListView(files: sessionState.decryptOutputFiles, successTitle: "Decrypted Files")
            } else {
                ScrollView {
                    Text(sessionState.decryptOutputText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .frame(minWidth: 300, maxWidth: .infinity)
    }

    private var canDecrypt: Bool {
        guard !keyringService.secretKeys().isEmpty else { return false }
        guard sessionState.decryptAutoDetectKey || sessionState.decryptSelectedKey != nil else { return false }

        switch sessionState.decryptInputMode {
        case .text:
            return !sessionState.decryptInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file:
            return !sessionState.decryptSelectedFiles.isEmpty && sessionState.decryptOutputLocation != nil
        }
    }

}

#Preview {
    let keyringService = KeyringService()
    let trustService = TrustService(keyringService: keyringService)

    return DecryptView()
        .environment(keyringService)
        .environment(SessionStateManager())
        .environment(trustService)
        .environment(NotificationService())
        .frame(width: 800, height: 600)
}
