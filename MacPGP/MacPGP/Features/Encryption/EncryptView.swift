import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EncryptView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(SessionStateManager.self) private var sessionState
    @Environment(NotificationService.self) private var notificationService

    @State private var viewModel: EncryptViewModel? = nil

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
                    viewModel?.encryptFromClipboard()
                } label: {
                    Label("Encrypt from Clipboard", systemImage: "doc.on.clipboard.fill")
                }
                .disabled(!(viewModel?.canEncryptFromClipboard ?? false))

                Button {
                    viewModel?.encrypt()
                } label: {
                    Label("Encrypt", systemImage: "lock.fill")
                }
                .disabled(!canEncrypt)
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
            Button("Encrypt") {
                viewModel?.didSubmitPassphrase()
            }
        } message: {
            Text("Enter passphrase for signing key")
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
        .onAppear {
            if viewModel == nil {
                viewModel = EncryptViewModel(
                    keyringService: keyringService,
                    sessionState: sessionState,
                    notificationService: notificationService
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel?.requestOutputFolderPicker ?? false },
            set: { viewModel?.requestOutputFolderPicker = $0 }
        )) {
            outputFolderPickerSheet
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
                ForEach(keyringService.signingKeys()) { key in
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
                Text("Encrypted Output")
                    .font(.headline)
                Spacer()

                if !sessionState.encryptOutputFiles.isEmpty {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(sessionState.encryptOutputFiles)
                    } label: {
                        Label(sessionState.encryptOutputFiles.count == 1 ? "Reveal" : "Reveal All", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                }

                if !sessionState.encryptOutputText.isEmpty || !sessionState.encryptOutputFiles.isEmpty {
                    Button {
                        viewModel?.copyOutputToClipboard()
                    } label: {
                        Label(sessionState.encryptOutputFiles.isEmpty ? "Copy" : "Copy Paths", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if viewModel?.isProcessing == true {
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
            } else if sessionState.encryptOutputText.isEmpty && sessionState.encryptOutputFiles.isEmpty {
                ContentUnavailableView(
                    "No Output",
                    systemImage: "lock.open",
                    description: Text(sessionState.encryptInputMode == .file ? "Encrypted files will appear here" : "Encrypted message will appear here")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !sessionState.encryptOutputFiles.isEmpty {
                FileResultListView(files: sessionState.encryptOutputFiles, successTitle: "Encrypted Files")
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


    private var outputFolderPickerSheet: some View {
        VStack(spacing: 16) {
            Text("Choose Output Folder")
                .font(.headline)

            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canCreateDirectories = true
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.prompt = "Choose Output Folder"
                panel.message = "Select where encrypted files will be saved"

                if panel.runModal() == .OK {
                    viewModel?.didChooseOutputLocation(panel.url)
                } else {
                    viewModel?.didChooseOutputLocation(nil)
                }
            }

            Button("Cancel", role: .cancel) {
                viewModel?.didChooseOutputLocation(nil)
            }
        }
        .padding()
        .frame(width: 360)
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
        .environment(NotificationService())
        .frame(width: 800, height: 600)
}
