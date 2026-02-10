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

                Text("Encrypt Files")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Select recipients to encrypt the shared files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top)

            Divider()

            // Files section
            VStack(alignment: .leading, spacing: 8) {
                Text("Files to Encrypt")
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
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Spacer()

                Button("Encrypt") {
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
            Text("Recipients")
                .font(.headline)

            if keyringService.publicKeys().isEmpty {
                ContentUnavailableView(
                    "No Keys Available",
                    systemImage: "key",
                    description: Text("Import recipient public keys first")
                )
                .frame(height: 150)
            } else {
                TextField("Search recipients...", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredKeys) { key in
                            RecipientRow(
                                key: key,
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

                Text("Selected (\(selectedRecipients.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(Array(selectedRecipients)) { key in
                        SelectedRecipientChip(key: key) {
                            selectedRecipients.remove(key)
                        }
                    }
                }
            }
        }
    }

    private var filteredKeys: [PGPKeyModel] {
        let keys = keyringService.publicKeys().filter { !$0.isExpired }

        if searchText.isEmpty {
            return keys
        }

        let query = searchText.lowercased()
        return keys.filter {
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

/// Row for displaying a single recipient in the picker
struct RecipientRow: View {
    let key: PGPKeyModel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(key.displayName)
                        .font(.body)
                    if let email = key.email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(String(key.shortKeyID.suffix(8)))
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// Chip view for a selected recipient
struct SelectedRecipientChip: View {
    let key: PGPKeyModel
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(key.displayName)
                .font(.caption)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.15))
        .clipShape(Capsule())
    }
}

/// Flow layout for arranging chips horizontally with wrapping
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, spacing: spacing, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, spacing: spacing, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, spacing: CGFloat, subviews: Subviews) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: width, height: y + rowHeight)
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
