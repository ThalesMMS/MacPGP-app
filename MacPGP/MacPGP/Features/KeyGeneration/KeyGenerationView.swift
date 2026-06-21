import SwiftUI

struct KeyGenerationView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: KeyGenerationViewModel?

    var body: some View {
        Group {
            if let viewModel = viewModel {
                generationContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = KeyGenerationViewModel(keyringService: keyringService)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPGPDidLock)) { _ in
            viewModel?.handleLock()
        }
    }

    @ViewBuilder
    private func generationContent(viewModel: KeyGenerationViewModel) -> some View {
        @Bindable var vm = viewModel

        NavigationStack {
            if let generatedKey = viewModel.generatedKey {
                successView(key: generatedKey, viewModel: viewModel)
            } else {
                formView(viewModel: viewModel)
            }
        }
        .frame(width: 500, height: 600)
    }

    /// Builds the grouped form UI for entering identity, key settings, and passphrase details used to generate a new cryptographic key.
    /// - Parameter viewModel: The `KeyGenerationViewModel` bound to the form fields.
    /// - Returns: A view containing the key generation form with identity fields, algorithm and expiry controls, passphrase inputs and strength indicator, error display, and toolbar actions for canceling or starting generation.
    @ViewBuilder
    private func formView(viewModel: KeyGenerationViewModel) -> some View {
        @Bindable var vm = viewModel

        Form {
            Section("keygen.identity") {
                TextField("Full Name", text: $vm.name)
                    .textContentType(.name)
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.fullNameField)

                TextField("Email Address", text: $vm.email)
                    .textContentType(.emailAddress)
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.emailField)

                TextField("Comment (optional)", text: $vm.comment)
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.commentField)
            }

            Section("keygen.key_settings") {
                Picker("keygen.algorithm", selection: Binding(
                    get: { vm.algorithm },
                    set: { vm.updateAlgorithm($0) }
                )) {
                    ForEach([KeyAlgorithm.rsa, .ecdsa, .eddsa]) { algorithm in
                        Text(algorithm.displayName).tag(algorithm)
                    }
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.algorithmValue)

                Picker("keygen.key_size", selection: $vm.keySize) {
                    ForEach(viewModel.availableKeySizes, id: \.self) { size in
                        Text(String.localizedStringWithFormat(NSLocalizedString("keygen.bits_format", comment: ""), size)).tag(size)
                    }
                }
                .disabled(viewModel.availableKeySizes.count == 1)
                .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.keySizePicker)

                if vm.algorithm == .ecdsa {
                    Text("keygen.creates_an_ecdsa_primary_key_with_an_ecd")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if vm.algorithm == .eddsa {
                    Text("keygen.creates_an_ed25519_primary_key_with_an_x")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("keygen.never_expires", isOn: $vm.neverExpires)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.neverExpiresToggle)

                if !viewModel.neverExpires {
                    Picker("keygen.expires_in", selection: $vm.expirationMonths) {
                        Text("keygen.expiry_6_months").tag(6)
                        Text("keygen.expiry_1_year").tag(12)
                        Text("keygen.expiry_2_years").tag(24)
                        Text("keygen.expiry_5_years").tag(60)
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.expirationPicker)
                }
            }

            Section("keygen.passphrase") {
                SecureField("keygen.passphrase", text: $vm.passphrase)
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.passphraseField)

                SecureField("Confirm Passphrase", text: $vm.confirmPassphrase)
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.confirmPassphraseField)

                if !viewModel.passphrase.isEmpty {
                    PassphraseStrengthView(strength: viewModel.passphraseStrength)

                    if !viewModel.passphraseMatch && !viewModel.confirmPassphrase.isEmpty {
                        Text("keygen.passphrases_no_match")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Toggle("keygen.store_in_keychain", isOn: $vm.storeInKeychain)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.storePassphraseToggle)
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("keyring.generate_new_key")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("keygen.cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("keygen.generate") {
                    Task {
                        await viewModel.generate()
                    }
                }
                .disabled(!viewModel.isValid || viewModel.isGenerating)
            }
        }
        .overlay {
            if viewModel.isGenerating {
                generatingOverlay(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private func generatingOverlay(viewModel: KeyGenerationViewModel) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text("keygen.generating")
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
    private func successView(key: PGPKeyModel, viewModel: KeyGenerationViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("keygen.key_generated_successfully")
                .font(.title)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
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
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("keygen.your_key_has_been_added_to_the_keyring", systemImage: "key.fill")
                    if viewModel.storeInKeychain {
                        Label("keygen.passphrase_stored_in_keychain", systemImage: "lock.shield.fill")
                    }
                }
                .font(.callout)
            }
            .frame(maxWidth: 300)

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

struct PassphraseStrengthView: View {
    let strength: PassphraseStrength

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String.localizedStringWithFormat(NSLocalizedString("keygen.strength_format", comment: ""), strength.description))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(strengthColor)
                        .frame(width: geometry.size.width * CGFloat(strength.rawValue) / 5)
                }
            }
            .frame(height: 4)
        }
    }

    private var strengthColor: Color {
        switch strength {
        case .none: return .gray
        case .veryWeak: return .red
        case .weak: return .orange
        case .fair: return .yellow
        case .good: return .green
        case .strong: return .blue
        }
    }
}

#Preview {
    KeyGenerationView()
        .environment(KeyringService())
}
