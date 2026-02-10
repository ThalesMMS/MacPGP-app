import SwiftUI

struct TrustLevelPickerView: View {
    let key: PGPKeyModel
    @Environment(\.dismiss) private var dismiss
    @Environment(KeyringService.self) private var keyringService
    @State private var viewModel: TrustLevelPickerViewModel?

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

        ScrollView {
            VStack(spacing: 20) {
                keyInfoSection
                trustLevelSection(viewModel: viewModel)
                trustDescriptionSection(viewModel: viewModel)
                warningSection(viewModel: viewModel)
                saveButtonSection(viewModel: viewModel)

                if let error = viewModel.errorMessage {
                    errorSection(error: error)
                }
            }
            .padding(24)
        }
        .navigationTitle("Set Trust Level")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Key Information Section

    @ViewBuilder
    private var keyInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key Information")
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
                    Text("Current Trust: \(key.trustLevel.displayName)")
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
            Text("Trust Level")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Select how much you trust this key to certify other keys:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Trust Level", selection: $vm.selectedTrustLevel) {
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
            Text("What This Means")
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

                    if viewModel.selectedTrustLevel.canCertify {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Can certify other keys")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer()
            }
            .padding(12)
            .background(trustLevelColor(for: viewModel.selectedTrustLevel).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(trustLevelColor(for: viewModel.selectedTrustLevel).opacity(0.3), lineWidth: 1)
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
                    Text("Ultimate Trust Warning")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)

                    Text("Ultimate trust should only be assigned to your own keys. This level indicates absolute trust in the key's ability to certify other keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        } else {
            EmptyView()
        }
    }

    // MARK: - Save Button Section

    @ViewBuilder
    private func saveButtonSection(viewModel: TrustLevelPickerViewModel) -> some View {
        VStack(spacing: 8) {
            Button(action: { viewModel.saveTrustLevel() }) {
                Label("Save Trust Level", systemImage: "shield.checkered")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(trustLevelColor(for: viewModel.selectedTrustLevel))
            .disabled(!viewModel.hasChanged)

            if !viewModel.hasChanged {
                Text("No changes to save")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                .foregroundStyle(trustLevelColor(for: viewModel.selectedTrustLevel))

            VStack(spacing: 8) {
                Text("Trust Level Updated")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("The trust level for \"\(key.displayName)\" has been set to \(viewModel.selectedTrustLevel.displayName).")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .navigationTitle("Trust Level Updated")
    }

    // MARK: - Helper Functions

    @ViewBuilder
    private func trustLevelIcon(for level: TrustLevel) -> some View {
        Image(systemName: trustLevelIconName(for: level))
            .foregroundStyle(trustLevelColor(for: level))
    }

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
}

// MARK: - View Model

@Observable
final class TrustLevelPickerViewModel {
    let key: PGPKeyModel
    let keyringService: KeyringService

    var selectedTrustLevel: TrustLevel
    var errorMessage: String?
    var isSuccess = false

    private let initialTrustLevel: TrustLevel

    init(key: PGPKeyModel, keyringService: KeyringService) {
        self.key = key
        self.keyringService = keyringService
        self.selectedTrustLevel = key.trustLevel
        self.initialTrustLevel = key.trustLevel
    }

    var hasChanged: Bool {
        selectedTrustLevel != initialTrustLevel
    }

    func saveTrustLevel() {
        errorMessage = nil

        do {
            try keyringService.updateTrustLevel(key, trustLevel: selectedTrustLevel)
            isSuccess = true
        } catch {
            errorMessage = "Failed to update trust level: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview

#Preview("Trust Level Picker") {
    TrustLevelPickerView(key: .preview)
        .environment(KeyringService())
}
