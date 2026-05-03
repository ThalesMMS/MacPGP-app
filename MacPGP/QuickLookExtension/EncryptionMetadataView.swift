import SwiftUI
import RNPKit

struct EncryptionMetadataView: View {
    let metadata: PGPMetadataExtractor.Metadata
    let fileURL: URL

    @State private var showPassphrasePrompt = false
    @State private var passphrase = ""
    @State private var decryptedData: Data?
    @State private var decryptionError: String?
    @State private var isDecrypting = false
    @State private var decryptionUnavailableMessage: String?
    @State private var decryptionTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: decryptedData != nil ? "lock.open.fill" : "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundColor(decryptedData != nil ? .green : .blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(decryptedData != nil ? "quicklook_encryption_decrypted_content" : "quicklook_encryption_pgp_encrypted_file"))
                        .font(.headline)
                    Text(fileURL.lastPathComponent)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content area - show decrypted content or metadata
            if let decryptedData = decryptedData {
                DecryptedContentView(data: decryptedData, filename: metadata.filename)
            } else {
                metadataContentView
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .task {
            await refreshKeyAvailability()
        }
        .overlay(
            Group {
                if showPassphrasePrompt {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            dismissPassphrasePrompt()
                        }

                    PassphrasePromptView(
                        passphrase: $passphrase,
                        isPresented: passphrasePromptBinding,
                        onDecrypt: { enteredPassphrase in
                            handleDecryption(passphrase: enteredPassphrase)
                        }
                    )
                    .overlay(
                        Group {
                            if isDecrypting {
                                VStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("quicklook_decrypting")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else if let error = decryptionError {
                                VStack(spacing: 8) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                    }
                                }
                                .padding()
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.top, 8)
                            }
                        }
                        .offset(y: 100)
                    )
                }
            }
        )
        .onDisappear {
            cancelDecryption()
        }
    }

    private var metadataContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Encryption Information
                MetadataSection(title: "quicklook_encryption_information_section") {
                    if let algorithm = metadata.encryptionAlgorithm {
                        MetadataRow(label: "quicklook_algorithm_label", value: algorithm.description)
                    }

                    MetadataRow(
                        label: "quicklook_integrity_protection_label",
                        value: metadata.isIntegrityProtected ? Self.localized("quicklook_integrity_protection_yes_mdc") : Self.localized("quicklook_no")
                    )

                    if let compression = metadata.compressionAlgorithm {
                        MetadataRow(label: "quicklook_compression_label", value: compression)
                    }
                }

                // Recipients
                MetadataSection(title: "quicklook_recipients_section") {
                    if metadata.recipientKeyIDs.isEmpty {
                        Text("quicklook_no_recipient_information")
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        ForEach(metadata.recipientKeyIDs, id: \.self) { keyID in
                            HStack {
                                Image(systemName: "key.fill")
                                    .foregroundColor(.blue)
                                Text(PreviewMetadataFormatter.keyID(keyID))
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }

                // File Information
                MetadataSection(title: "quicklook_file_information_section") {
                    MetadataRow(label: "quicklook_file_size_label", value: PreviewMetadataFormatter.fileSize(metadata.fileSize))

                    if let filename = metadata.filename {
                        MetadataRow(label: "quicklook_original_name_label", value: filename)
                    }

                    if let creationDate = metadata.creationDate {
                        MetadataRow(label: "quicklook_created_label", value: PreviewMetadataFormatter.date(creationDate))
                    }
                }

                if let message = decryptionUnavailableMessage {
                    DecryptionUnavailableView(message: message)
                        .padding(.top, 8)
                } else {
                    // Decrypt button
                    Button {
                        showPassphrasePrompt = true
                    } label: {
                        HStack {
                            Image(systemName: "lock.open.fill")
                            Text("quicklook_decrypt_preview")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
            }
            .padding()
        }
    }

    private var passphrasePromptBinding: Binding<Bool> {
        Binding(
            get: { showPassphrasePrompt },
            set: { isPresented in
                if isPresented {
                    showPassphrasePrompt = true
                } else {
                    dismissPassphrasePrompt()
                }
            }
        )
    }

    private func refreshKeyAvailability() async {
        do {
            let keys = try await Task.detached(priority: .utility) {
                try Self.loadKeysFromKeyring()
            }.value
            if keys.contains(where: { $0.isSecret }) {
                decryptionUnavailableMessage = nil
            } else {
                decryptionUnavailableMessage = Self.localized("quicklook_decryption_unavailable_no_secret_keys")
            }
        } catch {
            Self.logNonSensitiveError("Failed to check shared keys", error: error)
            decryptionUnavailableMessage = Self.localized("quicklook_decryption_unavailable_key_load_failed")
        }
    }

    private func handleDecryption(passphrase: String) {
        decryptionTask?.cancel()

        let fileURL = fileURL

        decryptionTask = Task.detached(priority: .userInitiated) {
            await MainActor.run {
                guard !Task.isCancelled else { return }
                isDecrypting = true
                decryptionError = nil
            }

            do {
                // Load the encrypted file data
                let encryptedData: Data
                do {
                    encryptedData = try Data(contentsOf: fileURL)
                } catch {
                    Self.logNonSensitiveError("Failed to read encrypted file", error: error)
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        isDecrypting = false
                        showPassphrasePrompt = true
                        self.passphrase = ""
                        decryptionTask = nil
                        decryptionError = Self.localized("quicklook_read_file_failed")
                    }
                    return
                }
                guard !Task.isCancelled else { return }

                // Load keys from the shared App Group container
                let keys = try Self.loadKeysFromKeyring()
                guard !Task.isCancelled else { return }

                do {
                    let result = try PreviewDecrypter.decrypt(
                        encryptedData: encryptedData,
                        keys: keys,
                        passphrase: passphrase
                    )
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.decryptedData = result.decryptedData
                        self.showPassphrasePrompt = false
                        self.passphrase = ""
                        self.isDecrypting = false
                        self.decryptionError = nil
                        self.decryptionTask = nil
                    }
                } catch let error as PreviewDecrypter.DecryptError {
                    let errorMessage: String
                    switch error {
                    case .noSecretKeys:
                        errorMessage = Self.localized("quicklook_decryption_unavailable_no_secret_keys")
                    case .invalidPassphrase:
                        errorMessage = Self.localized("quicklook_invalid_passphrase")
                    case .unableToDecrypt:
                        errorMessage = Self.localized("quicklook_unable_to_decrypt_check_passphrase_keys")
                    }

                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        isDecrypting = false
                        decryptionError = errorMessage
                        decryptionTask = nil
                    }
                }

            } catch {
                guard !Task.isCancelled else { return }
                Self.logNonSensitiveError("Failed to decrypt preview", error: error)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    isDecrypting = false
                    decryptionTask = nil
                    decryptionError = Self.localized("quicklook_decrypt_preview_failed")
                }
            }
        }
    }

    private func dismissPassphrasePrompt() {
        cancelDecryption()
        showPassphrasePrompt = false
        passphrase = ""
        decryptionError = nil
    }

    private func cancelDecryption() {
        decryptionTask?.cancel()
        decryptionTask = nil
        isDecrypting = false
    }

    nonisolated private static func loadKeysFromKeyring() throws -> [Key] {
        try SharedKeyringLoader.loadKeys()
    }

    nonisolated private static func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    nonisolated private static func logNonSensitiveError(_ context: String, error: Error) {
        let nsError = error as NSError
        NSLog("QuickLookExtension: \(context) (errorType: \(String(describing: type(of: error))), code: \(nsError.code))")
    }

}
