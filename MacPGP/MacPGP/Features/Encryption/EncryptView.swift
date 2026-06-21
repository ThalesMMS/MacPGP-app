import SwiftUI
import AppKit

struct EncryptView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(SessionStateManager.self) private var sessionState
    @Environment(NotificationService.self) private var notificationService

    @State private var viewModel: EncryptViewModel? = nil

    var body: some View {
        @Bindable var state = sessionState

        HSplitView {
            inputPane
            outputPane
        }
        .navigationTitle("sidebar.encrypt")
        .toolbar {
            ToolbarItemGroup {
                Picker("encrypt.mode", selection: $state.encryptInputMode) {
                    Text("encrypt.text").tag(InputMode.text)
                    Text("encrypt.file").tag(InputMode.file)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Toggle("encrypt.armor", isOn: $state.encryptArmorOutput)

                Button {
                    viewModel?.encryptFromClipboard()
                } label: {
                    Label("encrypt.from_clipboard", systemImage: "doc.on.clipboard.fill")
                }
                .disabled(viewModel?.isProcessing == true || !(viewModel?.canEncryptFromClipboard ?? false))

                Button {
                    viewModel?.encrypt()
                } label: {
                    Label("sidebar.encrypt", systemImage: "lock.fill")
                }
                .disabled(!canEncrypt)
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
            message: "Enter passphrase for signing key",
            submitTitle: "Encrypt",
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
        .onAppear {
            if viewModel == nil {
                viewModel = EncryptViewModel(
                    keyringService: keyringService,
                    sessionState: sessionState,
                    notificationService: notificationService
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPGPDidLock)) { _ in
            viewModel?.handleLock()
        }
        .sheet(isPresented: Binding(
            get: { viewModel?.requestOutputFolderPicker ?? false },
            set: { viewModel?.requestOutputFolderPicker = $0 }
        )) {
            outputFolderPickerSheet
        }
    }

    private var inputPane: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 16) {
            RecipientPickerView(selectedRecipients: $state.encryptSelectedRecipients)

            Divider()

            signerSection

            Divider()

            Group {
                switch sessionState.encryptInputMode {
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

    private var signerSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            Text("encrypt.sign_with_optional")
                .font(.headline)

            Picker("sign.signing_key", selection: $state.encryptSignerKey) {
                Text("encrypt.dont_sign").tag(nil as PGPKeyModel?)
                ForEach(keyringService.signingKeys()) { key in
                    Text(key.displayName).tag(key as PGPKeyModel?)
                }
            }
            .labelsHidden()
        }
    }

    private var textInputSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            Text("encrypt.message")
                .font(.headline)

            TextEditor(text: $state.encryptInputText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 150)
                .border(Color(nsColor: .separatorColor))
        }
    }

    private var fileInputSection: some View {
        @Bindable var state = sessionState

        return CryptoMultipleFileInputSection(
            title: "Files",
            selectedFiles: $state.encryptSelectedFiles,
            outputLocation: sessionState.encryptOutputLocation,
            onChooseOutputLocation: { viewModel?.requestChoosingOutputLocation() }
        )
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("encrypt.encrypted_output")
                    .font(.headline)
                Spacer()

                if !sessionState.encryptOutputFiles.isEmpty {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(sessionState.encryptOutputFiles)
                    } label: {
                        Label(sessionState.encryptOutputFiles.count == 1 ? "Reveal" : "Reveal All", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                }

                if !sessionState.encryptOutputText.isEmpty || !sessionState.encryptOutputFiles.isEmpty {
                    Button {
                        viewModel?.copyOutputToClipboard()
                    } label: {
                        Label(sessionState.encryptOutputFiles.isEmpty ? "Copy" : "Copy Paths", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if viewModel?.isProcessing == true {
                CryptoProgressOverlay(
                    actionTitle: "Encrypting",
                    progress: sessionState.encryptInputMode == .file ? sessionState.encryptionProgress : nil,
                    fileCount: sessionState.encryptSelectedFiles.count
                )
            } else if sessionState.encryptOutputText.isEmpty && sessionState.encryptOutputFiles.isEmpty {
                ContentUnavailableView(
                    "No Output",
                    systemImage: "lock.open",
                    description: Text(sessionState.encryptInputMode == .file ? "Encrypted files will appear here" : "Encrypted message will appear here")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !sessionState.encryptOutputFiles.isEmpty {
                FileResultListView(files: sessionState.encryptOutputFiles, successTitle: "Encrypted Files")
            } else {
                ScrollView {
                    Text(sessionState.encryptOutputText)
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

    private var canEncrypt: Bool {
        guard viewModel?.isProcessing != true else { return false }

        return !sessionState.encryptSelectedRecipients.isEmpty && (
            (sessionState.encryptInputMode == .text && !sessionState.encryptInputText.isEmpty) ||
            (sessionState.encryptInputMode == .file && !sessionState.encryptSelectedFiles.isEmpty)
        )
    }


    private var outputFolderPickerSheet: some View {
        VStack(spacing: 16) {
            Text("encrypt.choose_output_folder")
                .font(.headline)

            Button("encrypt.choose") {
                let panel = NSOpenPanel()
                panel.canCreateDirectories = true
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.prompt = "Choose Output Folder"
                panel.message = "Select where encrypted files will be saved"

                if panel.runModal() == .OK {
                    viewModel?.didChooseOutputLocation(panel.url)
                } else {
                    viewModel?.didChooseOutputLocation(nil)
                }
            }

            Button("keygen.cancel", role: .cancel) {
                viewModel?.didChooseOutputLocation(nil)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

enum InputMode: String, CaseIterable {
    case text
    case file
}

#Preview {
    let keyringService = KeyringService()
    let trustService = TrustService(keyringService: keyringService)

    return EncryptView()
        .environment(keyringService)
        .environment(SessionStateManager())
        .environment(trustService)
        .environment(NotificationService())
        .frame(width: 800, height: 600)
}
