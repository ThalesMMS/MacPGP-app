import SwiftUI

struct KeyServerSearchView: View {
    @Environment(KeyServerService.self) private var keyServerService
    @Environment(KeyringService.self) private var keyringService
    @Environment(\.dismiss) private var dismiss

    @State private var preferences = PreferencesManager.shared
    @State private var searchQuery = ""
    @State private var selectedServer = KeyServerConfig.defaultServer()
    @State private var searchResults: [KeySearchResult] = []
    @State private var selectedResult: KeySearchResult?
    @State private var isSearching = false
    @State private var activeSearchID: UUID?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isImporting = false

    private var enabledServers: [KeyServerConfig] {
        KeyServerConfig.enabledServers(using: preferences)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchToolbar

            Divider()

            if isSearching {
                loadingView
            } else if searchResults.isEmpty && !searchQuery.isEmpty {
                emptyStateView
            } else if !searchResults.isEmpty {
                resultsList
            } else {
                initialStateView
            }

            Divider()

            actionButtons
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear(perform: normalizeSelectedServer)
        .alert("Error", isPresented: $showingAlert) {
            Button("common.ok") {}
                .accessibilityIdentifier("Keyserver Error OK")
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var searchToolbar: some View {
        VStack(spacing: 12) {
            HStack {
                Text("keyring.search_keyserver")
                    .font(.headline)
                Spacer()
                Button("revocation.close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 12) {
                TextField("Enter email or key ID", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSearching)
                    .onSubmit {
                        performSearch()
                    }
                    .accessibilityIdentifier("Keyserver Search Field")

                Button(action: performSearch) {
                    Label("keyserver.search_button", systemImage: "magnifyingglass")
                }
                .disabled(searchQuery.isEmpty || isSearching)
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityIdentifier("Keyserver Search Button")
            }

            Picker("keyserver.server", selection: $selectedServer) {
                ForEach(enabledServers) { server in
                    Text(serverPickerLabel(for: server)).tag(server)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(isSearching)
            .accessibilityIdentifier("Keyserver Search Server Picker")
        }
        .padding()
    }

    // MARK: - Content Views

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("keyserver.searching")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var initialStateView: some View {
        ContentUnavailableView {
            Label("keyserver.search_message", systemImage: "magnifyingglass")
        } description: {
            Text(String.localizedStringWithFormat(NSLocalizedString("keyserver_search.prompt_format", comment: ""), selectedServer.name))
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("keyserver.no_keys_found", systemImage: "key.slash")
                .accessibilityIdentifier("Keyserver No Results")
        } description: {
            Text(String.localizedStringWithFormat(NSLocalizedString("keyserver_search.no_results_format", comment: ""), searchQuery, selectedServer.name))
        } actions: {
            if enabledServers.count > 1 {
                Button("keyserver.try_different_server") {
                    if let nextIndex = enabledServers.firstIndex(where: { $0.id == selectedServer.id }) {
                        let nextServerIndex = (nextIndex + 1) % enabledServers.count
                        selectedServer = enabledServers[nextServerIndex]
                    }
                    performSearch()
                }
            } else {
                Button("keyserver_search.search_again") {
                    performSearch()
                }
            }
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String.localizedStringWithFormat(NSLocalizedString("keyserver.keys_found", comment: "Number of public keys found on the keyserver"), searchResults.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            List(selection: $selectedResult) {
                ForEach(searchResults) { result in
                    KeySearchResultRow(result: result)
                        .tag(result)
                        .accessibilityIdentifier("Keyserver Result \(result.shortKeyID)")
                }
            }
            .listStyle(.inset)
            .accessibilityIdentifier("Keyserver Results List")
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            Spacer()

            Button("keygen.cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("keyserver.import") {
                importSelectedKey()
            }
            .disabled(selectedResult == nil || isImporting)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("Keyserver Import Button")
        }
        .padding()
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchQuery.isEmpty, !isSearching else { return }

        let searchID = UUID()
        let query = searchQuery
        let server = selectedServer
        activeSearchID = searchID
        isSearching = true
        searchResults = []
        selectedResult = nil

        Task {
            do {
                let results = try await keyServerService.search(query: query, on: server)
                await MainActor.run {
                    guard activeSearchID == searchID else { return }
                    searchResults = results
                    finishSearch(searchID)
                }
            } catch {
                await MainActor.run {
                    guard activeSearchID == searchID else { return }
                    finishSearch(searchID)
                    alertMessage = error.localizedDescription
                    showingAlert = true
                }
            }
        }
    }

    private func normalizeSelectedServer() {
        if !enabledServers.contains(selectedServer) {
            selectedServer = KeyServerConfig.defaultServer(using: preferences)
        }
    }

    /// Labels insecure (HKP/HTTP) servers in the picker so a plaintext endpoint is
    /// visually distinguishable wherever it can be selected.
    private func serverPickerLabel(for server: KeyServerConfig) -> String {
        guard server.requiresInsecureOptIn else { return server.name }
        return "\(server.name) (\(String(localized: "keyserver_settings.insecure_badge")))"
    }

    private func importSelectedKey() {
        guard let result = selectedResult, !isImporting else { return }

        let server = selectedServer
        isImporting = true
        Task {
            do {
                // Fetch the key and verify it matches the selected result's
                // fingerprint before importing, so a mismatched or substituted
                // server response cannot mutate the keyring.
                let keyData = try await keyServerService.fetchValidatedKey(matching: result.fingerprint, from: server)

                // Import the key into the keyring
                let importedKeys = try await MainActor.run {
                    try keyringService.importKey(from: keyData)
                }

                await MainActor.run {
                    isImporting = false

                    if !importedKeys.isEmpty {
                        // Success - dismiss the sheet
                        dismiss()
                    } else {
                        alertMessage = "Failed to import key"
                        showingAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    alertMessage = "Import failed: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }

    private func finishSearch(_ searchID: UUID) {
        guard activeSearchID == searchID else { return }
        isSearching = false
        activeSearchID = nil
    }
}

// MARK: - Key Search Result Row

struct KeySearchResultRow: View {
    let result: KeySearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.displayName)
                    .font(.headline)

                if result.isRevoked {
                    Label("key.revoked", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if result.userIDs.count > 1 {
                ForEach(result.userIDs.dropFirst(), id: \.self) { uid in
                    Text(uid)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Label(result.shortKeyID, systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(result.algorithm) \(result.keySize)", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let creationDate = result.creationDate {
                    Label(creationDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let expirationDate = result.expirationDate {
                    if expirationDate < Date() {
                        Label("key.expired", systemImage: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Label(String.localizedStringWithFormat(NSLocalizedString("keyserver_search.expires_format", comment: ""), expirationDate.formatted(date: .abbreviated, time: .omitted)), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    KeyServerSearchView()
        .environment(KeyServerService())
        .environment(KeyringService())
}
