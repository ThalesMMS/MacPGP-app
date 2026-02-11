import SwiftUI

struct KeyServerSearchView: View {
    @Environment(KeyServerService.self) private var keyServerService
    @Environment(KeyringService.self) private var keyringService
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var selectedServer = KeyServerConfig.keysOpenpgp
    @State private var searchResults: [KeySearchResult] = []
    @State private var selectedResult: KeySearchResult?
    @State private var isSearching = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isImporting = false

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
        .alert("Error", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var searchToolbar: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Search Keyserver")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 12) {
                TextField("Enter email or key ID", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        performSearch()
                    }

                Button(action: performSearch) {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .disabled(searchQuery.isEmpty || isSearching)
                .keyboardShortcut(.return, modifiers: [])
            }

            Picker("Server:", selection: $selectedServer) {
                ForEach(KeyServerConfig.defaults.filter { $0.isEnabled }) { server in
                    Text(server.name).tag(server)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding()
    }

    // MARK: - Content Views

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Searching keyserver...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var initialStateView: some View {
        ContentUnavailableView {
            Label("Search for Keys", systemImage: "magnifyingglass")
        } description: {
            Text("Enter an email address or key ID to search for public keys on \(selectedServer.name).")
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Keys Found", systemImage: "key.slash")
        } description: {
            Text("No keys matching \"\(searchQuery)\" were found on \(selectedServer.name).")
        } actions: {
            Button("Try Different Server") {
                // Cycle through available servers
                let enabledServers = KeyServerConfig.defaults.filter { $0.isEnabled }
                if let nextIndex = enabledServers.firstIndex(where: { $0.id == selectedServer.id }) {
                    let nextServerIndex = (nextIndex + 1) % enabledServers.count
                    selectedServer = enabledServers[nextServerIndex]
                }
                performSearch()
            }
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(searchResults.count) key\(searchResults.count == 1 ? "" : "s") found")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            List(selection: $selectedResult) {
                ForEach(searchResults) { result in
                    KeySearchResultRow(result: result)
                        .tag(result)
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Import") {
                importSelectedKey()
            }
            .disabled(selectedResult == nil || isImporting)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchQuery.isEmpty else { return }

        Task {
            isSearching = true
            searchResults = []
            selectedResult = nil

            do {
                let results = try await keyServerService.search(query: searchQuery, on: selectedServer)
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    alertMessage = error.localizedDescription
                    showingAlert = true
                }
            }
        }
    }

    private func importSelectedKey() {
        guard let result = selectedResult else { return }

        Task {
            isImporting = true

            do {
                // Fetch the full key data from the keyserver
                let keyData = try await keyServerService.fetchKey(fingerprint: result.fingerprint, from: selectedServer)

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
                    Label("Revoked", systemImage: "xmark.circle.fill")
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
                        Label("Expired", systemImage: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Label("Expires \(expirationDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "clock")
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
