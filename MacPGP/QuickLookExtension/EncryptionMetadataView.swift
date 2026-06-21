import SwiftUI
import RNPKit

/// Quick Look preview for an encrypted OpenPGP file.
///
/// Quick Look is **metadata-only** in v1 (issue #136). The shared App Group
/// projection (`keys.pgp`) is intentionally public-key-only, so the Quick Look
/// process has no secret-key material and cannot decrypt in-preview without
/// reversing that hardening or adding a separately reviewed secure handoff.
/// This surface therefore shows encryption metadata and directs the user to the
/// main app to decrypt.
struct EncryptionMetadataView: View {
    let metadata: PGPMetadataExtractor.Metadata
    let fileURL: URL

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey("quicklook_encryption_pgp_encrypted_file"))
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

            metadataContentView
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private var metadataContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Encryption Information
                MetadataSection(title: "quicklook_encryption_information_section") {
                    if let algorithm = metadata.encryptionAlgorithm {
                        LabelValueRow(
                            localizedLabel: "quicklook_algorithm_label",
                            value: algorithm.description,
                            style: .quickLookMetadata
                        )
                    }

                    LabelValueRow(
                        localizedLabel: "quicklook_integrity_protection_label",
                        value: metadata.isIntegrityProtected ? Self.localized("quicklook_integrity_protection_yes_mdc") : Self.localized("quicklook_no"),
                        style: .quickLookMetadata
                    )

                    if let compression = metadata.compressionAlgorithm {
                        LabelValueRow(
                            localizedLabel: "quicklook_compression_label",
                            value: compression,
                            style: .quickLookMetadata
                        )
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
                    LabelValueRow(
                        localizedLabel: "quicklook_file_size_label",
                        value: PreviewMetadataFormatter.fileSize(metadata.fileSize),
                        style: .quickLookMetadata
                    )

                    if let filename = metadata.filename {
                        LabelValueRow(
                            localizedLabel: "quicklook_original_name_label",
                            value: filename,
                            style: .quickLookMetadata
                        )
                    }

                    if let creationDate = metadata.creationDate {
                        LabelValueRow(
                            localizedLabel: "quicklook_created_label",
                            value: PreviewMetadataFormatter.date(creationDate),
                            style: .quickLookMetadata
                        )
                    }
                }

                // Quick Look is metadata-only: decryption happens in the main app.
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.app")
                        .foregroundColor(.secondary)
                    Text("quicklook_open_in_app_to_decrypt")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            .padding()
        }
    }

    nonisolated private static func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
