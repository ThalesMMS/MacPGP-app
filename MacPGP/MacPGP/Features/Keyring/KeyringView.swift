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
        .navigationTitle("sidebar.keyring")
        // Constrain the split-view content column itself (a plain .frame on the
        // column content is not enforced as the column's resizable minimum). The
        // minimum fits the toolbar's packed controls — Filter (130) + the
        // "Search Keyserver" button (~150) + Sort (90) plus inter-control spacing
        // and the row's horizontal padding — so none of them collapse or truncate
        // on narrow windows.
        .navigationSplitViewColumnWidth(min: 440, ideal: 480, max: 620)
    }

    @ViewBuilder
    private func keyListContent(viewModel: KeyringViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            if keyringService.keys.isEmpty {
                // No keys at all: show one empty state centered in the whole
                // column. The Filter/Search/Sort toolbar is intentionally hidden
                // here — it has nothing to act on, and keeping it left the
                // centered content stranded below a large empty gap.
                emptyKeyringView
            } else {
                toolbar(viewModel: viewModel)

                if viewModel.filteredKeys.isEmpty {
                    noMatchesView(viewModel: viewModel)
                } else {
                    keyList(viewModel: viewModel)
                }
            }
        }
        .searchable(text: $vm.searchText, prompt: "Search keys...")
        .confirmationDialog(
            "keyring.delete_key",
            isPresented: $vm.showingDeleteConfirmation,
            presenting: viewModel.keyToDelete
        ) { key in
            Button("keydetails.delete", role: .destructive) {
                viewModel.deleteKey()
                if selectedKey?.id == key.id {
                    selectedKey = nil
                }
            }
            Button("keygen.cancel", role: .cancel) {}
        } message: { key in
            Text(String.localizedStringWithFormat(NSLocalizedString("keydetails.confirm_delete_format", comment: ""), key.displayName))
        }
        .alert("Error", isPresented: $vm.showingAlert) {
            Button("common.ok") {}
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

    /// Shown when the keyring holds no keys at all. Fills the column so the
    /// content sits centered the way the detail pane's placeholder does, rather
    /// than floating below the toolbar with a large empty gap above it.
    @ViewBuilder
    private var emptyKeyringView: some View {
        ContentUnavailableView {
            Label("keyring.no_keys", systemImage: "key")
        } description: {
            Text("keyring.no_keys_message")
        } actions: {
            VStack(spacing: 10) {
                Button {
                    NotificationCenter.default.post(name: .showKeyGeneration, object: nil)
                } label: {
                    Text("keyring.generate_new_key")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    NotificationCenter.default.post(name: .importKey, object: nil)
                } label: {
                    Text("keyring.import_key")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    showingKeyserverSearch = true
                } label: {
                    Text("keyring.search_keyserver")
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shown when the keyring has keys but the active search or filter matches
    /// none. The toolbar stays visible so the filter can be cleared.
    @ViewBuilder
    private func noMatchesView(viewModel: KeyringViewModel) -> some View {
        ContentUnavailableView {
            Label("keyring.no_results", systemImage: "magnifyingglass")
        } description: {
            Text("keyring.no_keys_match_your_search_or_filter")
        } actions: {
            Button("keyring.clear_filters") {
                viewModel.searchText = ""
                viewModel.filterType = .all
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        Button("keyring.copy_key_id") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(key.shortKeyID, forType: .string)
        }

        Button("keyring.copy_fingerprint") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(key.fingerprint, forType: .string)
        }

        Divider()

        Button("keyring.export_public_key") {
            exportKey(key, includeSecret: false, viewModel: viewModel)
        }

        if key.isSecretKey {
            Button("keyring.export_secret_key") {
                exportKey(key, includeSecret: true, viewModel: viewModel)
            }
        }

        Divider()

        Button("keyring.upload_to_keyserver") {
            uploadKey(key, viewModel: viewModel)
        }
        .disabled(isUploading)

        Button("keyring.refresh_from_keyserver") {
            refreshKey(key, viewModel: viewModel)
        }
        .disabled(isRefreshing)

        Divider()

        Button("menu.backup_keys") {
            showingBackupWizard = true
        }

        if key.isSecretKey {
            Button("keyring.paper_backup") {
                paperKeyContext = key
                showingPaperKey = true
            }
        }

        Button("menu.restore_keys") {
            showingRestoreWizard = true
        }

        Divider()

        Button("keyring.delete_key", role: .destructive) {
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

                let defaultServer = KeyServerConfig.defaultServer()

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
                let defaultServer = KeyServerConfig.defaultServer()

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
