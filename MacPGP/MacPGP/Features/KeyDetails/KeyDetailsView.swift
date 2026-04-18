import SwiftUI
import UniformTypeIdentifiers

struct KeyDetailsView: View {
    let key: PGPKeyModel
    let onKeyUpdated: (PGPKeyModel) -> Void
    @Environment(KeyringService.self) private var keyringService
    @State private var showingExportSheet = false
    @State private var exportData: Data?
    @State private var exportFileName: String = ""
    @State private var showingDeleteConfirmation = false
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var showingFingerprintVerification = false
    @State private var showingTrustLevelPicker = false
    @State private var trustLevelPickerPresentationID = UUID()

    init(key: PGPKeyModel, onKeyUpdated: @escaping (PGPKeyModel) -> Void = { _ in }) {
        self.key = key
        self.onKeyUpdated = onKeyUpdated
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                Divider()
                keyInfoSection
                Divider()
                KeyFingerprintView(fingerprint: currentKey.fingerprint)
                Divider()
                userIDsSection

                // v1.0 keeps expiration handling read-only because ObjectivePGP cannot extend key
                // expiration reliably yet. The banner warns only and does not expose edit actions.
                if currentKey.expirationWarningLevel != .none {
                    Divider()
                    ExpirationWarningBanner(key: currentKey)
                }

                // Show detailed warning/error for expired or revoked keys
                if currentKey.isExpired || currentKey.isRevoked {
                    Divider()
                    statusWarning
                }
            }
            .padding(24)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(minWidth: 350, maxWidth: .infinity)
        .navigationTitle(currentKey.displayName)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showTrustLevelPicker()
                } label: {
                    Label("Set Trust Level", systemImage: "shield.checkered")
                }
                .help("Set trust level for this key")

                Button {
                    showingFingerprintVerification = true
                } label: {
                    Label("Verify Fingerprint", systemImage: "checkmark.seal")
                }
                .help("Verify this key's fingerprint")
                Menu {
                    Button("Export Public Key...") {
                        exportKey(includeSecret: false)
                    }

                    if currentKey.isSecretKey {
                        Button("Export Secret Key...") {
                            exportKey(includeSecret: true)
                        }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                // Revocation management is intentionally omitted from the release UI until
                // ObjectivePGP can generate and apply revocation certificates reliably.
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
            Text("Are you sure you want to delete \"\(currentKey.displayName)\"? This action cannot be undone.")
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
        .sheet(isPresented: $showingTrustLevelPicker) {
            TrustLevelPickerView(key: currentKey) { updatedKey in
                onKeyUpdated(updatedKey)
            }
                .id(trustLevelPickerPresentationID)
        }
        .sheet(isPresented: $showingFingerprintVerification) {
            FingerprintVerificationView(key: currentKey)
        }
    }

    private func showTrustLevelPicker() {
        trustLevelPickerPresentationID = UUID()
        showingTrustLevelPicker = true
    }

    private var currentKey: PGPKeyModel {
        keyringService.key(withFingerprint: key.fingerprint) ?? key
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: currentKey.isSecretKey ? "key.fill" : "key")
                .font(.system(size: 48))
                .foregroundStyle(currentKey.isSecretKey ? .orange : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(currentKey.displayName)
                    .font(.title)
                    .fontWeight(.semibold)

                if let email = currentKey.email {
                    Text(email)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    KeyBadge(
                        text: currentKey.isSecretKey ? "Secret Key" : "Public Key",
                        color: currentKey.isSecretKey ? .orange : .blue
                    )

                    // Trust level badge (clickable)
                    Button {
                        showTrustLevelPicker()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: currentKey.trustLevel.iconName)
                            Text("Trust: \(currentKey.trustLevel.displayName)")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(currentKey.trustLevel.color.opacity(0.15))
                        .foregroundStyle(currentKey.trustLevel.color)
                        .clipShape(Capsule())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Trust Level Badge \(currentKey.trustLevel.displayName)")
                    .accessibilityIdentifier("Trust Level Badge \(currentKey.trustLevel.displayName)")
                    .id(currentKey.trustLevel)
                    .buttonStyle(.plain)
                    .help("Set trust level for this key")

                    if currentKey.isVerified {
                        KeyBadge(text: "Verified", color: .green)
                    }

                    if currentKey.isExpired {
                        KeyBadge(text: "Expired", color: .red)
                    }

                    if currentKey.isRevoked {
                        KeyBadge(text: "Revoked", color: .red)
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
            InfoRow(label: "Key ID", value: currentKey.shortKeyID)
            InfoRow(label: "Algorithm", value: currentKey.algorithmDescription)
            InfoRow(label: "Created", value: currentKey.creationDate.formatted(date: .abbreviated, time: .omitted))
            InfoRow(
                label: "Expires",
                value: currentKey.expirationDate?.formatted(date: .abbreviated, time: .omitted) ?? "Never"
            )
        }
    }

    private var userIDsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("User IDs")
                .font(.headline)

            ForEach(currentKey.userIDs) { userID in
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

    private var statusWarning: some View {
        HStack(spacing: 12) {
            Image(systemName: currentKey.isRevoked ? "xmark.shield.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                if currentKey.isRevoked {
                    Text("This key has been revoked")
                        .fontWeight(.semibold)
                    Text("Revoked keys cannot be used for encryption or signing. This key should not be trusted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if currentKey.isExpired {
                    Text("This key has expired")
                        .fontWeight(.semibold)
                    Text("Expired keys cannot be used for encryption or signing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func exportKey(includeSecret: Bool) {
        do {
            exportData = try keyringService.exportKey(currentKey, includeSecretKey: includeSecret, armored: true)
            let suffix = includeSecret ? "secret" : "public"
            exportFileName = "\(currentKey.displayName.replacingOccurrences(of: " ", with: "_"))_\(suffix).asc"
            showingExportSheet = true
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func deleteKey() {
        do {
            try keyringService.deleteKey(currentKey)
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
    let keyringService = KeyringService()

    KeyDetailsView(key: .preview)
        .environment(keyringService)
        .frame(width: 500, height: 600)
}