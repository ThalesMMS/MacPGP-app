import SwiftUI

struct VerifyView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(SessionStateManager.self) private var sessionState
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private var signingService: SigningService {
        SigningService(keyringService: keyringService)
    }

    var body: some View {
        @Bindable var state = sessionState

        HSplitView {
            inputPane
            resultPane
        }
        .navigationTitle("Verify")
        .toolbar {
            ToolbarItemGroup {
                Picker("Mode", selection: $state.verifyInputMode) {
                    Text("Text").tag(InputMode.text)
                    Text("File").tag(InputMode.file)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Picker("Signature", selection: $state.verifySignatureMode) {
                    Text("Inline").tag(SignatureMode.inline)
                    Text("Detached").tag(SignatureMode.detached)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Button {
                    verify()
                } label: {
                    Label("Verify", systemImage: "checkmark.seal")
                }
                .disabled(!canVerify)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
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
    }


    private var textInputSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sessionState.verifySignatureMode == .inline ? "Signed Message" : "Original Message")
                    .font(.headline)

                Spacer()

                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
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
                Text("Detached Signature")
                    .font(.headline)

                Spacer()

                Button {
                    pasteSignatureFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
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

        return VStack(alignment: .leading, spacing: 8) {
            Text(sessionState.verifySignatureMode == .inline ? "Signed File" : "Original File")
                .font(.headline)

            if let file = sessionState.verifySelectedFile {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                    Text(file.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Button("Remove") {
                        sessionState.verifySelectedFile = nil
                    }
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                DropZone(fileURL: $state.verifySelectedFile)
            }
        }
    }

    private var signatureFileSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            Text("Signature File")
                .font(.headline)

            if let file = sessionState.verifySelectedSignatureFile {
                HStack {
                    Image(systemName: "signature")
                        .foregroundStyle(.secondary)
                    Text(file.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Button("Remove") {
                        sessionState.verifySelectedSignatureFile = nil
                    }
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                DropZone(fileURL: $state.verifySelectedSignatureFile)
            }
        }
    }

    private var resultPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Verification Result")
                .font(.headline)

            if isProcessing {
                Spacer()
                ProgressView("Verifying...")
                Spacer()
            } else if let result = sessionState.verifyResult {
                verificationResultView(result)
            } else {
                ContentUnavailableView(
                    "No Result",
                    systemImage: "checkmark.seal",
                    description: Text("Verification result will appear here")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .frame(minWidth: 300, maxWidth: .infinity)
    }

    @ViewBuilder
    private func verificationResultView(_ result: VerificationResult) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: result.isValid ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(result.isValid ? .green : .red)

            Text(result.isValid ? "Signature Valid" : "Signature Invalid")
                .font(.title)
                .fontWeight(.semibold)

            Text(result.message)
                .foregroundStyle(.secondary)

            if let signer = result.signerKey {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Signed by", systemImage: "person.fill")
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
                Text("Signed on \(date.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let originalMessage = result.originalMessage {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Original Message", systemImage: "doc.text")
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

    private var canVerify: Bool {
        switch sessionState.verifyInputMode {
        case .text:
            if sessionState.verifySignatureMode == .inline {
                return !sessionState.verifyInputText.isEmpty
            } else {
                return !sessionState.verifyInputText.isEmpty && !sessionState.verifySignatureText.isEmpty
            }
        case .file:
            if sessionState.verifySignatureMode == .inline {
                return sessionState.verifySelectedFile != nil
            } else {
                return sessionState.verifySelectedFile != nil && sessionState.verifySelectedSignatureFile != nil
            }
        }
    }

    private func verify() {
        isProcessing = true
        sessionState.verifyResult = nil
        errorMessage = nil

        Task {
            do {
                let result: VerificationResult

                switch sessionState.verifyInputMode {
                case .text:
                    if sessionState.verifySignatureMode == .inline {
                        result = try signingService.verify(message: sessionState.verifyInputText)
                    } else {
                        result = try signingService.verify(message: sessionState.verifyInputText, signature: sessionState.verifySignatureText)
                    }

                case .file:
                    guard let fileURL = sessionState.verifySelectedFile else { return }
                    if sessionState.verifySignatureMode == .inline {
                        result = try signingService.verify(file: fileURL)
                    } else {
                        result = try signingService.verify(file: fileURL, signatureFile: sessionState.verifySelectedSignatureFile)
                    }
                }

                await MainActor.run {
                    sessionState.verifyResult = result
                }
            } catch {
                await MainActor.run {
                    sessionState.verifyResult = .invalid(reason: error.localizedDescription)
                }
            }

            await MainActor.run {
                isProcessing = false
            }
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
