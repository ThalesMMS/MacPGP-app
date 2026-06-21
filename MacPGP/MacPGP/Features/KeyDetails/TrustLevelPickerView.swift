import SwiftUI

struct TrustLevelPickerView: View {
    let key: PGPKeyModel
    let onTrustLevelUpdated: (PGPKeyModel) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(KeyringService.self) private var keyringService
    @State private var viewModel: TrustLevelPickerViewModel?

    init(key: PGPKeyModel, onTrustLevelUpdated: @escaping (PGPKeyModel) -> Void = { _ in }) {
        self.key = key
        self.onTrustLevelUpdated = onTrustLevelUpdated
    }

    var body: some View {
        Group {
            if let viewModel = viewModel {
                pickerContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = TrustLevelPickerViewModel(key: key, keyringService: keyringService)
            }
        }
    }

    @ViewBuilder
    private func pickerContent(viewModel: TrustLevelPickerViewModel) -> some View {
        @Bindable var vm = viewModel

        NavigationStack {
            if viewModel.isSuccess {
                successView(viewModel: viewModel)
            } else {
                pickerFormView(viewModel: viewModel)
            }
        }
        .frame(width: 600, height: 550)
    }

    @ViewBuilder
    private func pickerFormView(viewModel: TrustLevelPickerViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    keyInfoSection(key: viewModel.key)
                    trustLevelSection(viewModel: viewModel)
                    trustDescriptionSection(viewModel: viewModel)
                    warningSection(viewModel: viewModel)
                    saveStatusSection(viewModel: viewModel)

                    if let error = viewModel.errorMessage {
                        errorSection(error: error)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("keygen.cancel") {
                    dismiss()
                }

                Spacer()

                Button("keydetails.save_trust_level") {
                    viewModel.saveTrustLevel(onSuccess: onTrustLevelUpdated)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasChanged)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .navigationTitle("keydetails.set_trust_level")
    }

    // MARK: - Key Information Section

    @ViewBuilder
    private func keyInfoSection(key: PGPKeyModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("trust.key_information")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(key.displayName)
                    .font(.title3)
                    .fontWeight(.semibold)

                if let email = key.email {
                    Text(email)
                        .foregroundStyle(.secondary)
                }

                Text(key.shortKeyID)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.tertiary)

                HStack(spacing: 6) {
                    Image(systemName: "shield")
                    Text(String.localizedStringWithFormat(NSLocalizedString("trust.current_format", comment: ""), key.trustLevel.displayName))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Trust Level Section

    @ViewBuilder
    private func trustLevelSection(viewModel: TrustLevelPickerViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: 12) {
            Text("trust.trust_level")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("trust.select_trust_message")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("trust.trust_level", selection: $vm.selectedTrustLevel) {
                    ForEach(TrustLevel.allCases) { level in
                        HStack {
                            trustLevelIcon(for: level)
                            Text(level.displayName)
                        }
                        .tag(level)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Trust Description Section

    @ViewBuilder
    private func trustDescriptionSection(viewModel: TrustLevelPickerViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("trust.what_this_means")
                .font(.headline)

            HStack(spacing: 12) {
                trustLevelIcon(for: viewModel.selectedTrustLevel)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.selectedTrustLevel.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(viewModel.selectedTrustLevel.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            AccessibilityIdentifiers.TrustLevelPicker.description(
                                token: viewModel.selectedTrustLevel.accessibilityToken
                            )
                        )

                    if viewModel.selectedTrustLevel.canCertify {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("trust.can_certify")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .accessibilityIdentifier(
                                    AccessibilityIdentifiers.TrustLevelPicker.canCertifyDescription(
                                        token: viewModel.selectedTrustLevel.accessibilityToken
                                    )
                                )
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer()
            }
            .padding(12)
            .background(viewModel.selectedTrustLevel.color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(viewModel.selectedTrustLevel.color.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Warning Section

    @ViewBuilder
    private func warningSection(viewModel: TrustLevelPickerViewModel) -> some View {
        if viewModel.selectedTrustLevel == .ultimate {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("trust.ultimate_warning")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)

                    Text("trust.ultimate_warning_message")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            AccessibilityIdentifiers.TrustLevelPicker.ultimateTrustWarningDescription
                        )
                }

                Spacer()
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Save Status Section

    @ViewBuilder
    private func saveStatusSection(viewModel: TrustLevelPickerViewModel) -> some View {
        if !viewModel.hasChanged {
            Text("keydetails.no_changes_to_save")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Error Section

    @ViewBuilder
    private func errorSection(error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(error)
                .font(.caption)
                .foregroundStyle(.red)

            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Success View

    @ViewBuilder
    private func successView(viewModel: TrustLevelPickerViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "shield.checkered")
                .font(.system(size: 64))
                .foregroundStyle(viewModel.selectedTrustLevel.color)

            VStack(spacing: 8) {
                Text("keydetails.trust_level_updated")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(String.localizedStringWithFormat(NSLocalizedString("trust.set_to_format", comment: ""), viewModel.key.displayName, viewModel.selectedTrustLevel.displayName))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .accessibilityIdentifier(
                        AccessibilityIdentifiers.TrustLevelPicker.trustLevelUpdatedMessage
                    )
            }

            Spacer()

            Button("keygen.done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .navigationTitle("keydetails.trust_level_updated")
    }

    // MARK: - Helper Functions

    @ViewBuilder
    private func trustLevelIcon(for level: TrustLevel) -> some View {
        Image(systemName: level.iconName)
            .foregroundStyle(level.color)
    }
}

// MARK: - View Model

@Observable
final class TrustLevelPickerViewModel {
    private(set) var key: PGPKeyModel
    let keyringService: KeyringService

    var selectedTrustLevel: TrustLevel
    var errorMessage: String?
    var isSuccess = false

    private let initialTrustLevel: TrustLevel

    init(key: PGPKeyModel, keyringService: KeyringService) {
        let currentKey = keyringService.key(withFingerprint: key.fingerprint) ?? key
        self.key = currentKey
        self.keyringService = keyringService
        self.selectedTrustLevel = currentKey.trustLevel
        self.initialTrustLevel = currentKey.trustLevel
    }

    var hasChanged: Bool {
        selectedTrustLevel != initialTrustLevel
    }

    func saveTrustLevel(onSuccess: (PGPKeyModel) -> Void = { _ in }) {
        errorMessage = nil

        do {
            try keyringService.updateTrustLevel(key, trustLevel: selectedTrustLevel)
            key = keyringService.key(withFingerprint: key.fingerprint) ?? key
            isSuccess = true
            onSuccess(key)
        } catch {
            errorMessage = "Failed to update trust level: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Trust Level Picker") {
    TrustLevelPickerView(key: .preview)
        .environment(KeyringService())
}
#endif
