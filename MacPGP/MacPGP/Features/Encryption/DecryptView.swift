import SwiftUI

struct DecryptView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(SessionStateManager.self) private var sessionState
    @State private var passphrase = ""
    @State private var showingPassphrasePrompt = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private var encryptionService: EncryptionService {
        EncryptionService(keyringService: keyringService)
    }

    var body: some View {
        @Bindable var state = sessionState

        HSplitView {
            inputPane
            outputPane
        }
        .navigationTitle("Decrypt")
        .toolbar {
            ToolbarItemGroup {
                Picker("Mode", selection: $state.decryptInputMode) {
                    Text("Text").tag(InputMode.text)
                    Text("File").tag(InputMode.file)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Button {
                    promptForPassphrase()
                } label: {
                    Label("Decrypt", systemImage: "lock.open.fill")
                }
                .disabled(!canDecrypt)
            }
        }
        .alert("Passphrase Required", isPresented: $showingPassphrasePrompt) {
            SecureField("Passphrase", text: $passphrase)
            Button("Cancel", role: .cancel) {
                passphrase = ""
            }
            Button("Decrypt") {
                decrypt()
            }
        } message: {
            if let key = sessionState.decryptSelectedKey {
                Text("Enter passphrase for \(key.displayName)")
            } else {
                Text("Enter passphrase to decrypt")
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

            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 300, idealWidth: 400, maxWidth: 500)
    }

    private var keySelectionSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Decryption Key")
                    .font(.headline)

                Spacer()

                Toggle("Auto-detect", isOn: $state.decryptAutoDetectKey)
                    .toggleStyle(.checkbox)
            }

            if !sessionState.decryptAutoDetectKey {
                Picker("Select Key", selection: $state.decryptSelectedKey) {
                    Text("Select a key...").tag(nil as PGPKeyModel?)
                    ForEach(keyringService.secretKeys()) { key in
                        Text(key.displayName).tag(key as PGPKeyModel?)
                    }
                }
                .labelsHidden()
            } else {
                Text("Will try all available secret keys")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if keyringService.secretKeys().isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("No secret keys available for decryption")
                        .font(.caption)
                }
            }
        }
    }

    private var textInputSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Encrypted Message")
                    .font(.headline)

                Spacer()

                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
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

        return VStack(alignment: .leading, spacing: 8) {
            Text("Encrypted File")
                .font(.headline)

            if let file = sessionState.decryptSelectedFile {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                    Text(file.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Button("Remove") {
                        sessionState.decryptSelectedFile = nil
                    }
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                DropZone(fileURL: $state.decryptSelectedFile)
            }
        }
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Decrypted Output")
                    .font(.headline)
                Spacer()

                if !sessionState.decryptOutputText.isEmpty {
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
                ProgressView("Decrypting...")
                Spacer()
            } else if sessionState.decryptOutputText.isEmpty {
                ContentUnavailableView(
                    "No Output",
                    systemImage: "lock.fill",
                    description: Text("Decrypted message will appear here")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        !keyringService.secretKeys().isEmpty && (
            (sessionState.decryptInputMode == .text && !sessionState.decryptInputText.isEmpty) ||
            (sessionState.decryptInputMode == .file && sessionState.decryptSelectedFile != nil)
        )
    }

    private func promptForPassphrase() {
        if !sessionState.decryptAutoDetectKey && sessionState.decryptSelectedKey == nil {
            errorMessage = "Please select a decryption key"
            showingError = true
            return
        }
        showingPassphrasePrompt = true
    }

    private func decrypt() {
        guard !passphrase.isEmpty else {
            errorMessage = "Passphrase is required"
            showingError = true
            return
        }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                switch sessionState.decryptInputMode {
                case .text:
                    guard let data = sessionState.decryptInputText.data(using: .utf8) else {
                        throw OperationError.decryptionFailed(underlying: nil)
                    }

                    let result: String
                    if sessionState.decryptAutoDetectKey {
                        let (decryptedData, _) = try encryptionService.tryDecrypt(
                            data: data,
                            passphrase: passphrase
                        )
                        result = String(data: decryptedData, encoding: .utf8) ?? ""
                    } else if let key = sessionState.decryptSelectedKey {
                        result = try encryptionService.decrypt(
                            message: sessionState.decryptInputText,
                            using: key,
                            passphrase: passphrase
                        )
                    } else {
                        throw OperationError.keyNotFound(keyID: "")
                    }

                    await MainActor.run {
                        sessionState.decryptOutputText = result
                    }

                case .file:
                    guard let fileURL = sessionState.decryptSelectedFile else { return }
                    guard let key = sessionState.decryptAutoDetectKey ? keyringService.secretKeys().first : sessionState.decryptSelectedKey else {
                        throw OperationError.noSecretKey
                    }

                    let outputURL = try encryptionService.decrypt(
                        file: fileURL,
                        using: key,
                        passphrase: passphrase
                    )

                    await MainActor.run {
                        sessionState.decryptOutputText = "File decrypted successfully:\n\(outputURL.path)"
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
            sessionState.decryptInputText = string
        }
    }

    private func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sessionState.decryptOutputText, forType: .string)
    }
}

#Preview {
    DecryptView()
        .environment(KeyringService())
        .environment(SessionStateManager())
        .frame(width: 800, height: 600)
}
