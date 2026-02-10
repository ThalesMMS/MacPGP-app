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
        .navigationTitle("Verify Key Fingerprint")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
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

                if key.isVerified {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Already verified")
                        if let date = key.verificationDate {
                            Text("on \(date.formatted(date: .abbreviated, time: .omitted))")
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
            Text("Fingerprint")
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
                        Label("Copy", systemImage: "doc.on.doc")
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
                Text("QR Code")
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
                    Text("Scan this QR code with another device to verify the fingerprint in person.")
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
                Text("Compare with Received Fingerprint")
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
                    Text("Paste or type the fingerprint you received through a trusted channel to verify it matches this key.")
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
                        Text("Paste fingerprint here...")
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
                    Text("Fingerprints Match!")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)

                    Text("The fingerprints are identical. This key can be trusted.")
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
                    Text("Fingerprints Don't Match")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)

                    Text("The fingerprints are different. Do NOT trust this key. It may be compromised or incorrect.")
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

    // MARK: - Verification Actions Section

    @ViewBuilder
    private func verificationActionsSection(viewModel: FingerprintVerificationViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: 12) {
            Text("Mark as Verified")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Text("After verifying the fingerprint through a trusted channel, mark this key as verified. Choose the verification method you used:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Verification Method", selection: $vm.selectedMethod) {
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
                    Label("Mark as Verified", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!viewModel.canMarkAsVerified)
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
                Text("Key Verified Successfully")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("The key \"\(key.displayName)\" has been marked as verified using \(viewModel.selectedMethod.displayName).")
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
        .navigationTitle("Verification Complete")
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
    var comparisonFingerprint = ""
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
        !key.isVerified
    }

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

    func markAsVerified() {
        errorMessage = nil

        do {
            try keyringService.markKeyAsVerified(key, method: selectedMethod)
            isSuccess = true
        } catch {
            errorMessage = "Failed to mark key as verified: \(error.localizedDescription)"
        }
    }

    private func normalizeFingerprint(_ fingerprint: String) -> String {
        fingerprint
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .uppercased()
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

#Preview("Fingerprint Verification") {
    FingerprintVerificationView(key: .preview)
        .environment(KeyringService())
}
