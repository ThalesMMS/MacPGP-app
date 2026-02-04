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
                .disabled(!canSign)
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
                Text(sessionState.signDetachedSignature ? "Signature" : "Signed Message")
                    .font(.headline)
                Spacer()

                if !sessionState.signOutputText.isEmpty {
                    Button {
                        copyOutput()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if isProcessing {
                Spacer()
                ProgressView("Signing...")
                Spacer()
            } else if sessionState.signOutputText.isEmpty {
                ContentUnavailableView(
                    "No Output",
                    systemImage: "signature",
                    description: Text(sessionState.signDetachedSignature ? "Signature will appear here" : "Signed message will appear here")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func promptForPassphrase() {
        guard sessionState.signSignerKey != nil else {
            errorMessage = "Please select a signing key"
            showingError = true
            return
        }
        showingPassphrasePrompt = true
    }

    private func sign() {
        guard !passphrase.isEmpty else {
            errorMessage = "Passphrase is required"
            showingError = true
            return
        }

        guard let key = sessionState.signSignerKey else { return }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                switch sessionState.signInputMode {
                case .text:
                    let signed = try signingService.sign(
                        message: sessionState.signInputText,
                        using: key,
                        passphrase: passphrase,
                        cleartext: sessionState.signCleartextSignature,
                        detached: sessionState.signDetachedSignature,
                        armored: sessionState.signArmorOutput
                    )

                    await MainActor.run {
                        sessionState.signOutputText = signed
                    }

                case .file:
                    guard let fileURL = sessionState.signSelectedFile else { return }
                    let outputURL = try signingService.sign(
                        file: fileURL,
                        using: key,
                        passphrase: passphrase,
                        detached: sessionState.signDetachedSignature,
                        armored: sessionState.signArmorOutput
                    )

                    await MainActor.run {
                        sessionState.signOutputText = "File signed successfully:\n\(outputURL.path)"
                    }
                }

                passphrase = ""
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
        NSPasteboard.general.setString(sessionState.signOutputText, forType: .string)
    }
}

#Preview {
    SignView()
        .environment(KeyringService())
        .environment(SessionStateManager())
        .frame(width: 800, height: 600)
}
