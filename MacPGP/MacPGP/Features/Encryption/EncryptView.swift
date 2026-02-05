import SwiftUI
import UniformTypeIdentifiers

struct EncryptView: View {
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
        .navigationTitle("Encrypt")
        .toolbar {
            ToolbarItemGroup {
                Picker("Mode", selection: $state.encryptInputMode) {
                    Text("Text").tag(InputMode.text)
                    Text("File").tag(InputMode.file)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Toggle("Armor", isOn: $state.encryptArmorOutput)

                Button {
                    encrypt()
                } label: {
                    Label("Encrypt", systemImage: "lock.fill")
                }
                .disabled(!canEncrypt)
            }
        }
        .alert("Passphrase Required", isPresented: $showingPassphrasePrompt) {
            SecureField("Passphrase", text: $passphrase)
            Button("Cancel", role: .cancel) {
                passphrase = ""
            }
            Button("Encrypt") {
                encrypt()
            }
        } message: {
            Text("Enter passphrase for signing key")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An error occurred")
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

            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 300, idealWidth: 400, maxWidth: 500)
    }

    private var signerSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            Text("Sign with (optional)")
                .font(.headline)

            Picker("Signing Key", selection: $state.encryptSignerKey) {
                Text("Don't sign").tag(nil as PGPKeyModel?)
                ForEach(keyringService.secretKeys()) { key in
                    Text(key.displayName).tag(key as PGPKeyModel?)
                }
            }
            .labelsHidden()
        }
    }

    private var textInputSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 8) {
            Text("Message")
                .font(.headline)

            TextEditor(text: $state.encryptInputText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 150)
                .border(Color(nsColor: .separatorColor))
        }
    }

    private var fileInputSection: some View {
        @Bindable var state = sessionState

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("File")
                    .font(.headline)

                if let file = sessionState.encryptSelectedFile {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.secondary)
                        Text(file.lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        Button("Remove") {
                            sessionState.encryptSelectedFile = nil
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    DropZone(fileURL: $state.encryptSelectedFile)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Output Location")
                    .font(.headline)

                if let location = sessionState.encryptOutputLocation {
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
                Text("Encrypted Output")
                    .font(.headline)
                Spacer()

                if !sessionState.encryptOutputText.isEmpty {
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
                    if sessionState.encryptInputMode == .file && sessionState.encryptionProgress > 0 {
                        ProgressView(value: sessionState.encryptionProgress) {
                            Text("Encrypting file...")
                        } currentValueLabel: {
                            Text("\(Int(sessionState.encryptionProgress * 100))%")
                        }
                        .frame(width: 200)
                    } else {
                        ProgressView("Encrypting...")
                    }
                }
                Spacer()
            } else if sessionState.encryptOutputText.isEmpty {
                ContentUnavailableView(
                    "No Output",
                    systemImage: "lock.open",
                    description: Text("Encrypted message will appear here")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        !sessionState.encryptSelectedRecipients.isEmpty && (
            (sessionState.encryptInputMode == .text && !sessionState.encryptInputText.isEmpty) ||
            (sessionState.encryptInputMode == .file && sessionState.encryptSelectedFile != nil)
        )
    }

    private func encrypt() {
        if sessionState.encryptSignerKey != nil && passphrase.isEmpty {
            showingPassphrasePrompt = true
            return
        }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                let recipients = Array(sessionState.encryptSelectedRecipients)

                switch sessionState.encryptInputMode {
                case .text:
                    let encrypted = try encryptionService.encrypt(
                        message: sessionState.encryptInputText,
                        for: recipients,
                        signedBy: sessionState.encryptSignerKey,
                        passphrase: passphrase.isEmpty ? nil : passphrase,
                        armored: sessionState.encryptArmorOutput
                    )
                    await MainActor.run {
                        sessionState.encryptOutputText = encrypted
                    }

                case .file:
                    guard let fileURL = sessionState.encryptSelectedFile else { return }

                    // Reset progress
                    await MainActor.run {
                        sessionState.encryptionProgress = 0.0
                    }

                    // Use async encrypt with progress callback
                    let outputURL = try await encryptionService.encryptAsync(
                        file: fileURL,
                        for: recipients,
                        signedBy: sessionState.encryptSignerKey,
                        passphrase: passphrase.isEmpty ? nil : passphrase,
                        outputURL: sessionState.encryptOutputLocation,
                        armored: sessionState.encryptArmorOutput,
                        progressCallback: { progress in
                            sessionState.encryptionProgress = progress
                        }
                    )

                    await MainActor.run {
                        sessionState.encryptOutputText = "File encrypted successfully:\n\(outputURL.path)"
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
                sessionState.encryptionProgress = 0.0
            }
        }
    }

    private func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sessionState.encryptOutputText, forType: .string)
    }

    private func chooseOutputLocation() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sessionState.encryptSelectedFile?.lastPathComponent ?? "encrypted"

        if let inputFile = sessionState.encryptSelectedFile {
            let fileName = inputFile.deletingPathExtension().lastPathComponent
            let fileExtension = sessionState.encryptArmorOutput ? "asc" : "gpg"
            panel.nameFieldStringValue = "\(fileName).\(fileExtension)"
        }

        if panel.runModal() == .OK {
            sessionState.encryptOutputLocation = panel.url
        }
    }
}

enum InputMode: String, CaseIterable {
    case text
    case file
}

struct DropZone: View {
    @Binding var fileURL: URL?
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Drop a file here")
                .font(.headline)

            Text("or")
                .foregroundStyle(.secondary)

            Button("Select File...") {
                selectFile()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .foregroundStyle(isTargeted ? .blue : .secondary.opacity(0.5))
        )
        .background(isTargeted ? Color.blue.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    DispatchQueue.main.async {
                        self.fileURL = url
                    }
                }
            }
            return true
        }
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            fileURL = panel.url
        }
    }
}

#Preview {
    EncryptView()
        .environment(KeyringService())
        .environment(SessionStateManager())
        .frame(width: 800, height: 600)
}
