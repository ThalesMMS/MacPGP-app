import SwiftUI
import UniformTypeIdentifiers

struct KeyDetailsView: View {
    let key: PGPKeyModel
    @Environment(KeyringService.self) private var keyringService
    @State private var showingExportSheet = false
    @State private var exportData: Data?
    @State private var exportFileName: String = ""
    @State private var showingDeleteConfirmation = false
    @State private var alertMessage: String?
    @State private var showingAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                Divider()
                keyInfoSection
                Divider()
                KeyFingerprintView(fingerprint: key.fingerprint)
                Divider()
                userIDsSection

                if key.isExpired {
                    Divider()
                    expirationWarning
                }
            }
            .padding(24)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(minWidth: 350, maxWidth: .infinity)
        .navigationTitle(key.displayName)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Export Public Key...") {
                        exportKey(includeSecret: false)
                    }

                    if key.isSecretKey {
                        Button("Export Secret Key...") {
                            exportKey(includeSecret: true)
                        }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete Key",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                deleteKey()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(key.displayName)\"? This action cannot be undone.")
        }
        .alert("Error", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "An error occurred")
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: PGPKeyDocument(data: exportData ?? Data()),
            contentType: .data,
            defaultFilename: exportFileName
        ) { result in
            if case .failure(let error) = result {
                alertMessage = "Export failed: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: key.isSecretKey ? "key.fill" : "key")
                .font(.system(size: 48))
                .foregroundStyle(key.isSecretKey ? .orange : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(key.displayName)
                    .font(.title)
                    .fontWeight(.semibold)

                if let email = key.email {
                    Text(email)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    KeyBadge(
                        text: key.isSecretKey ? "Secret Key" : "Public Key",
                        color: key.isSecretKey ? .orange : .blue
                    )

                    if key.isExpired {
                        KeyBadge(text: "Expired", color: .red)
                    }
                }
            }

            Spacer()
        }
    }

    private var keyInfoSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], alignment: .leading, spacing: 16) {
            InfoRow(label: "Key ID", value: key.shortKeyID)
            InfoRow(label: "Algorithm", value: key.algorithmDescription)
            InfoRow(label: "Created", value: key.creationDate.formatted(date: .abbreviated, time: .omitted))
            InfoRow(
                label: "Expires",
                value: key.expirationDate?.formatted(date: .abbreviated, time: .omitted) ?? "Never"
            )
        }
    }

    private var userIDsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("User IDs")
                .font(.headline)

            ForEach(key.userIDs) { userID in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(userID.name)
                            .fontWeight(.medium)
                        Text(userID.email)
                            .foregroundStyle(.secondary)
                        if let comment = userID.comment {
                            Text(comment)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var expirationWarning: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text("This key has expired")
                    .fontWeight(.semibold)
                Text("Expired keys cannot be used for encryption or signing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func exportKey(includeSecret: Bool) {
        do {
            exportData = try keyringService.exportKey(key, includeSecretKey: includeSecret, armored: true)
            let suffix = includeSecret ? "secret" : "public"
            exportFileName = "\(key.displayName.replacingOccurrences(of: " ", with: "_"))_\(suffix).asc"
            showingExportSheet = true
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func deleteKey() {
        do {
            try keyringService.deleteKey(key)
        } catch {
            alertMessage = "Failed to delete key: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

struct KeyBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    KeyDetailsView(key: .preview)
        .environment(KeyringService())
        .frame(width: 500, height: 600)
}
