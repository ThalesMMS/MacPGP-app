import SwiftUI

struct SignView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(SessionStateManager.self) private var sessionState
    @State private var viewModel: SignViewModel?

    private var isProcessing: Bool { viewModel?.isProcessing ?? false }

    var body: some View {
        @Bindable var state = sessionState

        HSplitView {
            inputPane
            outputPane
        }
        .navigationTitle(String(localized: "sign.title", comment: "Sign feature navigation title"))
        .onAppear {
            if viewModel == nil {
                viewModel = SignViewModel(keyringService: keyringService, sessionState: sessionState)
            }
            viewModel?.validateSelectedSigner()
        }
        .onDisappear {
            viewModel?.cancel()
            viewModel = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPGPDidLock)) { _ in
            viewModel?.handleLock()
        }
        .onChange(of: signingKeyFingerprints) { _, _ in
            viewModel?.validateSelectedSigner()
        }
        .toolbar {
            ToolbarItemGroup {
                Picker(String(localized: "sign.mode", comment: "Sign input mode picker"), selection: $state.signInputMode) {
                    Text(String(localized: "sign.text", comment: "Text input mode")).tag(InputMode.text)
                    Text(String(localized: "sign.file", comment: "File input mode")).tag(InputMode.file)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                if sessionState.signInputMode == .text {
                    Toggle(String(localized: "sign.cleartext", comment: "Cleartext signature toggle"), isOn: $state.signCleartextSignature)
                        .disabled(sessionState.signDetachedSignature)
                }
                Toggle(String(localized: "sign.detached", comment: "Detached signature toggle"), isOn: $state.signDetachedSignature)
                Toggle(String(localized: "sign.armor", comment: "Armor output toggle"), isOn: $state.signArmorOutput)

                Button {
                    viewModel?.promptForPassphrase()
                } label: {
                    Label(String(localized: "sign.button", comment: "Sign button"), systemImage: "signature")
                }
                .disabled(!(viewModel?.canSign ?? false) || isProcessing)
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
            message: viewModel?.passphrasePromptMessage ?? "",
            submitTitle: String(localized: "sign.button", comment: "Sign button"),
            onCancel: { viewModel?.cancelPassphrasePrompt() },
            onSubmit: { viewModel?.sign() }
        )
        .cryptoErrorAlert(
            message: viewModel?.errorMessage,
            isPresented: Binding(
                get: { viewModel?.showingError ?? false },
                set: { viewModel?.showingError = $0 }
            )
        )
    }

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            signerSelectionSection

            Divider()

            Group {
                switch sessionState.signInputMode {
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

    private var signerSelectionSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "sign.signing_key", comment: "Signing key section header"))
                .font(.headline)

            if signingKeys.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(String(localized: "sign.no_secret_keys", comment: "No usable signing key message"))
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Picker(String(localized: "sign.signing_key", comment: "Signing key picker"), selection: $state.signSignerKey) {
                    Text(String(localized: "sign.select_key_placeholder", comment: "Key selection placeholder")).tag(nil as PGPKeyModel?)
                    ForEach(signingKeys) { key in
                        HStack {
                            Text(verbatim: key.displayName)
                            if let email = key.email {
                                Text(verbatim: "(\(email))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(key as PGPKeyModel?)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var textInputSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "sign.message_to_sign", comment: "Message to sign section header"))
                    .font(.headline)

                Spacer()

                Button {
                    pasteFromClipboard()
                } label: {
                    Label(String(localized: "sign.paste", comment: "Paste button"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
            }

            TextEditor(text: $state.signInputText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)
                .border(Color(nsColor: .separatorColor))
        }
    }

    private var fileInputSection: some View {
        @Bindable var state = sessionState

        return CryptoSingleFileInputSection(
            title: "File to Sign",
            selectedFile: $state.signSelectedFile
        )
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(outputTitle)
                    .font(.headline)
                Spacer()

                if !sessionState.signOutputFiles.isEmpty {
                    Button {
                        revealOutputFiles()
                    } label: {
                        Label("common.reveal", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                }

                if !sessionState.signOutputText.isEmpty || !sessionState.signOutputFiles.isEmpty {
                    Button {
                        copyOutput()
                    } label: {
                        Label(sessionState.signOutputFiles.isEmpty ? "Copy" : "Copy Path", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if isProcessing {
                CryptoProgressOverlay(actionTitle: "Signing")
            } else if sessionState.signOutputText.isEmpty && sessionState.signOutputFiles.isEmpty {
                ContentUnavailableView(
                    "No Output",
                    systemImage: "signature",
                    description: Text(outputEmptyStateDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !sessionState.signOutputFiles.isEmpty {
                FileResultListView(files: sessionState.signOutputFiles, successTitle: fileResultTitle)
            } else {
                ScrollView {
                    Text(sessionState.signOutputText)
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

    private var signingKeys: [PGPKeyModel] {
        viewModel?.signingKeys ?? keyringService.signingKeys()
    }

    private var signingKeyFingerprints: [String] {
        signingKeys.map(\.fingerprint)
    }

    private var outputTitle: String {
        if sessionState.signInputMode == .file {
            return sessionState.signDetachedSignature ? "Signature File" : "Signed File"
        }

        return sessionState.signDetachedSignature ? "Signature" : "Signed Message"
    }

    private var outputEmptyStateDescription: String {
        if sessionState.signInputMode == .file {
            return sessionState.signDetachedSignature
                ? "Signature file will appear here"
                : "Signed file will appear here"
        }

        return sessionState.signDetachedSignature
            ? "Signature will appear here"
            : "Signed message will appear here"
    }

    private var fileResultTitle: String {
        sessionState.signDetachedSignature ? "Signature Files" : "Signed Files"
    }

    private func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            sessionState.signInputText = string
        }
    }

    private func copyOutput() {
        NSPasteboard.general.clearContents()
        let content: String
        if !sessionState.signOutputFiles.isEmpty {
            content = sessionState.signOutputFiles.map(\.path).joined(separator: "\n")
        } else {
            content = sessionState.signOutputText
        }
        NSPasteboard.general.setString(content, forType: .string)
    }

    private func revealOutputFiles() {
        NSWorkspace.shared.activateFileViewerSelecting(sessionState.signOutputFiles)
    }

}

#Preview {
    SignView()
        .environment(KeyringService())
        .environment(SessionStateManager())
        .frame(width: 800, height: 600)
}
