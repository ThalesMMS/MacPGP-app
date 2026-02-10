import SwiftUI
import UniformTypeIdentifiers

struct RevocationManagementView: View {
    let key: PGPKeyModel
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RevocationManagementViewModel?

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
                viewModel = RevocationManagementViewModel(key: key)
            }
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
    }

    @ViewBuilder
    private func formView(viewModel: RevocationManagementViewModel) -> some View {
        @Bindable var vm = viewModel

        Form {
            Section("Key Information") {
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
                            Text("This key is already revoked")
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }

            if key.isSecretKey && !key.isRevoked {
                Section("Generate Revocation Certificate") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Generate a revocation certificate to revoke this key in the future.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Reason for Revocation", selection: $vm.selectedReason) {
                            ForEach(RevocationReason.allCases, id: \.self) { reason in
                                Text(reason.displayName).tag(reason)
                            }
                        }

                        PassphraseField(
                            title: "Passphrase",
                            passphrase: $vm.generatePassphrase
                        )

                        Button("Generate Certificate") {
                            viewModel.generateCertificate()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canGenerate || viewModel.isProcessing)
                    }
                }
            }

            Section("Import & Apply Revocation Certificate") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Import a revocation certificate to permanently revoke this key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Choose File...") {
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
                        Button("Apply Revocation") {
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
        .navigationTitle("Revocation Management")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
        .overlay {
            if viewModel.isProcessing {
                processingOverlay(viewModel: viewModel)
            }
        }
        .fileExporter(
            isPresented: $vm.showingExportSheet,
            document: PGPKeyDocument(data: viewModel.exportData ?? Data()),
            contentType: .data,
            defaultFilename: viewModel.exportFileName
        ) { result in
            viewModel.handleExportResult(result)
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
            Button("Apply Revocation", role: .destructive) {
                viewModel.applyRevocation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently revoke \"\(key.displayName)\". This action cannot be undone and the key will no longer be usable for encryption or signing.")
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

                Text("This may take a moment")
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

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .navigationTitle("Success")
    }
}

@Observable
final class RevocationManagementViewModel {
    let key: PGPKeyModel

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

    init(key: PGPKeyModel) {
        self.key = key
    }

    var canGenerate: Bool {
        !generatePassphrase.isEmpty && key.isSecretKey && !key.isRevoked
    }

    func generateCertificate() {
        guard canGenerate else { return }

        isProcessing = true
        processingMessage = "Generating revocation certificate..."
        errorMessage = nil

        do {
            let certificate = try revocationService.generateRevocationCertificate(
                for: key,
                reason: selectedReason,
                passphrase: generatePassphrase
            )

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
            isProcessing = false
            if let operationError = error as? OperationError {
                errorMessage = operationError.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
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
                let data = try Data(contentsOf: url)
                selectedCertificateURL = url
                selectedCertificateData = data
            } catch {
                errorMessage = "Failed to read certificate file: \(error.localizedDescription)"
            }

        case .failure(let error):
            errorMessage = "Failed to import certificate: \(error.localizedDescription)"
        }
    }

    func applyRevocation() {
        guard let certificateData = selectedCertificateData else { return }

        isProcessing = true
        processingMessage = "Applying revocation certificate..."
        errorMessage = nil

        do {
            // First import to validate
            let fingerprint = try revocationService.importRevocationCertificate(data: certificateData)

            // Verify it matches our key
            guard fingerprint == key.fingerprint else {
                throw OperationError.unknownError(message: "Certificate does not match this key")
            }

            // Apply the revocation
            let _ = try revocationService.applyRevocation(to: key, certificate: certificateData)

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
