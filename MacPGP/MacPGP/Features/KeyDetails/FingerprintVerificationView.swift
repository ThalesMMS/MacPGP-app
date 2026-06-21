import SwiftUI

struct FingerprintVerificationView: View {
    let key: PGPKeyModel
    @Environment(\.dismiss) private var dismiss
    @Environment(KeyringService.self) private var keyringService
    @State private var viewModel: FingerprintVerificationViewModel?

    var body: some View {
        Group {
            if let viewModel = viewModel {
                verificationContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = FingerprintVerificationViewModel(key: key, keyringService: keyringService)
            }
        }
    }

    @ViewBuilder
    private func verificationContent(viewModel: FingerprintVerificationViewModel) -> some View {
        @Bindable var vm = viewModel

        NavigationStack {
            if viewModel.isSuccess {
                successView(viewModel: viewModel)
            } else {
                verificationFormView(viewModel: viewModel)
            }
        }
        .frame(width: 700, height: 750)
    }

    @ViewBuilder
    private func verificationFormView(viewModel: FingerprintVerificationViewModel) -> some View {
        @Bindable var vm = viewModel

        ScrollView {
            VStack(spacing: 20) {
                keyInfoSection
                fingerprintSection(viewModel: viewModel)
                qrCodeSection(viewModel: viewModel)
                comparisonSection(viewModel: viewModel)
                verificationActionsSection(viewModel: viewModel)

                if let error = viewModel.errorMessage {
                    errorSection(error: error)
                }
            }
            .padding(24)
        }
        .navigationTitle("keydetails.verify_key_fingerprint")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("revocation.close") {
                    viewModel.audioService.stop()
                    dismiss()
                }
            }
        }
    }

    // MARK: - Key Information Section

    @ViewBuilder
    private var keyInfoSection: some View {
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

                if key.isVerified {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("keydetails.already_verified")
                        if let date = key.verificationDate {
                            Text(String.localizedStringWithFormat(NSLocalizedString("verification.signed_on_relative_format", comment: ""), date.formatted(date: .abbreviated, time: .omitted)))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.green)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Fingerprint Section

    @ViewBuilder
    private func fingerprintSection(viewModel: FingerprintVerificationViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("common.fingerprint")
                .font(.headline)

            VStack(spacing: 12) {
                Text(key.formattedFingerprint)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                HStack(spacing: 12) {
                    Button(action: { viewModel.copyFingerprint() }) {
                        Label("common.copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button(action: { viewModel.toggleAudioPlayback() }) {
                        Label(
                            viewModel.audioService.isPlaying ? "Stop" : "Read Aloud",
                            systemImage: viewModel.audioService.isPlaying ? "stop.fill" : "speaker.wave.2"
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - QR Code Section

    @ViewBuilder
    private func qrCodeSection(viewModel: FingerprintVerificationViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("common.qr_code")
                    .font(.headline)

                Spacer()

                Button(action: { vm.showQRCode.toggle() }) {
                    Label(
                        vm.showQRCode ? "Hide" : "Show",
                        systemImage: vm.showQRCode ? "chevron.up" : "chevron.down"
                    )
                }
                .buttonStyle(.bordered)
            }

            if vm.showQRCode {
                VStack(spacing: 12) {
                    Text("keydetails.scan_this_qr_code_with_another_device_to")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    QRCodeView(key.fingerprint, size: 200)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .frame(maxWidth: .infinity)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.showQRCode)
    }

    // MARK: - Comparison Section

    @ViewBuilder
    private func comparisonSection(viewModel: FingerprintVerificationViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("keydetails.compare_with_received_fingerprint")
                    .font(.headline)

                Spacer()

                Button(action: { vm.showComparison.toggle() }) {
                    Label(
                        vm.showComparison ? "Hide" : "Show",
                        systemImage: vm.showComparison ? "chevron.up" : "chevron.down"
                    )
                }
                .buttonStyle(.bordered)
            }

            if vm.showComparison {
                VStack(spacing: 12) {
                    Text("keydetails.paste_or_type_the_fingerprint_you_receiv")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    comparisonInputView(viewModel: viewModel)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.showComparison)
    }

    @ViewBuilder
    private func comparisonInputView(viewModel: FingerprintVerificationViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(spacing: 12) {
            TextEditor(text: $vm.comparisonFingerprint)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(height: 100)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if vm.comparisonFingerprint.isEmpty {
                        Text("keydetails.paste_fingerprint_here")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            if !vm.comparisonFingerprint.isEmpty {
                comparisonResultView(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private func comparisonResultView(viewModel: FingerprintVerificationViewModel) -> some View {
        if viewModel.fingerprintsMatch {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text("keydetails.fingerprints_match_2")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)

                    Text("keydetails.the_fingerprints_are_identical_tap_verif")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
        } else {
            HStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 4) {
                    Text("keydetails.fingerprints_don_t_match")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)

                    Text("keydetails.the_fingerprints_are_different_do_not_tr")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
            )
        }
    }

    /// Renders the verification actions block with method selection and the "Mark as Verified" control.
    /// - Parameters:
    ///   - viewModel: The view model supplying verification state and actions used to drive the UI.
    /// - Returns: A view containing guidance text, a segmented picker for selecting the verification method, a prominent "Mark as Verified" button (tinted green) whose enabled state follows the view model's `canMarkAsVerified`, and a contextual helper label shown when marking is disabled and the key is not already verified.

    @ViewBuilder
    private func verificationActionsSection(viewModel: FingerprintVerificationViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: 12) {
            Text("keydetails.mark_as_verified")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Text("keydetails.paste_the_fingerprint_you_received_throu")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("keydetails.verification_method", selection: $vm.selectedMethod) {
                    ForEach([
                        FingerprintVerificationMethod.inPerson,
                        .phone,
                        .qrCode,
                        .trusted
                    ], id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                Button(action: { viewModel.markAsVerified() }) {
                    Label("keydetails.mark_as_verified", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!viewModel.canMarkAsVerified)

                if !viewModel.canMarkAsVerified && !key.isVerified {
                    Label("keydetails.paste_a_matching_fingerprint_to_continue", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
    private func successView(viewModel: FingerprintVerificationViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("keydetails.key_verified_successfully")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(String.localizedStringWithFormat(NSLocalizedString("verification.marked_verified_format", comment: ""), key.displayName, viewModel.selectedMethod.displayName))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button("keygen.done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .navigationTitle("keydetails.verification_complete")
    }
}

// MARK: - View Model

@Observable
final class FingerprintVerificationViewModel {
    let key: PGPKeyModel
    let keyringService: KeyringService
    let audioService = FingerprintAudioService()

    var showQRCode = false
    var showComparison = false
    var comparisonFingerprint = "" {
        didSet {
            if comparisonFingerprint != oldValue {
                errorMessage = nil
            }
        }
    }
    var selectedMethod: FingerprintVerificationMethod = .inPerson
    var errorMessage: String?
    var isSuccess = false

    init(key: PGPKeyModel, keyringService: KeyringService) {
        self.key = key
        self.keyringService = keyringService
    }

    var fingerprintsMatch: Bool {
        guard !comparisonFingerprint.isEmpty else { return false }
        let normalized1 = normalizeFingerprint(key.fingerprint)
        let normalized2 = normalizeFingerprint(comparisonFingerprint)
        return normalized1 == normalized2
    }

    var canMarkAsVerified: Bool {
        !key.isVerified && fingerprintsMatch
    }

    /// Copies the key's fingerprint to the system pasteboard.
    /// 
    /// This replaces the current contents of NSPasteboard.general with the fingerprint string.
    func copyFingerprint() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key.fingerprint, forType: .string)
    }

    func toggleAudioPlayback() {
        if audioService.isPlaying {
            audioService.stop()
        } else {
            audioService.speak(key.fingerprint)
        }
    }

    /// Marks the associated key as verified using the currently selected verification method and updates the view model state.
    /// 
    /// If the precondition to mark the key as verified is not met, sets `errorMessage` to a user-facing prompt and returns without attempting persistence. On successful persistence, sets `isSuccess` to `true`. If persistence fails, sets `errorMessage` to a message describing the failure.
    func markAsVerified() {
        errorMessage = nil

        guard canMarkAsVerified else {
            errorMessage = "Paste a matching fingerprint before marking this key as verified."
            return
        }

        do {
            try keyringService.markKeyAsVerified(key, method: selectedMethod)
            isSuccess = true
        } catch {
            errorMessage = "Failed to mark key as verified: \(error.localizedDescription)"
        }
    }

    private func normalizeFingerprint(_ fingerprint: String) -> String {
        fingerprint.normalizedFingerprint
    }
}

// MARK: - Verification Method Extension

extension FingerprintVerificationMethod {
    var displayName: String {
        switch self {
        case .inPerson:
            return "In Person"
        case .phone:
            return "Phone Call"
        case .qrCode:
            return "QR Code"
        case .trusted:
            return "Trusted Source"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Fingerprint Verification") {
    FingerprintVerificationView(key: .preview)
        .environment(KeyringService())
}
#endif
