import SwiftUI
import UniformTypeIdentifiers

struct RestoreWizardView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: BackupViewModel?
    @State private var currentStep: RestoreStep = .fileSelection

    enum RestoreStep {
        case fileSelection
        case passphrase
        case validation
        case confirmation
        case success
    }

    var body: some View {
        Group {
            if let viewModel = viewModel {
                restoreContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = BackupViewModel(keyringService: keyringService)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPGPDidLock)) { _ in
            viewModel?.handleLock()
        }
    }

    @ViewBuilder
    private func restoreContent(viewModel: BackupViewModel) -> some View {
        @Bindable var vm = viewModel

        NavigationStack {
            VStack(spacing: 0) {
                if currentStep != .success {
                    stepIndicator
                        .padding()
                }

                switch currentStep {
                case .fileSelection:
                    fileSelectionView(viewModel: viewModel)
                case .passphrase:
                    passphraseView(viewModel: viewModel)
                case .validation:
                    validationView(viewModel: viewModel)
                case .confirmation:
                    confirmationView(viewModel: viewModel)
                case .success:
                    successView(viewModel: viewModel)
                }
            }
        }
        .frame(width: 600, height: 500)
    }

    // MARK: - Step Indicator

    @ViewBuilder
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            stepDot(number: 1, title: "Select", isActive: currentStep == .fileSelection, isCompleted: stepCompleted(.fileSelection))
            stepConnector(isCompleted: stepCompleted(.fileSelection))
            stepDot(number: 2, title: "Decrypt", isActive: currentStep == .passphrase, isCompleted: stepCompleted(.passphrase))
            stepConnector(isCompleted: stepCompleted(.passphrase))
            stepDot(number: 3, title: "Validate", isActive: currentStep == .validation, isCompleted: stepCompleted(.validation))
            stepConnector(isCompleted: stepCompleted(.validation))
            stepDot(number: 4, title: "Confirm", isActive: currentStep == .confirmation, isCompleted: stepCompleted(.confirmation))
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func stepDot(number: Int, title: String, isActive: Bool, isCompleted: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green : (isActive ? Color.accentColor : Color.gray.opacity(0.3)))
                    .frame(width: 32, height: 32)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                } else {
                    Text("\(number)")
                        .foregroundStyle(isActive ? .white : .secondary)
                        .fontWeight(isActive ? .semibold : .regular)
                }
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func stepConnector(isCompleted: Bool) -> some View {
        Rectangle()
            .fill(isCompleted ? Color.green : Color.gray.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    private func stepCompleted(_ step: RestoreStep) -> Bool {
        let steps: [RestoreStep] = [.fileSelection, .passphrase, .validation, .confirmation, .success]
        guard let currentIndex = steps.firstIndex(of: currentStep),
              let stepIndex = steps.firstIndex(of: step) else {
            return false
        }
        return currentIndex > stepIndex
    }

    // MARK: - File Selection View

    @ViewBuilder
    private func fileSelectionView(viewModel: BackupViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("restore.select_file")
                .font(.title)
                .fontWeight(.semibold)

            Text("restore.select_file_message")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let url = viewModel.restoreFileURL {
                GroupBox {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text(url.lastPathComponent)
                                .fontWeight(.medium)
                            Text(url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .frame(maxWidth: 400)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("restore.title")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("keygen.cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(viewModel.restoreFileURL == nil ? "Choose File..." : "Next") {
                    if viewModel.restoreFileURL == nil {
                        selectBackupFile(viewModel: viewModel)
                    } else {
                        proceedToNextStep(viewModel: viewModel)
                    }
                }
            }
        }
    }

    private func selectBackupFile(viewModel: BackupViewModel) {
        let panel = NSOpenPanel()
        panel.title = "Select Backup File"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "macpgp") ?? .data, .data]

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await viewModel.validateBackup(url: url)
                if viewModel.errorMessage == nil {
                    // File validated, move to appropriate next step
                    await MainActor.run {
                        if viewModel.validatedBackup?.isEncrypted == true {
                            currentStep = .passphrase
                        } else {
                            currentStep = .validation
                        }
                    }
                }
            }
        }
    }

    private func proceedToNextStep(viewModel: BackupViewModel) {
        if viewModel.validatedBackup?.isEncrypted == true {
            currentStep = .passphrase
        } else {
            currentStep = .validation
        }
    }

    /// Displays the passphrase entry screen used to decrypt an encrypted backup.
    /// 
    /// The view binds to the provided `BackupViewModel` for the passphrase, error, and processing state. It shows:
    /// - a secure field bound to `viewModel.restorePassphrase`;
    /// - any `viewModel.errorMessage` in a red section;
    /// - a "Back" toolbar button that sets `currentStep` to `.fileSelection`;
    /// - a "Decrypt" toolbar button that triggers decryption and is disabled when the passphrase is empty or `viewModel.isProcessing` is `true`;
    /// - a full-screen processing overlay while `viewModel.isProcessing` is `true`.
    /// - Parameters:
    ///   - viewModel: The `BackupViewModel` providing bindings and state for passphrase entry and decryption.
    /// - Returns: A view presenting the passphrase form, toolbar actions, and conditional processing overlay.

    @ViewBuilder
    private func passphraseView(viewModel: BackupViewModel) -> some View {
        @Bindable var vm = viewModel

        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text("restore.encrypted_backup")
                                .font(.headline)
                            Text("restore.enter_the_passphrase_to_decrypt_this_bac")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SecureField("Backup Passphrase", text: $vm.restorePassphrase)
                        .textFieldStyle(.roundedBorder)
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
        .navigationTitle("restore.decrypt_backup")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("backup.back") {
                    currentStep = .fileSelection
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("sidebar.decrypt") {
                    Task {
                        await decryptAndValidate(viewModel: viewModel)
                    }
                }
                .disabled(viewModel.restorePassphrase.isEmpty || viewModel.isProcessing)
            }
        }
        .overlay {
            if viewModel.isProcessing {
                processingOverlay(message: "Decrypting backup...")
            }
        }
    }

    /// Attempts to decrypt and validate the selected backup using the provided view model and advances the wizard to the validation step if that operation succeeds.
    /// - Parameter viewModel: The `BackupViewModel` that performs decryption and validation.
    private func decryptAndValidate(viewModel: BackupViewModel) async {
        let didValidate = await viewModel.decryptAndValidateBackup()

        if didValidate {
            await MainActor.run {
                currentStep = .validation
            }
        }
    }

    // MARK: - Validation View

    @ViewBuilder
    private func validationView(viewModel: BackupViewModel) -> some View {
        Form {
            if let backup = viewModel.validatedBackup {
                Section("backup.backup_information") {
                    LabeledContent("Created", value: backup.formattedCreatedDate)
                    LabeledContent("Created By", value: backup.createdBy)
                    LabeledContent("Encryption", value: backup.isEncrypted ? "AES-256" : "None")
                    LabeledContent("Keys", value: "\(backup.keyCount)")

                    if let name = backup.metadata.name {
                        LabeledContent("Name", value: name)
                    }

                    if let description = backup.metadata.description {
                        LabeledContent("Description", value: description)
                    }
                }

                if !viewModel.previewKeys.isEmpty {
                    Section("restore.keys_to_import") {
                        ForEach(viewModel.previewKeys, id: \.self) { fingerprint in
                            HStack {
                                Image(systemName: "key.fill")
                                    .foregroundStyle(.secondary)
                                Text(fingerprint)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                            }
                        }
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            if let success = viewModel.successMessage {
                Section {
                    Label(success, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let warning = viewModel.warningMessage {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("restore.validate_backup")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("backup.back") {
                    if viewModel.validatedBackup?.isEncrypted == true {
                        currentStep = .passphrase
                    } else {
                        currentStep = .fileSelection
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("restore.continue") {
                    currentStep = .confirmation
                }
                .disabled(viewModel.validatedBackup == nil)
            }
        }
    }

    // MARK: - Confirmation View

    @ViewBuilder
    private func confirmationView(viewModel: BackupViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("restore.ready_to_import")
                .font(.title)
                .fontWeight(.semibold)

            if let backup = viewModel.validatedBackup {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(String.localizedStringWithFormat(NSLocalizedString("restore.import_key_count", comment: ""), backup.keyCount), systemImage: "key.fill")
                        Label("restore.adds_keys_to_your_keyring", systemImage: "plus.circle.fill")

                        if backup.isEncrypted {
                            Label("restore.backup_will_be_decrypted_using_your_pass", systemImage: "lock.open.fill")
                        }
                    }
                    .font(.callout)
                }
                .frame(maxWidth: 400)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("restore.confirm_import")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("backup.back") {
                    currentStep = .validation
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("restore.import_keys") {
                    Task {
                        await performRestore(viewModel: viewModel)
                    }
                }
                .disabled(viewModel.isProcessing)
            }
        }
        .overlay {
            if viewModel.isProcessing {
                processingOverlay(message: "Importing keys...")
            }
        }
    }

    private func performRestore(viewModel: BackupViewModel) async {
        await viewModel.restoreBackup()

        if viewModel.errorMessage == nil {
            await MainActor.run {
                currentStep = .success
            }
        }
    }

    // MARK: - Success View

    @ViewBuilder
    private func successView(viewModel: BackupViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("restore.restore_complete")
                .font(.title)
                .fontWeight(.semibold)

            if let success = viewModel.successMessage {
                Text(success)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let warning = viewModel.warningMessage {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            if let backup = viewModel.validatedBackup {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String.localizedStringWithFormat(NSLocalizedString("restore.imported_count", comment: ""), backup.keyCount), systemImage: "key.fill")
                        Label("restore.keys_are_now_available_in_your_keyring", systemImage: "checkmark.shield.fill")
                    }
                    .font(.callout)
                }
                .frame(maxWidth: 400)
            }

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

    // MARK: - Processing Overlay

    @ViewBuilder
    private func processingOverlay(message: String) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text(message)
                    .font(.headline)

                Text("restore.please_wait")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

#Preview {
    @Previewable @State var keyringService = KeyringService()

    RestoreWizardView()
        .environment(keyringService)
}
