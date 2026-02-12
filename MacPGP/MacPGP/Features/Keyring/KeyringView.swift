import SwiftUI

struct KeyringView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(KeyServerService.self) private var keyServerService
    @Binding var selectedKey: PGPKeyModel?
    @State private var viewModel: KeyringViewModel?
    @State private var showingExportSheet = false
    @State private var exportData: Data?
    @State private var exportFileName: String = ""
    @State private var showingBackupWizard = false
    @State private var showingRestoreWizard = false
    @State private var showingPaperKey = false
    @State private var paperKeyContext: PGPKeyModel?
    @State private var showingKeyserverSearch = false
    @State private var isUploading = false
    @State private var isRefreshing = false

    var body: some View {
        Group {
            if let viewModel = viewModel {
                keyListContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = KeyringViewModel(keyringService: keyringService)
            }
        }
        .navigationTitle("Keyring")
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
    }

    @ViewBuilder
    private func keyListContent(viewModel: KeyringViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            toolbar(viewModel: viewModel)

            if viewModel.filteredKeys.isEmpty {
                emptyStateView(viewModel: viewModel)
            } else {
                keyList(viewModel: viewModel)
            }
        }
        .searchable(text: $vm.searchText, prompt: "Search keys...")
        .confirmationDialog(
            "Delete Key",
            isPresented: $vm.showingDeleteConfirmation,
            presenting: viewModel.keyToDelete
        ) { key in
            Button("Delete", role: .destructive) {
                viewModel.deleteKey()
                if selectedKey?.id == key.id {
                    selectedKey = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { key in
            Text("Are you sure you want to delete \"\(key.displayName)\"? This action cannot be undone.")
        }
        .alert("Error", isPresented: $vm.showingAlert) {
            Button("OK") {}
        } message: {
            Text(viewModel.alertMessage ?? "An error occurred")
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: PGPKeyDocument(data: exportData ?? Data()),
            contentType: .data,
            defaultFilename: exportFileName
        ) { result in
            if case .failure(let error) = result {
                viewModel.alertMessage = "Export failed: \(error.localizedDescription)"
                viewModel.showingAlert = true
            }
        }
        .sheet(isPresented: $showingBackupWizard) {
            BackupWizardView()
        }
        .sheet(isPresented: $showingRestoreWizard) {
            RestoreWizardView()
        }
        .sheet(isPresented: $showingPaperKey) {
            if let key = paperKeyContext {
                PaperKeyView(key: key)
            }
        }
        .sheet(isPresented: $showingKeyserverSearch) {
            KeyServerSearchView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showBackupWizard)) { _ in
            showingBackupWizard = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showRestoreWizard)) { _ in
            showingRestoreWizard = true
        }
    }

    @ViewBuilder
    private func toolbar(viewModel: KeyringViewModel) -> some View {
        @Bindable var vm = viewModel

        HStack {
            Picker(String(localized: "keyring.toolbar.filter", defaultValue: "Filter", comment: "Filter picker label"), selection: $vm.filterType) {
                ForEach(KeyFilterType.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 130)

            Button(action: { showingKeyserverSearch = true }) {
                Label(String(localized: "keyring.toolbar.search_keyserver", defaultValue: "Search Keyserver", comment: "Button to search key server"), systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderless)

            Spacer()

            Picker(String(localized: "keyring.toolbar.sort", defaultValue: "Sort", comment: "Sort picker label"), selection: $vm.sortOrder) {
                ForEach(KeySortOrder.allCases) { order in
                    Text(order.displayName).tag(order)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 90)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func emptyStateView(viewModel: KeyringViewModel) -> some View {
        ContentUnavailableView {
            Label("No Keys", systemImage: "key")
        } description: {
            if viewModel.searchText.isEmpty {
                Text("Generate a new key or import existing keys to get started.")
            } else {
                Text("No keys match your search.")
            }
        } actions: {
            if viewModel.searchText.isEmpty {
                Button("Generate New Key") {
                    NotificationCenter.default.post(name: .showKeyGeneration, object: nil)
                }
                .buttonStyle(.borderedProminent)

                Button("Import Key") {
                    NotificationCenter.default.post(name: .importKey, object: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func keyList(viewModel: KeyringViewModel) -> some View {
        List(selection: $selectedKey) {
            ForEach(viewModel.filteredKeys) { key in
                KeyRowView(key: key)
                    .tag(key)
                    .contextMenu {
                        keyContextMenu(for: key, viewModel: viewModel)
                    }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func keyContextMenu(for key: PGPKeyModel, viewModel: KeyringViewModel) -> some View {
        Button("Copy Key ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(key.shortKeyID, forType: .string)
        }

        Button("Copy Fingerprint") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(key.fingerprint, forType: .string)
        }

        Divider()

        Button("Export Public Key...") {
            exportKey(key, includeSecret: false, viewModel: viewModel)
        }

        if key.isSecretKey {
            Button("Export Secret Key...") {
                exportKey(key, includeSecret: true, viewModel: viewModel)
            }
        }

        Divider()

        Button("Upload to Keyserver...") {
            uploadKey(key, viewModel: viewModel)
        }
        .disabled(isUploading)

        Button("Refresh from Keyserver") {
            refreshKey(key, viewModel: viewModel)
        }
        .disabled(isRefreshing)

        Divider()

        Button("Backup Keys...") {
            showingBackupWizard = true
        }

        if key.isSecretKey {
            Button("Paper Backup...") {
                paperKeyContext = key
                showingPaperKey = true
            }
        }

        Button("Restore Keys...") {
            showingRestoreWizard = true
        }

        Divider()

        Button("Delete Key", role: .destructive) {
            viewModel.confirmDelete(key)
        }
    }

    private func exportKey(_ key: PGPKeyModel, includeSecret: Bool, viewModel: KeyringViewModel) {
        do {
            exportData = try viewModel.exportKey(key, includeSecret: includeSecret)
            let suffix = includeSecret ? "secret" : "public"
            exportFileName = "\(key.displayName.replacingOccurrences(of: " ", with: "_"))_\(suffix).asc"
            showingExportSheet = true
        } catch {
            viewModel.alertMessage = "Export failed: \(error.localizedDescription)"
            viewModel.showingAlert = true
        }
    }

    private func uploadKey(_ key: PGPKeyModel, viewModel: KeyringViewModel) {
        Task {
            isUploading = true
            defer { isUploading = false }

            do {
                // Always upload public key only (never upload secret keys)
                let publicKeyData = try viewModel.exportKey(key, includeSecret: false)

                // Use default keyserver (keys.openpgp.org)
                let defaultServer = KeyServerConfig.keysOpenpgp

                try await keyServerService.uploadKey(publicKeyData, to: defaultServer)

                // Show success message
                await MainActor.run {
                    viewModel.alertMessage = "Key uploaded successfully to \(defaultServer.name)"
                    viewModel.showingAlert = true
                }
            } catch {
                // Show error message
                await MainActor.run {
                    viewModel.alertMessage = "Upload failed: \(error.localizedDescription)"
                    viewModel.showingAlert = true
                }
            }
        }
    }

    private func refreshKey(_ key: PGPKeyModel, viewModel: KeyringViewModel) {
        Task {
            isRefreshing = true
            defer { isRefreshing = false }

            do {
                // Use default keyserver (keys.openpgp.org)
                let defaultServer = KeyServerConfig.keysOpenpgp

                let keyData = try await keyServerService.refreshKey(fingerprint: key.fingerprint, from: defaultServer)

                // Import the refreshed key
                _ = try await MainActor.run {
                    try keyringService.importKey(from: keyData)
                }

                // Show success message
                await MainActor.run {
                    viewModel.alertMessage = "Key refreshed successfully from \(defaultServer.name)"
                    viewModel.showingAlert = true
                }
            } catch {
                // Show error message
                await MainActor.run {
                    viewModel.alertMessage = "Refresh failed: \(error.localizedDescription)"
                    viewModel.showingAlert = true
                }
            }
        }
    }
}

struct PGPKeyDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

import UniformTypeIdentifiers

#Preview {
    KeyringView(selectedKey: .constant(nil))
        .environment(KeyringService())
        .environment(KeyServerService())
}
