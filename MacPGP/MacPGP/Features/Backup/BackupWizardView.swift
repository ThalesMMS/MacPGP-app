import SwiftUI
import UniformTypeIdentifiers

struct BackupWizardView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: BackupViewModel?
    @State private var currentStep: BackupStep = .keySelection
    @State private var showingExportDialog = false
    @State private var backupCompleted = false
    @State private var showingPaperKey = false
    @State private var paperKeyContext: PGPKeyModel?

    enum BackupStep {
        case keySelection
        case encryptionSettings
        case exporting
        case success
    }

    var body: some View {
        Group {
            if let viewModel = viewModel {
                wizardContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = BackupViewModel(keyringService: keyringService)
            }
        }
    }

    @ViewBuilder
    private func wizardContent(viewModel: BackupViewModel) -> some View {
        @Bindable var vm = viewModel

        NavigationStack {
            if backupCompleted {
                successView(viewModel: viewModel)
            } else {
                stepView(viewModel: viewModel)
            }
        }
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showingPaperKey) {
            if let key = paperKeyContext {
                PaperKeyView(key: key)
            }
        }
    }

    @ViewBuilder
    private func stepView(viewModel: BackupViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Progress indicator
            stepIndicator

            Divider()

            // Current step content
            switch currentStep {
            case .keySelection:
                keySelectionStep(viewModel: viewModel)
            case .encryptionSettings:
                encryptionSettingsStep(viewModel: viewModel)
            case .exporting:
                exportingStep(viewModel: viewModel)
            case .success:
                successView(viewModel: viewModel)
            }
        }
        .navigationTitle("Backup Keys")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                HStack(spacing: 8) {
                    if canGoBack {
                        Button("Back") {
                            goBack()
                        }
                    }

                    if currentStep != .exporting {
                        Button(nextButtonTitle) {
                            goNext(viewModel: viewModel)
                        }
                        .disabled(!canProceed(viewModel: viewModel))
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stepIndicator: some View {
        HStack(spacing: 16) {
            StepIndicatorItem(
                number: 1,
                title: "Select Keys",
                isActive: currentStep == .keySelection,
                isCompleted: stepNumber > 1
            )

            StepIndicatorItem(
                number: 2,
                title: "Encryption",
                isActive: currentStep == .encryptionSettings,
                isCompleted: stepNumber > 2
            )

            StepIndicatorItem(
                number: 3,
                title: "Export",
                isActive: currentStep == .exporting,
                isCompleted: backupCompleted
            )
        }
        .padding()
    }

    @ViewBuilder
    private func keySelectionStep(viewModel: BackupViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: 16) {
            Text("Select the keys you want to backup")
                .font(.headline)

            HStack {
                Button("Select All") {
                    viewModel.selectAllKeys()
                }
                .buttonStyle(.borderless)

                Button("Deselect All") {
                    viewModel.deselectAllKeys()
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("\(viewModel.selectedKeyCount) key(s) selected")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let availableKeys = viewModel.availableKeys
                    if availableKeys.isEmpty {
                        ContentUnavailableView(
                            "No Secret Keys",
                            systemImage: "key.slash",
                            description: Text("You need at least one secret key to create a backup")
                        )
                    } else {
                        ForEach(availableKeys) { key in
                            KeySelectionRow(
                                key: key,
                                isSelected: viewModel.selectedKeys.contains(key.fingerprint)
                            ) {
                                viewModel.toggleKeySelection(key.fingerprint)
                            }
                            .contextMenu {
                                Button("Paper Backup...") {
                                    paperKeyContext = key
                                    showingPaperKey = true
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)

                Text("For a printable backup of a single key, right-click and choose \"Paper Backup...\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .padding()
    }

    @ViewBuilder
    private func encryptionSettingsStep(viewModel: BackupViewModel) -> some View {
        @Bindable var vm = viewModel

        Form {
            Section {
                Toggle("Encrypt backup with passphrase", isOn: $vm.useEncryption)
                    .toggleStyle(.switch)

                if viewModel.useEncryption {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A strong passphrase will protect your backup if it falls into the wrong hands.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Encryption")
            }

            if viewModel.useEncryption {
                Section {
                    SecureField("Backup Passphrase", text: $vm.backupPassphrase)
                        .textContentType(.newPassword)

                    SecureField("Confirm Passphrase", text: $vm.confirmBackupPassphrase)
                        .textContentType(.newPassword)

                    if !viewModel.backupPassphrase.isEmpty && !viewModel.confirmBackupPassphrase.isEmpty {
                        if viewModel.passphraseMatch {
                            Label("Passphrases match", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Label("Passphrases do not match", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Passphrase")
                } footer: {
                    Text("Make sure to remember this passphrase. You'll need it to restore this backup.")
                        .font(.caption)
                }
            }

            Section {
                TextField("Backup Name (optional)", text: $vm.backupName)
                TextField("Description (optional)", text: $vm.backupDescription)
            } header: {
                Text("Backup Information")
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func exportingStep(viewModel: BackupViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Ready to Export")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Click 'Choose Location' to save your backup file")
                    .foregroundStyle(.secondary)
            }

            Button("Choose Location...") {
                showExportDialog(viewModel: viewModel)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func successView(viewModel: BackupViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Backup Complete")
                .font(.title)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                Text("Successfully backed up \(viewModel.selectedKeyCount) key(s)")
                    .font(.headline)

                if viewModel.useEncryption {
                    Label("Backup is encrypted", systemImage: "lock.shield.fill")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Store your backup in a secure location", systemImage: "checkmark")
                    Label("Keep your passphrase safe and accessible", systemImage: "checkmark")
                    Label("Test your backup by restoring to a test keyring", systemImage: "checkmark")
                }
                .font(.callout)
            }
            .frame(maxWidth: 400)

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

    // MARK: - Helper Methods

    private var stepNumber: Int {
        switch currentStep {
        case .keySelection: return 1
        case .encryptionSettings: return 2
        case .exporting: return 3
        case .success: return 4
        }
    }

    private var canGoBack: Bool {
        currentStep == .encryptionSettings || currentStep == .exporting
    }

    private var nextButtonTitle: String {
        switch currentStep {
        case .keySelection:
            return "Next"
        case .encryptionSettings:
            return "Next"
        case .exporting:
            return "Export"
        case .success:
            return "Done"
        }
    }

    private func canProceed(viewModel: BackupViewModel) -> Bool {
        switch currentStep {
        case .keySelection:
            return !viewModel.selectedKeys.isEmpty
        case .encryptionSettings:
            if viewModel.useEncryption {
                return !viewModel.backupPassphrase.isEmpty && viewModel.passphraseMatch
            }
            return true
        case .exporting:
            return true
        case .success:
            return true
        }
    }

    private func goBack() {
        switch currentStep {
        case .encryptionSettings:
            currentStep = .keySelection
        case .exporting:
            currentStep = .encryptionSettings
        default:
            break
        }
    }

    private func goNext(viewModel: BackupViewModel) {
        switch currentStep {
        case .keySelection:
            currentStep = .encryptionSettings
        case .encryptionSettings:
            currentStep = .exporting
        case .exporting:
            break
        case .success:
            dismiss()
        }
    }

    private func showExportDialog(viewModel: BackupViewModel) {
        let panel = NSSavePanel()
        panel.title = "Export Backup"
        panel.message = "Choose a location to save your backup"
        panel.nameFieldStringValue = "MacPGP-Backup-\(Date().formatted(.iso8601.dateSeparator(.dash).timeSeparator(.omitted).timeZoneSeparator(.omitted)))"
        panel.allowedContentTypes = [.init(exportedAs: "com.macpgp.backup", conformingTo: .data)]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            Task {
                await viewModel.createBackup(destination: url)

                await MainActor.run {
                    if viewModel.errorMessage == nil {
                        backupCompleted = true
                        currentStep = .success
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StepIndicatorItem: View {
    let number: Int
    let title: String
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 32, height: 32)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(textColor)
                }
            }

            Text(title)
                .font(.subheadline)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }

    private var fillColor: Color {
        if isCompleted {
            return .green
        } else if isActive {
            return .blue
        } else {
            return Color(nsColor: .quaternaryLabelColor)
        }
    }

    private var textColor: Color {
        if isActive {
            return .white
        } else {
            return .secondary
        }
    }
}

struct KeySelectionRow: View {
    let key: PGPKeyModel
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(key.displayName)
                        .font(.headline)

                    if let email = key.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(key.shortKeyID)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(key.algorithmDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if key.isExpired {
                        Label("Expired", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if key.isExpiringSoon {
                        Label("Expiring soon", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    BackupWizardView()
        .environment(KeyringService())
}
