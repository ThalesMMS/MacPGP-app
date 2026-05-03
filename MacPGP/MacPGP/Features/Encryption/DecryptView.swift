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
                    viewModel?.decryptFromClipboard()
                } label: {
                    Label("Decrypt from Clipboard", systemImage: "doc.on.clipboard.fill")
                }
                .disabled(!(viewModel?.canDecryptFromClipboard ?? false))

                Button {
                    viewModel?.requestPassphraseAndDecrypt(fromClipboard: false)
                } label: {
                    Label("Decrypt", systemImage: "lock.open.fill")
                }
                .disabled(!canDecrypt || viewModel?.isProcessing == true)
            }
        }
        .alert("Passphrase Required", isPresented: Binding(
            get: { viewModel?.showingPassphrasePrompt ?? false },
            set: { viewModel?.showingPassphrasePrompt = $0 }
        )) {
            SecureField("Passphrase", text: Binding(
                get: { viewModel?.passphrase ?? "" },
                set: { viewModel?.passphrase = $0 }
            ))
            Button("Cancel", role: .cancel) {
                viewModel?.cancelPassphrasePrompt()
            }
            Button("Decrypt") {
                viewModel?.didSubmitPassphrase()
            }
        } message: {
            if let key = viewModel?.passphrasePromptKey {
                Text("Enter passphrase for \(key.displayName)")
            } else {
                Text("Enter passphrase to decrypt")
            }
        }
        .alert(
            viewModel?.alert?.title ?? "Error",
            isPresented: Binding(
                get: { viewModel?.showingAlert ?? false },
                set: { viewModel?.showingAlert = $0 }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(viewModel?.alert?.message ?? "An error occurred")
        }
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
                    viewModel?.pasteFromClipboard()
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
                Text("Encrypted Files")
                    .font(.headline)

                if !sessionState.decryptSelectedFiles.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(sessionState.decryptSelectedFiles.enumerated()), id: \.offset) { index, file in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.secondary)
                                Text(file.lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                                Button("Remove") {
                                    sessionState.decryptSelectedFiles.remove(at: index)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding()
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                } else {
                    DropZone(fileURLs: $state.decryptSelectedFiles)
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
                            viewModel?.requestChoosingOutputLocation()
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Button {
                        viewModel?.requestChoosingOutputLocation()
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
                Spacer()
                VStack(spacing: 16) {
                    if sessionState.decryptInputMode == .file && sessionState.decryptionProgress > 0 {
                        let fileCount = sessionState.decryptSelectedFiles.count
                        let progressText = fileCount > 1 ? "Decrypting files..." : "Decrypting file..."
                        ProgressView(value: sessionState.decryptionProgress) {
                            Text(progressText)
                        } currentValueLabel: {
                            Text("\(Int(sessionState.decryptionProgress * 100))%")
                        }
                        .frame(width: 200)
                    } else {
                        ProgressView("Decrypting...")
                    }
                }
                Spacer()
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
