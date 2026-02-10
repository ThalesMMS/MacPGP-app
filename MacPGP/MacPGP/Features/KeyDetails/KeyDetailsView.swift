import SwiftUI
import UniformTypeIdentifiers

struct KeyDetailsView: View {
    let key: PGPKeyModel
    @Environment(KeyringService.self) private var keyringService
    @Environment(TrustService.self) private var trustService
    @State private var showingExportSheet = false
    @State private var exportData: Data?
    @State private var exportFileName: String = ""
    @State private var showingDeleteConfirmation = false
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var showingExtendExpiration = false
    @State private var showingRevocationManagement = false
    @State private var showingFingerprintVerification = false
    @State private var showingTrustLevelPicker = false
    @State private var trustPaths: [TrustPath] = []
    @State private var effectiveTrust: TrustLevel = .unknown

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                Divider()
                keyInfoSection
                Divider()
                KeyFingerprintView(fingerprint: key.fingerprint)
                Divider()
                trustPathSection
                Divider()
                userIDsSection

                // Show expiration warning banner if key is expiring soon or has expiration concerns
                if key.expirationWarningLevel != .none || key.isRevoked {
                    Divider()
                    ExpirationWarningBanner(key: key) {
                        showingExtendExpiration = true
                    }
                }

                // Show detailed warning/error for expired or revoked keys
                if key.isExpired || key.isRevoked {
                    Divider()
                    statusWarning
                }
            }
            .padding(24)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(minWidth: 350, maxWidth: .infinity)
        .navigationTitle(key.displayName)
        .onAppear {
            loadTrustPaths()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingTrustLevelPicker = true
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

                if key.isSecretKey {
                    Button {
                        showingExtendExpiration = true
                    } label: {
                        Label("Extend Expiration", systemImage: "calendar.badge.plus")
                    }
                    .help("Extend the key's expiration date")

                    Button {
                        showingRevocationManagement = true
                    } label: {
                        Label("Revocation", systemImage: "exclamationmark.shield")
                    }
                    .help("Manage revocation certificate")
                }

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
        .sheet(isPresented: $showingTrustLevelPicker) {
            TrustLevelPickerView(key: key)
        }
        .sheet(isPresented: $showingExtendExpiration) {
            ExtendExpirationView(key: key)
        }
        .sheet(isPresented: $showingRevocationManagement) {
            RevocationManagementView(key: key)
        }
        .sheet(isPresented: $showingFingerprintVerification) {
            FingerprintVerificationView(key: key)
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

                    // Trust level badge (clickable)
                    Button {
                        showingTrustLevelPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: trustLevelIconName(for: key.trustLevel))
                            Text("Trust: \(key.trustLevel.displayName)")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(trustLevelColor(for: key.trustLevel).opacity(0.15))
                        .foregroundStyle(trustLevelColor(for: key.trustLevel))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Set trust level for this key")

                    if key.isVerified {
                        KeyBadge(text: "Verified", color: .green)
                    }

                    if key.isExpired {
                        KeyBadge(text: "Expired", color: .red)
                    }

                    if key.isRevoked {
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

    private var statusWarning: some View {
        HStack(spacing: 12) {
            Image(systemName: key.isRevoked ? "xmark.shield.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                if key.isRevoked {
                    Text("This key has been revoked")
                        .fontWeight(.semibold)
                    Text("Revoked keys cannot be used for encryption or signing. This key should not be trusted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if key.isExpired {
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

    private var trustPathSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trust Path")
                    .font(.headline)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: trustLevelIconName(for: effectiveTrust))
                    Text(effectiveTrust.displayName)
                }
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(trustLevelColor(for: effectiveTrust).opacity(0.15))
                .foregroundStyle(trustLevelColor(for: effectiveTrust))
                .clipShape(Capsule())
            }

            if !trustPaths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    let path = trustPaths[0]

                    ForEach(Array(path.nodes.enumerated()), id: \.offset) { index, node in
                        HStack(spacing: 12) {
                            // Trust level indicator
                            ZStack {
                                Circle()
                                    .fill(trustLevelColor(for: node.trustLevel).opacity(0.2))
                                    .frame(width: 32, height: 32)

                                Image(systemName: node.key.isSecretKey ? "key.fill" : "key")
                                    .font(.caption)
                                    .foregroundStyle(trustLevelColor(for: node.trustLevel))
                            }

                            // Key information
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(node.key.displayName)
                                        .font(.caption)
                                        .fontWeight(.medium)

                                    if index == 0 {
                                        Text("Your Key")
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.purple.opacity(0.2))
                                            .foregroundStyle(.purple)
                                            .clipShape(Capsule())
                                    }

                                    if index == path.nodes.count - 1 {
                                        Text("Target")
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.blue.opacity(0.2))
                                            .foregroundStyle(.blue)
                                            .clipShape(Capsule())
                                    }
                                }

                                HStack(spacing: 4) {
                                    Image(systemName: trustLevelIconName(for: node.trustLevel))
                                    Text(node.trustLevel.displayName)
                                }
                                .font(.caption2)
                                .foregroundStyle(trustLevelColor(for: node.trustLevel))
                            }

                            Spacer()
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        if index < path.nodes.count - 1 {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("certifies")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 20)
                            .padding(.vertical, 2)
                        }
                    }

                    if trustPaths.count > 1 {
                        Text("+ \(trustPaths.count - 1) more trust path\(trustPaths.count > 2 ? "s" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)

                    Text("No trust path found from your trusted keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Trust Level Helpers

    private func trustLevelIconName(for level: TrustLevel) -> String {
        switch level {
        case .unknown: return "questionmark.circle"
        case .never: return "xmark.shield"
        case .marginal: return "shield.lefthalf.filled"
        case .full: return "shield"
        case .ultimate: return "crown.fill"
        }
    }

    private func trustLevelColor(for level: TrustLevel) -> Color {
        switch level {
        case .unknown: return .gray
        case .never: return .red
        case .marginal: return .orange
        case .full: return .green
        case .ultimate: return .purple
        }
    }

    // MARK: - Actions

    private func loadTrustPaths() {
        trustPaths = trustService.findTrustPaths(to: key)
        effectiveTrust = trustService.calculateEffectiveTrust(for: key)
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
    let keyringService = KeyringService()
    let trustService = TrustService(keyringService: keyringService)

    KeyDetailsView(key: .preview)
        .environment(keyringService)
        .environment(trustService)
        .frame(width: 500, height: 600)
}
