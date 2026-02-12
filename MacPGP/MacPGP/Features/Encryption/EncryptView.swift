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
    @State private var notificationService = NotificationService()

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
                    encryptFromClipboard()
                } label: {
                    Label("Encrypt from Clipboard", systemImage: "doc.on.clipboard.fill")
                }
                .disabled(!canEncryptFromClipboard)

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
            .layoutPriority(1)

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
                Text("Files")
                    .font(.headline)

                if !sessionState.encryptSelectedFiles.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(sessionState.encryptSelectedFiles.enumerated()), id: \.offset) { index, file in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.secondary)
                                Text(file.lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                                Button("Remove") {
                                    sessionState.encryptSelectedFiles.remove(at: index)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding()
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                } else {
                    DropZone(fileURLs: $state.encryptSelectedFiles)
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
                        let fileCount = sessionState.encryptSelectedFiles.count
                        let progressText = fileCount > 1 ? "Encrypting files..." : "Encrypting file..."
                        ProgressView(value: sessionState.encryptionProgress) {
                            Text(progressText)
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
            (sessionState.encryptInputMode == .file && !sessionState.encryptSelectedFiles.isEmpty)
        )
    }

    private var canEncryptFromClipboard: Bool {
        // Only available in text mode with recipients selected
        sessionState.encryptInputMode == .text &&
        !sessionState.encryptSelectedRecipients.isEmpty &&
        NSPasteboard.general.string(forType: .string) != nil
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
                    guard !sessionState.encryptSelectedFiles.isEmpty else { return }

                    var outputPaths: [String] = []
                    let fileCount = sessionState.encryptSelectedFiles.count

                    for (index, fileURL) in sessionState.encryptSelectedFiles.enumerated() {
                        // Update progress for current file
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
                                // Calculate overall progress: (completed files + current file progress) / total files
                                let overallProgress = (Double(index) + progress) / Double(fileCount)
                                sessionState.encryptionProgress = overallProgress
                            }
                        )

                        outputPaths.append(outputURL.path)
                    }

                    await MainActor.run {
                        if outputPaths.count == 1 {
                            sessionState.encryptOutputText = "File encrypted successfully:\n\(outputPaths[0])"
                        } else {
                            sessionState.encryptOutputText = "Files encrypted successfully (\(outputPaths.count)):\n" + outputPaths.map { "• \($0)" }.joined(separator: "\n")
                        }
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

    private func encryptFromClipboard() {
        // Read text from clipboard
        guard let clipboardText = NSPasteboard.general.string(forType: .string),
              !clipboardText.isEmpty else {
            errorMessage = "Clipboard is empty or does not contain text"
            showingError = true
            return
        }

        // Check if signing key requires passphrase
        if sessionState.encryptSignerKey != nil && passphrase.isEmpty {
            showingPassphrasePrompt = true
            return
        }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                let recipients = Array(sessionState.encryptSelectedRecipients)

                // Encrypt the clipboard text
                let encrypted = try encryptionService.encrypt(
                    message: clipboardText,
                    for: recipients,
                    signedBy: sessionState.encryptSignerKey,
                    passphrase: passphrase.isEmpty ? nil : passphrase,
                    armored: sessionState.encryptArmorOutput
                )

                // Write encrypted text back to clipboard
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(encrypted, forType: .string)

                    // Show success notification
                    notificationService.showSuccess(
                        title: "Encryption Successful",
                        message: "Clipboard contents have been encrypted"
                    )

                    // Update output pane to show what was encrypted
                    sessionState.encryptOutputText = encrypted
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

    private func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sessionState.encryptOutputText, forType: .string)
    }

    private func chooseOutputLocation() {
        let panel = NSOpenPanel()
        panel.canCreateDirectories = true
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Choose Output Folder"
        panel.message = "Select where encrypted files will be saved"

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
    private var multipleFiles: Binding<[URL]>?
    private var singleFile: Binding<URL?>?
    private var allowsMultiple: Bool

    @State private var isTargeted = false

    // Initializer for multiple files
    init(fileURLs: Binding<[URL]>) {
        self.multipleFiles = fileURLs
        self.singleFile = nil
        self.allowsMultiple = true
    }

    // Initializer for single file (backward compatibility)
    init(fileURL: Binding<URL?>) {
        self.multipleFiles = nil
        self.singleFile = fileURL
        self.allowsMultiple = false
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(allowsMultiple ? "Drop files here" : "Drop a file here")
                .font(.headline)

            Text("or")
                .foregroundStyle(.secondary)

            Button(allowsMultiple ? "Select Files..." : "Select File...") {
                selectFiles()
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
            guard !providers.isEmpty else { return false }

            if allowsMultiple {
                var loadedURLs: [URL] = []
                let group = DispatchGroup()

                for provider in providers {
                    group.enter()
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url {
                            loadedURLs.append(url)
                        }
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    self.multipleFiles?.wrappedValue.append(contentsOf: loadedURLs)
                }
            } else {
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.singleFile?.wrappedValue = url
                        }
                    }
                }
            }

            return true
        }
    }

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            if allowsMultiple {
                multipleFiles?.wrappedValue.append(contentsOf: panel.urls)
            } else {
                singleFile?.wrappedValue = panel.url
            }
        }
    }
}

#Preview {
    let keyringService = KeyringService()
    let trustService = TrustService(keyringService: keyringService)

    return EncryptView()
        .environment(keyringService)
        .environment(SessionStateManager())
        .environment(trustService)
        .frame(width: 800, height: 600)
}
