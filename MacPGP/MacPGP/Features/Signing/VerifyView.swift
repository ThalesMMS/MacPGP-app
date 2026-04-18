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

    /// Renders a verification result panel showing the outcome and any associated details.
    /// - Parameter result: The `VerificationResult` whose outcome and metadata will be displayed.
    /// - Returns: A view presenting an outcome symbol, title, and message, plus optional signer information, signature date, and the original message when available.
    @ViewBuilder
    private func verificationResultView(_ result: VerificationResult) -> some View {
        let resultColor: Color = {
            switch result.outcome {
            case .valid:
                return .green
            case .invalidSignature:
                return .red
            case .error:
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

    /// Perform verification for the current input and update the session state with the result.
    /// 
    /// Begins an asynchronous verification using the current `sessionState` selections (text vs. file and inline vs. detached). Clears any prior result and sets `isProcessing` while verification runs. On success, sets `sessionState.verifyResult` to the produced `VerificationResult`. On failure, sets `sessionState.verifyResult` to `.verificationError(reason: error.localizedDescription)`. Resets `isProcessing` when finished.
    private func verify() {
        let inputMode = sessionState.verifyInputMode
        let signatureMode = sessionState.verifySignatureMode
        let inputText = sessionState.verifyInputText
        let signatureText = sessionState.verifySignatureText
        let selectedFile = sessionState.verifySelectedFile
        let selectedSignatureFile = sessionState.verifySelectedSignatureFile

        if inputMode == .file && selectedFile == nil {
            errorMessage = "Please select a file to verify"
            showingError = true
            return
        }

        if inputMode == .file && signatureMode == .detached && selectedSignatureFile == nil {
            errorMessage = "Please select a signature file"
            showingError = true
            return
        }

        isProcessing = true
        sessionState.verifyResult = nil
        errorMessage = nil

        Task {
            do {
                let result: VerificationResult

                switch inputMode {
                case .text:
                    if signatureMode == .inline {
                        result = try await signingService.verifyAsync(message: inputText)
                    } else {
                        result = try await signingService.verifyAsync(message: inputText, signature: signatureText)
                    }

                case .file:
                    guard let fileURL = selectedFile else {
                        throw OperationError.verificationFailed(underlying: nil)
                    }

                    if signatureMode == .inline {
                        result = try await signingService.verifyAsync(file: fileURL)
                    } else {
                        result = try await signingService.verifyAsync(file: fileURL, signatureFile: selectedSignatureFile)
                    }
                }

                await MainActor.run {
                    sessionState.verifyResult = result
                }
            } catch {
                await MainActor.run {
                    sessionState.verifyResult = .verificationError(reason: error.localizedDescription)
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
