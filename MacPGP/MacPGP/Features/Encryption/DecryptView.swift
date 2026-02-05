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
                    startDecryption()
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

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Output Location")
                    .font(.headline)

                if let location = sessionState.decryptOutputLocation {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                        Text(location.path)
                            .lineLimit(1)
                            .font(.caption)
                        Spacer()
                        Button("Change") {
                            chooseOutputLocation()
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Button {
                        chooseOutputLocation()
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                            Text("Choose Output Location")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.bordered)
                }
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
                VStack(spacing: 16) {
                    if sessionState.decryptInputMode == .file && sessionState.decryptionProgress > 0 {
                        ProgressView(value: sessionState.decryptionProgress) {
                            Text("Decrypting file...")
                        } currentValueLabel: {
                            Text("\(Int(sessionState.decryptionProgress * 100))%")
                        }
                        .frame(width: 200)
                    } else {
                        ProgressView("Decrypting...")
                    }
                }
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

    private func startDecryption() {
        if !sessionState.decryptAutoDetectKey && sessionState.decryptSelectedKey == nil {
            errorMessage = "Please select a decryption key"
            showingError = true
            return
        }

        // Try keychain first if a specific key is selected
        if !sessionState.decryptAutoDetectKey, let key = sessionState.decryptSelectedKey {
            if let storedPassphrase = try? KeychainManager.shared.retrievePassphrase(forKeyID: key.shortKeyID) {
                passphrase = storedPassphrase
                decrypt()
                return
            }
        }

        // If no keychain passphrase found or auto-detect is enabled, prompt
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

                    // Reset progress
                    await MainActor.run {
                        sessionState.decryptionProgress = 0.0
                    }

                    // Use async decrypt with progress callback
                    let outputURL = try await encryptionService.decryptAsync(
                        file: fileURL,
                        using: key,
                        passphrase: passphrase,
                        outputURL: sessionState.decryptOutputLocation,
                        progressCallback: { progress in
                            sessionState.decryptionProgress = progress
                        }
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
                sessionState.decryptionProgress = 0.0
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

    private func chooseOutputLocation() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "decrypted"

        if let inputFile = sessionState.decryptSelectedFile {
            let fileName = inputFile.lastPathComponent
            // Remove .gpg or .asc extension if present
            if fileName.hasSuffix(".gpg") {
                panel.nameFieldStringValue = String(fileName.dropLast(4))
            } else if fileName.hasSuffix(".asc") {
                panel.nameFieldStringValue = String(fileName.dropLast(4))
            } else {
                panel.nameFieldStringValue = inputFile.deletingPathExtension().lastPathComponent
            }
        }

        if panel.runModal() == .OK {
            sessionState.decryptOutputLocation = panel.url
        }
    }
}

#Preview {
    DecryptView()
        .environment(KeyringService())
        .environment(SessionStateManager())
        .frame(width: 800, height: 600)
}
