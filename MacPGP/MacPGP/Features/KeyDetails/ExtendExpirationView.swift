import SwiftUI

struct ExtendExpirationView: View {
    let key: PGPKeyModel
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ExtendExpirationViewModel?

    var body: some View {
        Group {
            if let viewModel = viewModel {
                expirationContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ExtendExpirationViewModel(key: key)
            }
        }
    }

    @ViewBuilder
    private func expirationContent(viewModel: ExtendExpirationViewModel) -> some View {
        @Bindable var vm = viewModel

        NavigationStack {
            if viewModel.isSuccess {
                successView(viewModel: viewModel)
            } else {
                formView(viewModel: viewModel)
            }
        }
        .frame(width: 500, height: 500)
    }

    @ViewBuilder
    private func formView(viewModel: ExtendExpirationViewModel) -> some View {
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

                    if let currentExpiration = key.expirationDate {
                        HStack {
                            Text("Current expiration:")
                                .foregroundStyle(.secondary)
                            Text(currentExpiration, style: .date)
                                .foregroundStyle(.primary)
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("New Expiration Date") {
                DatePicker(
                    "Select date",
                    selection: $vm.newExpirationDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)

                Picker("Preset", selection: $vm.selectedPreset) {
                    ForEach(ExpirationPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onChange(of: viewModel.selectedPreset) { _, newPreset in
                    if newPreset != .custom {
                        viewModel.applyPreset(newPreset)
                    }
                }
            }

            Section("Authentication") {
                VStack(alignment: .leading, spacing: 8) {
                    PassphraseField(
                        title: "Passphrase",
                        passphrase: $vm.passphrase
                    )

                    if !viewModel.passphrase.isEmpty {
                        Text("Your passphrase is required to modify the key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !viewModel.validationIssues.isEmpty {
                Section {
                    ForEach(viewModel.validationIssues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(issue.contains("Warning") ? .orange : .red)
                            .font(.caption)
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
        .navigationTitle("Extend Key Expiration")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Extend") {
                    Task {
                        await viewModel.extendExpiration()
                        if viewModel.isSuccess {
                            // Dismiss after a brief delay to show success
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            dismiss()
                        }
                    }
                }
                .disabled(!viewModel.isValid || viewModel.isProcessing)
            }
        }
        .overlay {
            if viewModel.isProcessing {
                processingOverlay()
            }
        }
    }

    @ViewBuilder
    private func processingOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text("Updating expiration date...")
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
    private func successView(viewModel: ExtendExpirationViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Expiration Extended")
                .font(.title)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                Text(key.displayName)
                    .font(.headline)

                if let newDate = viewModel.updatedExpirationDate {
                    HStack {
                        Text("New expiration:")
                        Text(newDate, style: .date)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Key expiration date has been updated", systemImage: "calendar.badge.checkmark")
                }
                .font(.callout)
            }
            .frame(maxWidth: 300)

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
final class ExtendExpirationViewModel {
    let key: PGPKeyModel
    var newExpirationDate: Date
    var passphrase: String = ""
    var selectedPreset: ExpirationPreset = .oneYear

    var isProcessing: Bool = false
    var errorMessage: String?
    var isSuccess: Bool = false
    var updatedExpirationDate: Date?

    private let expirationService = KeyExpirationService.shared

    init(key: PGPKeyModel) {
        self.key = key

        // Default to 1 year from now
        let calendar = Calendar.current
        self.newExpirationDate = calendar.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    }

    var validationIssues: [String] {
        expirationService.validateExpirationDate(newExpirationDate, forKey: key)
    }

    var isValid: Bool {
        !passphrase.isEmpty && validationIssues.filter { !$0.contains("Warning") }.isEmpty
    }

    func applyPreset(_ preset: ExpirationPreset) {
        let calendar = Calendar.current

        switch preset {
        case .sixMonths:
            newExpirationDate = calendar.date(byAdding: .month, value: 6, to: Date()) ?? Date()
        case .oneYear:
            newExpirationDate = calendar.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        case .twoYears:
            newExpirationDate = calendar.date(byAdding: .year, value: 2, to: Date()) ?? Date()
        case .fiveYears:
            newExpirationDate = calendar.date(byAdding: .year, value: 5, to: Date()) ?? Date()
        case .custom:
            // Keep current date
            break
        }

        // Reset to custom when user manually changes the date
        if preset != .custom {
            // This will be set back to custom if the user changes the date picker
            selectedPreset = preset
        }
    }

    @MainActor
    func extendExpiration() async {
        guard isValid else { return }

        isProcessing = true
        errorMessage = nil

        do {
            // Note: The KeyExpirationService currently throws an error because
            // ObjectivePGP doesn't support expiration date modification yet.
            // This is a placeholder implementation that will work once the
            // underlying library support is added.
            let updatedKey = try expirationService.extendExpiration(
                for: key,
                newExpirationDate: newExpirationDate,
                passphrase: passphrase
            )

            // If successful
            updatedExpirationDate = newExpirationDate
            isSuccess = true
        } catch {
            if let operationError = error as? OperationError {
                errorMessage = operationError.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isProcessing = false
    }
}

enum ExpirationPreset: String, CaseIterable, Identifiable {
    case sixMonths = "6months"
    case oneYear = "1year"
    case twoYears = "2years"
    case fiveYears = "5years"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sixMonths:
            return "6 months"
        case .oneYear:
            return "1 year"
        case .twoYears:
            return "2 years"
        case .fiveYears:
            return "5 years"
        case .custom:
            return "Custom"
        }
    }
}

#Preview {
    ExtendExpirationView(key: .preview)
}
