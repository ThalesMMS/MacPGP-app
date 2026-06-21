import SwiftUI

struct VerifyView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(SessionStateManager.self) private var sessionState
    @State private var viewModel: VerifyViewModel?

    private var isProcessing: Bool { viewModel?.isProcessing ?? false }

    var body: some View {
        @Bindable var state = sessionState

        HSplitView {
            inputPane
            resultPane
        }
        .navigationTitle(String(localized: "verify.title", comment: "Verify feature navigation title"))
        .onAppear {
            if viewModel == nil {
                viewModel = VerifyViewModel(keyringService: keyringService, sessionState: sessionState)
            }
        }
        .onDisappear {
            viewModel?.cancel()
            viewModel = nil
        }
        .toolbar {
            ToolbarItemGroup {
                Picker(String(localized: "verify.mode", comment: "Verify input mode picker"), selection: $state.verifyInputMode) {
                    Text(String(localized: "verify.text", comment: "Text input mode")).tag(InputMode.text)
                    Text(String(localized: "verify.file", comment: "File input mode")).tag(InputMode.file)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .disabled(isProcessing)

                Picker(String(localized: "verify.signature", comment: "Signature mode picker"), selection: $state.verifySignatureMode) {
                    Text(String(localized: "verify.inline", comment: "Inline signature mode")).tag(SignatureMode.inline)
                    Text(String(localized: "verify.detached", comment: "Detached signature mode")).tag(SignatureMode.detached)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .disabled(isProcessing)

                Button {
                    viewModel?.verify()
                } label: {
                    Label(String(localized: "verify.button", comment: "Verify button"), systemImage: "checkmark.seal")
                }
                .disabled(!(viewModel?.canVerify ?? false) || isProcessing)
            }
        }
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
            Group {
                switch sessionState.verifyInputMode {
                case .text:
                    VStack(alignment: .leading, spacing: 16) {
                        textInputSection
                        if sessionState.verifySignatureMode == .detached {
                            Divider()
                            detachedSignatureSection
                        }
                    }
                case .file:
                    VStack(alignment: .leading, spacing: 16) {
                        fileInputSection
                        if sessionState.verifySignatureMode == .detached {
                            Divider()
                            signatureFileSection
                        }
                    }
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 300, idealWidth: 400, maxWidth: 500)
        .disabled(isProcessing)
    }


    private var textInputSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sessionState.verifySignatureMode == .inline
                     ? String(localized: "verify.signed_message", comment: "Signed message label")
                     : String(localized: "verify.original_message", comment: "Original message label"))
                    .font(.headline)

                Spacer()

                Button {
                    pasteFromClipboard()
                } label: {
                    Label(String(localized: "verify.paste", comment: "Paste button"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
            }

            TextEditor(text: $state.verifyInputText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: sessionState.verifySignatureMode == .detached ? 150 : 250)
                .border(Color(nsColor: .separatorColor))
        }
    }

    private var detachedSignatureSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "verify.detached_signature", comment: "Detached signature label"))
                    .font(.headline)

                Spacer()

                Button {
                    pasteSignatureFromClipboard()
                } label: {
                    Label(String(localized: "verify.paste", comment: "Paste button"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
            }

            TextEditor(text: $state.verifySignatureText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 150)
                .border(Color(nsColor: .separatorColor))
        }
    }

    private var fileInputSection: some View {
        @Bindable var state = sessionState

        return CryptoSingleFileInputSection(
            title: sessionState.verifySignatureMode == .inline
                ? String(localized: "verify.signed_file", comment: "Signed file label")
                : String(localized: "verify.original_file", comment: "Original file label"),
            selectedFile: $state.verifySelectedFile
        )
    }

    private var signatureFileSection: some View {
        @Bindable var state = sessionState

        return CryptoSingleFileInputSection(
            title: "Signature File",
            selectedFile: $state.verifySelectedSignatureFile,
            selectedFileIcon: "signature"
        )
    }

    private var resultPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("verification.verification_result")
                .font(.headline)

            if isProcessing {
                CryptoProgressOverlay(actionTitle: "Verifying")
            } else if let result = sessionState.verifyResult {
                verificationResultView(result)
            } else {
                ContentUnavailableView(
                    "No Result",
                    systemImage: "checkmark.seal",
                    description: Text("verification.verification_result_will_appear_here")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .frame(minWidth: 300, maxWidth: .infinity)
    }

    /// Renders a verification result panel showing the outcome and any associated details.
    /// - Parameter result: The `VerificationResult` whose outcome and metadata will be displayed.
    /// - Returns: A view presenting an outcome symbol, title, and message, plus optional signer information, signature date, and the original message when available.
    @ViewBuilder
    private func verificationResultView(_ result: VerificationResult) -> some View {
        let resultColor: Color = {
            switch result.outcome {
            case .valid:
                return .green
            case .invalidSignature, .noSignatures:
                return .red
            case .expired, .mixed, .missingKey, .unknownStatus, .error:
                return .orange
            }
        }()

        VStack(spacing: 24) {
            Spacer()

            Image(systemName: result.symbolName)
                .font(.system(size: 64))
                .foregroundStyle(resultColor)

            Text(result.title)
                .font(.title)
                .fontWeight(.semibold)

            Text(result.message)
                .foregroundStyle(.secondary)

            if let signer = result.signerKey {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("verification.signed_by", systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(signer.displayName)
                            .font(.headline)

                        if let email = signer.email {
                            Text(email)
                                .foregroundStyle(.secondary)
                        }

                        Text(signer.shortKeyID)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 300)
            }

            if let date = result.signatureDate {
                Text(String.localizedStringWithFormat(NSLocalizedString("verify.signed_on_format", comment: ""), date.formatted()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let originalMessage = result.originalMessage {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("verify.original_message", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView {
                            Text(originalMessage)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                    }
                }
                .frame(maxWidth: 400)
            }

            Spacer()
        }
    }

    private func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            sessionState.verifyInputText = string
        }
    }

    private func pasteSignatureFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            sessionState.verifySignatureText = string
        }
    }
}

enum SignatureMode: String, CaseIterable {
    case inline
    case detached
}

#Preview {
    VerifyView()
        .environment(KeyringService())
        .environment(SessionStateManager())
        .frame(width: 800, height: 600)
}
