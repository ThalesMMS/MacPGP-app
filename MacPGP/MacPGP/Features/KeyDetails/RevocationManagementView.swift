import SwiftUI
import UniformTypeIdentifiers

struct RevocationManagementView: View {
    let key: PGPKeyModel
    let onKeyUpdated: (PGPKeyModel) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(KeyringService.self) private var keyringService
    @State private var viewModel: RevocationManagementViewModel?

    init(key: PGPKeyModel, onKeyUpdated: @escaping (PGPKeyModel) -> Void = { _ in }) {
        self.key = key
        self.onKeyUpdated = onKeyUpdated
    }

    var body: some View {
        Group {
            if let viewModel = viewModel {
                managementContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = RevocationManagementViewModel(
                    key: key,
                    keyringService: keyringService,
                    onKeyUpdated: onKeyUpdated
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPGPDidLock)) { _ in
            viewModel?.handleLock()
        }
    }

    @ViewBuilder
    private func managementContent(viewModel: RevocationManagementViewModel) -> some View {
        @Bindable var vm = viewModel

        NavigationStack {
            if viewModel.isSuccess {
                successView(viewModel: viewModel)
            } else {
                formView(viewModel: viewModel)
            }
        }
        .frame(width: 550, height: 600)
        .fileExporter(
            isPresented: $vm.showingExportSheet,
            document: PGPKeyDocument(data: viewModel.exportData ?? Data()),
            contentType: .data,
            defaultFilename: viewModel.exportFileName
        ) { result in
            viewModel.handleExportResult(result)
        }
    }

    @ViewBuilder
    private func formView(viewModel: RevocationManagementViewModel) -> some View {
        @Bindable var vm = viewModel

        Form {
            Section("trust.key_information") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(key.displayName)
                        .font(.headline)

                    if let email = key.email {
                        Text(email)
                            .foregroundStyle(.secondary)
                    }

                    Text(key.shortKeyID)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tertiary)

                    if key.isRevoked {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("revocation.already_revoked")
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }

            if key.isSecretKey && !key.isRevoked {
                Section("revocation.generate_certificate") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("revocation.generate_certificate_message")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("revocation.reason", selection: $vm.selectedReason) {
                            ForEach(RevocationReason.allCases, id: \.self) { reason in
                                Text(reason.displayName).tag(reason)
                            }
                        }

                        PassphraseField(
                            title: "Passphrase",
                            passphrase: $vm.generatePassphrase
                        )

                        Button("revocation.generate_button") {
                            Task {
                                await viewModel.generateCertificate()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canGenerate || viewModel.isProcessing)
                    }
                }
            }

            Section("revocation.import_apply") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("revocation.import_apply_message")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("revocation.choose_file") {
                            viewModel.showingImportPicker = true
                        }
                        .buttonStyle(.bordered)

                        if let url = viewModel.selectedCertificateURL {
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    if viewModel.selectedCertificateURL != nil {
                        Button("revocation.apply_revocation") {
                            viewModel.showingApplyConfirmation = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(viewModel.isProcessing)
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("revocation.title")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("revocation.close") {
                    dismiss()
                }
            }
        }
        .overlay {
            if viewModel.isProcessing {
                processingOverlay(viewModel: viewModel)
            }
        }
        .fileImporter(
            isPresented: $vm.showingImportPicker,
            allowedContentTypes: [.data, .text],
            allowsMultipleSelection: false
        ) { result in
            viewModel.handleImportResult(result)
        }
        .confirmationDialog(
            "Apply Revocation Certificate",
            isPresented: $vm.showingApplyConfirmation
        ) {
            Button("revocation.apply_revocation", role: .destructive) {
                Task {
                    await viewModel.applyRevocation()
                }
            }
            Button("keygen.cancel", role: .cancel) {}
        } message: {
            Text(String.localizedStringWithFormat(NSLocalizedString("revocation.confirm_revoke_format", comment: ""), key.displayName))
        }
    }

    @ViewBuilder
    private func processingOverlay(viewModel: RevocationManagementViewModel) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text(viewModel.processingMessage)
                    .font(.headline)

                Text("keygen.please_wait")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func successView(viewModel: RevocationManagementViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text(viewModel.successTitle)
                .font(.title)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                Text(key.displayName)
                    .font(.headline)

                Text(viewModel.successMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label(viewModel.successDetails, systemImage: viewModel.successIcon)
                }
                .font(.callout)
            }
            .frame(maxWidth: 350)

            Spacer()

            Button("keygen.done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .navigationTitle("common.success")
    }
}

@MainActor
@Observable
final class RevocationManagementViewModel: SensitiveSessionState {
    let key: PGPKeyModel

