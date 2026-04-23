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
            Section("Identity") {
                TextField("Full Name", text: $vm.name)
                    .textContentType(.name)
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.fullNameField)

                TextField("Email Address", text: $vm.email)
                    .textContentType(.emailAddress)
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.emailField)

                TextField("Comment (optional)", text: $vm.comment)
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.commentField)
            }

            Section("Key Settings") {
                Picker("Algorithm", selection: Binding(
                    get: { vm.algorithm },
                    set: { vm.updateAlgorithm($0) }
                )) {
                    ForEach([KeyAlgorithm.rsa, .ecdsa, .eddsa]) { algorithm in
                        Text(algorithm.displayName).tag(algorithm)
                    }
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.algorithmValue)

                Picker("Key Size", selection: $vm.keySize) {
                    ForEach(viewModel.availableKeySizes, id: \.self) { size in
                        Text("\(size) bits").tag(size)
                    }
                }
                .disabled(viewModel.availableKeySizes.count == 1)
                .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.keySizePicker)

                if vm.algorithm == .ecdsa {
                    Text("Creates an ECDSA primary key with an ECDH subkey for encryption.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if vm.algorithm == .eddsa {
                    Text("Creates an Ed25519 primary key with an X25519 subkey for encryption.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Never expires", isOn: $vm.neverExpires)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.neverExpiresToggle)

                if !viewModel.neverExpires {
                    Picker("Expires in", selection: $vm.expirationMonths) {
                        Text("6 months").tag(6)
                        Text("1 year").tag(12)
                        Text("2 years").tag(24)
                        Text("5 years").tag(60)
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.expirationPicker)
                }
            }

            Section("Passphrase") {
                SecureField("Passphrase", text: $vm.passphrase)
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.passphraseField)

                SecureField("Confirm Passphrase", text: $vm.confirmPassphrase)
                    .accessibilityIdentifier(AccessibilityIdentifiers.KeyGeneration.confirmPassphraseField)

                if !viewModel.passphrase.isEmpty {
                    PassphraseStrengthView(strength: viewModel.passphraseStrength)

                    if !viewModel.passphraseMatch && !viewModel.confirmPassphrase.isEmpty {
                        Text("Passphrases do not match")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Toggle("Store passphrase in Keychain", isOn: $vm.storeInKeychain)
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
        .navigationTitle("Generate New Key")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Generate") {
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

                Text("Generating key...")
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
    private func successView(key: PGPKeyModel, viewModel: KeyGenerationViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Key Generated Successfully")
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
                    Label("Your key has been added to the keyring", systemImage: "key.fill")
                    if viewModel.storeInKeychain {
                        Label("Passphrase stored in Keychain", systemImage: "lock.shield.fill")
                    }
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

struct PassphraseStrengthView: View {
    let strength: PassphraseStrength

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Strength: \(strength.description)")
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
