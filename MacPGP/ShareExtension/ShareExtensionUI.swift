import SwiftUI

/// Main SwiftUI view for the Share Extension
struct ShareExtensionView: View {
    @Environment(ExtensionKeyringService.self) private var keyringService

    let fileURLs: [URL]
    let onEncrypt: (Set<PGPKeyModel>) -> Void
    let onCancel: () -> Void

    @State private var selectedRecipients: Set<PGPKeyModel> = []
    @State private var isEncrypting = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("shareext.encrypt_files")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("shareext.select_recipients")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top)

            Divider()

            // Files section
            VStack(alignment: .leading, spacing: 8) {
                Text("shareext.files_to_encrypt")
                    .font(.headline)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(fileURLs, id: \.self) { url in
                            FileRow(url: url)
                        }
                    }
                }
                .frame(maxHeight: 100)
            }

            Divider()

            // Recipient picker section
            RecipientPicker(selectedRecipients: $selectedRecipients)

            Spacer()

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                Button("shareext.cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Spacer()

                Button("shareext.encrypt") {
                    isEncrypting = true
                    onEncrypt(selectedRecipients)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedRecipients.isEmpty || isEncrypting)
            }
            .padding(.bottom)
        }
        .padding()
        .frame(width: 480, height: 600)
    }
}

/// Row displaying a single file to be encrypted
struct FileRow: View {
    let url: URL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: fileIcon)
                .foregroundStyle(.secondary)

            Text(url.lastPathComponent)
                .font(.body)
                .lineLimit(1)

            Spacer()

            if let fileSize = fileSize {
                Text(fileSize)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var fileIcon: String {
        let pathExtension = url.pathExtension.lowercased()
        switch pathExtension {
        case "txt", "md":
            return "doc.text"
        case "pdf":
            return "doc.fill"
        case "jpg", "jpeg", "png", "gif":
            return "photo"
        case "zip", "tar", "gz":
            return "doc.zipper"
        default:
            return "doc"
        }
    }

    private var fileSize: String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? UInt64 else {
            return nil
        }

        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

/// Recipient picker component for the share extension
struct RecipientPicker: View {
    @Environment(ExtensionKeyringService.self) private var keyringService
    @Binding var selectedRecipients: Set<PGPKeyModel>
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("shareext.recipients")
                .font(.headline)

            if availableRecipients.isEmpty {
                ContentUnavailableView(
                    "No Keys Available",
                    systemImage: "key",
                    description: Text(keyringService.keyAvailabilityMessage ?? "Open MacPGP to import or refresh recipient keys, then try sharing again.")
                )
                .frame(height: 150)
                .onAppear {
                    selectedRecipients.removeAll()
                }
            } else {
                TextField("Search recipients...", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredKeys) { key in
                            RecipientRow(
                                displayName: key.displayName,
                                email: key.email,
                                shortKeyID: key.shortKeyID,
                                isSelected: selectedRecipients.contains(key)
                            ) {
                                toggleSelection(key)
                            }
                        }
                    }
                }
                .frame(height: 200)
            }

            if !selectedRecipients.isEmpty {
                Divider()

                Text(String.localizedStringWithFormat(NSLocalizedString("shareext.selected_count", comment: ""), selectedRecipients.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(Array(selectedRecipients)) { key in
                        SelectedRecipientChip(displayName: key.displayName) {
                            selectedRecipients.remove(key)
                        }
                    }
                }
            }
        }
    }

    private var availableRecipients: [PGPKeyModel] {
        keyringService.publicKeys()
    }

    private var filteredKeys: [PGPKeyModel] {
        if searchText.isEmpty {
            return availableRecipients
        }

        let query = searchText.lowercased()
        return availableRecipients.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.email?.lowercased().contains(query) == true ||
            $0.shortKeyID.lowercased().contains(query)
        }
    }

    private func toggleSelection(_ key: PGPKeyModel) {
        if selectedRecipients.contains(key) {
            selectedRecipients.remove(key)
        } else {
            selectedRecipients.insert(key)
        }
    }
}

#Preview {
    ShareExtensionView(
        fileURLs: [
            URL(fileURLWithPath: "/tmp/document.pdf"),
            URL(fileURLWithPath: "/tmp/image.jpg")
        ],
        onEncrypt: { _ in },
        onCancel: { }
    )
    .environment(ExtensionKeyringService())
}
