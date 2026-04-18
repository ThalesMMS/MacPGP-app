import SwiftUI

struct SignView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(SessionStateManager.self) private var sessionState
    @State private var passphrase = ""
    @State private var showingPassphrasePrompt = false
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
            outputPane
        }
        .navigationTitle("Sign")
        .toolbar {
            ToolbarItemGroup {
                Picker("Mode", selection: $state.signInputMode) {
                    Text("Text").tag(InputMode.text)
                    Text("File").tag(InputMode.file)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                if sessionState.signInputMode == .text {
                    Toggle("Cleartext", isOn: $state.signCleartextSignature)
                        .disabled(sessionState.signDetachedSignature)
                }
                Toggle("Detached", isOn: $state.signDetachedSignature)
                Toggle("Armor", isOn: $state.signArmorOutput)

                Button {
                    promptForPassphrase()
                } label: {
                    Label("Sign", systemImage: "signature")
                }
                .disabled(!canSign || isProcessing)
            }
        }
        .alert("Passphrase Required", isPresented: $showingPassphrasePrompt) {
            SecureField("Passphrase", text: $passphrase)
            Button("Cancel", role: .cancel) {
                passphrase = ""
            }
            Button("Sign") {
                sign()
            }
        } message: {
            if let key = sessionState.signSignerKey {
                Text("Enter passphrase for \(key.displayName)")
            } else {
                Text("Enter passphrase to sign")
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
            Text("Signing Key")
                .font(.headline)

            if keyringService.secretKeys().isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("No secret keys available for signing")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Picker("Select Key", selection: $state.signSignerKey) {
                    Text("Select a key...").tag(nil as PGPKeyModel?)
                    ForEach(keyringService.secretKeys()) { key in
                        HStack {
                            Text(key.displayName)
                            if let email = key.email {
                                Text("(\(email))")
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
                Text("Message to Sign")
                    .font(.headline)

                Spacer()

                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
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

        return VStack(alignment: .leading, spacing: 8) {
            Text("File to Sign")
                .font(.headline)

            if let file = sessionState.signSelectedFile {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                    Text(file.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Button("Remove") {
                        sessionState.signSelectedFile = nil
                    }
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                DropZone(fileURL: $state.signSelectedFile)
            }
        }
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
                        Label("Reveal", systemImage: "folder")
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
                Spacer()
                ProgressView("Signing...")
                Spacer()
            } else if sessionState.signOutputText.isEmpty && sessionState.signOutputFiles.isEmpty {
                ContentUnavailableView(
                    "No Output",
                    systemImage: "signature",
                    description: Text(outputPlaceholderDescription)
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

    private var canSign: Bool {
        sessionState.signSignerKey != nil && (
            (sessionState.signInputMode == .text && !sessionState.signInputText.isEmpty) ||
            (sessionState.signInputMode == .file && sessionState.signSelectedFile != nil)
        )
    }

    private var outputTitle: String {
        if sessionState.signInputMode == .file {
            return sessionState.signDetachedSignature ? "Signature File" : "Signed File"
        }

        return sessionState.signDetachedSignature ? "Signature" : "Signed Message"
    }

    private var outputPlaceholderDescription: String {
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

    private func promptForPassphrase() {
        guard !isProcessing else { return }

        guard sessionState.signSignerKey != nil else {
            errorMessage = "Please select a signing key"
            showingError = true
            return
        }
        showingPassphrasePrompt = true
    }

    private func sign() {
        guard !isProcessing else { return }

        guard !passphrase.isEmpty else {
            errorMessage = "Passphrase is required"
            showingError = true
            return
        }

        guard let key = sessionState.signSignerKey else { return }

        let inputMode = sessionState.signInputMode
        let inputText = sessionState.signInputText
        let selectedFile = sessionState.signSelectedFile
        let cleartextSignature = sessionState.signCleartextSignature
        let detachedSignature = sessionState.signDetachedSignature
        let armorOutput = sessionState.signArmorOutput
        let enteredPassphrase = passphrase

        if inputMode == .file && selectedFile == nil {
            errorMessage = "Please select a file to sign"
            showingError = true
            return
        }

        isProcessing = true
        errorMessage = nil
        sessionState.signOutputText = ""
        sessionState.signOutputFiles = []

        Task {
            do {
                switch inputMode {
                case .text:
                    let signed = try await signingService.signAsync(
                        message: inputText,
                        using: key,
                        passphrase: enteredPassphrase,
                        cleartext: cleartextSignature,
                        detached: detachedSignature,
                        armored: armorOutput
                    )

                    await MainActor.run {
                        sessionState.signOutputFiles = []
                        sessionState.signOutputText = signed
                        passphrase = ""
                    }

                case .file:
                    guard let fileURL = selectedFile else {
                        throw OperationError.signingFailed(underlying: nil)
                    }

                    let outputURL = try await signingService.signAsync(
                        file: fileURL,
                        using: key,
                        passphrase: enteredPassphrase,
                        detached: detachedSignature,
                        armored: armorOutput
                    )

                    await MainActor.run {
                        sessionState.signOutputText = ""
                        sessionState.signOutputFiles = [outputURL]
                        passphrase = ""
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }

            await MainActor.run {
                isProcessing = false
            }
        }
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
