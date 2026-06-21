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
    @State private var showingRevocationManagement = false
    @State private var showingExpirationEditor = false
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
                    Label("keydetails.set_trust_level", systemImage: "shield.checkered")
                }
                .help("keydetails.set_trust_level_for_this_key")

                Button {
                    showingFingerprintVerification = true
                } label: {
                    Label("keydetails.verify_fingerprint", systemImage: "checkmark.seal")
                }
                .help("keydetails.verify_this_key_s_fingerprint")
                Menu {
                    Button("keyring.export_public_key") {
                        exportKey(includeSecret: false)
                    }

                    if currentKey.isSecretKey {
                        Button("keyring.export_secret_key") {
                            exportKey(includeSecret: true)
                        }
                    }
                } label: {
                    Label("keydetails.export", systemImage: "square.and.arrow.up")
                }

                if currentKey.isSecretKey {
                    Menu {
                        if !currentKey.isRevoked {
                            Button("keydetails.edit_expiration_2") {
                                showingExpirationEditor = true
                            }
                        }

                        Button("keydetails.manage_revocation") {
                            showingRevocationManagement = true
                        }
                    } label: {
                        Label("keydetails.manage_key", systemImage: "slider.horizontal.3")
                    }
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("keydetails.delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "keyring.delete_key",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("keydetails.delete", role: .destructive) {
                deleteKey()
            }
            Button("keygen.cancel", role: .cancel) {}
        } message: {
            Text(String.localizedStringWithFormat(NSLocalizedString("keydetails.confirm_delete_format", comment: ""), currentKey.displayName))
        }
        .alert("Error", isPresented: $showingAlert) {
            Button("common.ok") {}
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
        .sheet(isPresented: $showingRevocationManagement) {
            RevocationManagementView(key: currentKey) { updatedKey in
                onKeyUpdated(updatedKey)
            }
        }
        .sheet(isPresented: $showingExpirationEditor) {
            KeyExpirationEditorView(key: currentKey) { updatedKey in
                onKeyUpdated(updatedKey)
            }
            .environment(keyringService)
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
                            Text(String.localizedStringWithFormat(NSLocalizedString("keydetails.trust_inline_format", comment: ""), currentKey.trustLevel.displayName))
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
                    .help("keydetails.set_trust_level_for_this_key")

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
            LabelValueRow(
                verbatimLabel: "Key ID",
                value: currentKey.shortKeyID,
                style: .keyDetails
            )
            LabelValueRow(
                verbatimLabel: "Algorithm",
                value: currentKey.algorithmDescription,
                style: .keyDetails
            )
            LabelValueRow(
                verbatimLabel: "Created",
                value: currentKey.creationDate.formatted(date: .abbreviated, time: .omitted),
                style: .keyDetails
            )
            LabelValueRow(
                verbatimLabel: "Expires",
                value: currentKey.expirationDate?.formatted(date: .abbreviated, time: .omitted) ?? "Never",
                style: .keyDetails
            )
        }
        .overlay(alignment: .bottomTrailing) {
            if currentKey.isSecretKey && !currentKey.isRevoked {
                Button("keydetails.edit_expiration_2") {
                    showingExpirationEditor = true
                }
                .buttonStyle(.borderless)
                .padding(.top, 8)
            }
        }
    }

    private var userIDsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("keydetails.user_ids")
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
                    Text("keydetails.key_revoked")
                        .fontWeight(.semibold)
                    Text("keydetails.key_revoked_message")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if currentKey.isExpired {
                    Text("keydetails.key_expired")
                        .fontWeight(.semibold)
                    Text("keydetails.key_expired_message")
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

#if DEBUG
#Preview {
    let keyringService = KeyringService()

    KeyDetailsView(key: .preview)
        .environment(keyringService)
        .frame(width: 500, height: 600)
}
#endif

private struct KeyExpirationEditorView: View {
    let key: PGPKeyModel
    let onUpdated: (PGPKeyModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(KeyringService.self) private var keyringService
    @State private var expirationService = KeyExpirationService.shared
    @State private var passphrase = ""
    @State private var selectedDate: Date
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var updateTask: Task<Void, Never>?

    init(key: PGPKeyModel, onUpdated: @escaping (PGPKeyModel) -> Void) {
        self.key = key
        self.onUpdated = onUpdated

        let defaultDate = key.expirationDate.flatMap {
            $0 > Date() ? $0 : nil
        } ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        _selectedDate = State(initialValue: Calendar.current.startOfDay(for: defaultDate))
    }

    var body: some View {
        let validationIssues = expirationService.validateExpirationDate(normalizedSelectedDate, forKey: key)

        NavigationStack {
            Form {
                Section("keydetails.key") {
                    Text(key.displayName)
                        .font(.headline)
                    Text(key.shortKeyID)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }

                Section("settings.expiration") {
                    DatePicker(
                        "New Expiration Date",
                        selection: Binding(
                            get: { selectedDate },
                            set: { selectedDate = normalizedDate($0) }
                        ),
                        in: minimumSelectableDate...,
                        displayedComponents: [.date]
                    )

                    ForEach(validationIssues, id: \.self) { issue in
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(issue.severity == .warning ? .orange : .red)
                    }
                }

                Section("keygen.passphrase") {
                    PassphraseField(title: "Passphrase", passphrase: $passphrase)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("keydetails.edit_expiration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("keygen.cancel") {
                        guard !isProcessing else { return }
                        dismiss()
                    }
                    .disabled(isProcessing)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("keydetails.update") {
                        updateExpiration()
                    }
                    .disabled(isProcessing || passphrase.isEmpty || hasBlockingValidationIssue)
                }
            }
        }
        .frame(width: 480, height: 360)
        .interactiveDismissDisabled(isProcessing)
        .onDisappear {
            updateTask?.cancel()
            updateTask = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPGPDidLock)) { _ in
            // Cancel the in-flight update (it checks Task.isCancelled before
            // applying), clear the passphrase, and dismiss the editor.
            updateTask?.cancel()
            updateTask = nil
            passphrase = ""
            isProcessing = false
            dismiss()
        }
    }

    private var hasBlockingValidationIssue: Bool {
        expirationService.validateExpirationDate(normalizedSelectedDate, forKey: key)
            .contains { $0.severity == .error }
    }

    private var minimumSelectableDate: Date {
        normalizedDate(Date())
    }

    private var normalizedSelectedDate: Date {
        normalizedDate(selectedDate)
    }

    private func normalizedDate(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func updateExpiration() {
        guard !isProcessing else { return }

        isProcessing = true
        errorMessage = nil

        let expirationDate = normalizedSelectedDate
        updateTask = Task { @MainActor in
            defer {
                isProcessing = false
                updateTask = nil
            }

            do {
                let updatedKey = try await extendExpirationAndPersist(expirationDate: expirationDate)
                guard !Task.isCancelled else { return }
                onUpdated(updatedKey)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.userFacingMessage
            }
        }
    }

    private func extendExpirationAndPersist(expirationDate: Date) async throws -> PGPKeyModel {
        let updatedKey = try await expirationService.extendExpirationAsync(
            for: key,
            newExpirationDate: normalizedDate(expirationDate),
            passphrase: passphrase
        )

        try Task.checkCancellation()
        try keyringService.replaceKey(updatedKey.rawKey)

        return updatedKey
    }
}