    /// Bumped on lock so a certificate generation that resolves after the
    /// session is locked cannot publish results with a cleared passphrase.
    private var lockGeneration = 0

    // Generate Certificate State
    var selectedReason: RevocationReason = .noReason
    var generatePassphrase: String = ""

    // Import Certificate State
    var selectedCertificateURL: URL?
    var selectedCertificateData: Data?

    // UI State
    var showingExportSheet: Bool = false
    var showingImportPicker: Bool = false
    var showingApplyConfirmation: Bool = false
    var isProcessing: Bool = false
    var errorMessage: String?
    var isSuccess: Bool = false
    var processingMessage: String = "Processing..."

    // Export State
    var exportData: Data?
    var exportFileName: String = ""

    // Success State
    var successTitle: String = ""
    var successMessage: String = ""
    var successDetails: String = ""
    var successIcon: String = "checkmark.circle"

    private let revocationService = RevocationService.shared
    private let keyringService: KeyringService
    private let onKeyUpdated: (PGPKeyModel) -> Void

    init(
        key: PGPKeyModel,
        keyringService: KeyringService,
        onKeyUpdated: @escaping (PGPKeyModel) -> Void
    ) {
        self.key = key
        self.keyringService = keyringService
        self.onKeyUpdated = onKeyUpdated
    }

    var canGenerate: Bool {
        !generatePassphrase.isEmpty && key.isSecretKey && !key.isRevoked
    }

    func generateCertificate() async {
        guard canGenerate else { return }

        let generation = lockGeneration
        isProcessing = true
        processingMessage = "Generating revocation certificate..."
        errorMessage = nil

        let reason = selectedReason
        let passphrase = generatePassphrase

        do {
            let certificate = try await revocationService.generateRevocationCertificateAsync(
                for: key,
                reason: reason,
                passphrase: passphrase
            )

            // A lock during generation invalidates the run.
            guard generation == lockGeneration else { return }

            // Prepare for export
            exportData = certificate
            exportFileName = "\(key.displayName.replacingOccurrences(of: " ", with: "_"))_revocation.asc"

            // Show success
            isProcessing = false
            isSuccess = true
            successTitle = "Certificate Generated"
            successMessage = "Revocation certificate has been created"
            successDetails = "Save this certificate securely. You'll need it to revoke the key if it becomes compromised."
            successIcon = "doc.badge.checkmark"

            // Trigger file save
            showingExportSheet = true
        } catch {
            guard generation == lockGeneration else { return }
            isProcessing = false
            if let operationError = error as? OperationError {
                errorMessage = operationError.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Clears the generation passphrase and invalidates an in-flight certificate
    /// generation on **Lock MacPGP**.
    func handleLock() {
        lockGeneration &+= 1
        generatePassphrase = ""
        isProcessing = false
    }

    func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            // File was saved successfully
            break
        case .failure(let error):
            errorMessage = "Failed to save certificate: \(error.localizedDescription)"
            isSuccess = false
        }
    }

    func handleImportResult(_ result: Result<[URL], Error>) {
        errorMessage = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            do {
                let data = try revocationService.importRevocationCertificateFromFile(from: url)
                selectedCertificateURL = url
                selectedCertificateData = data
            } catch {
                selectedCertificateURL = nil
                selectedCertificateData = nil
                errorMessage = "Failed to read certificate file: \(error.userFacingMessage)"
            }

        case .failure(let error):
            errorMessage = "Failed to import certificate: \(error.localizedDescription)"
        }
    }

    func applyRevocation() async {
        guard let certificateData = selectedCertificateData else { return }

        isProcessing = true
        processingMessage = "Applying revocation certificate..."
        errorMessage = nil

        do {
            _ = try revocationService.importRevocationCertificate(
                data: certificateData,
                keyringService: keyringService,
                expectedKey: key
            )

            // Apply the revocation
            let updatedKey = try await revocationService.applyRevocationAsync(to: key, certificate: certificateData)
            try keyringService.replaceKey(updatedKey.rawKey)
            onKeyUpdated(updatedKey)

            // Show success
            isProcessing = false
            isSuccess = true
            successTitle = "Key Revoked"
            successMessage = "The key has been permanently revoked"
            successDetails = "This key can no longer be used for encryption or signing"
            successIcon = "exclamationmark.shield.fill"
        } catch {
            isProcessing = false
            if let operationError = error as? OperationError {
                errorMessage = operationError.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    RevocationManagementView(key: .preview)
}
