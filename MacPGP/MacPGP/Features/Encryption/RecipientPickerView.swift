import SwiftUI

struct RecipientPickerView: View {
    @Environment(KeyringService.self) private var keyringService
    @Environment(TrustService.self) private var trustService
    @Binding var selectedRecipients: Set<PGPKeyModel>
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("recipients.title")
                .font(.headline)

            if keyringService.publicKeys().isEmpty {
                ContentUnavailableView(
                    "No Keys Available",
                    systemImage: "key",
                    description: Text("recipients.import_first")
                )
                .frame(height: 150)
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
                                isSelected: selectedRecipients.contains(key),
                                trustBadge: trustBadge(for: key),
                                showsTrustWarning: trustService.getTrustWarning(for: key) != nil
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

                Text(String.localizedStringWithFormat(NSLocalizedString("common.selected_count_format", comment: ""), selectedRecipients.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(Array(selectedRecipients)) { key in
                        SelectedRecipientChip(displayName: key.displayName) {
                            selectedRecipients.remove(key)
                        }
                    }
                }

                // Show trust warnings for selected recipients
                if !untrustedRecipients.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("recipients.trust_warnings")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        ForEach(untrustedRecipients) { key in
                            if let warning = trustService.getTrustWarning(for: key) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(key.displayName)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Text(warning)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .padding(.top, 4)
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

    private var untrustedRecipients: [PGPKeyModel] {
        Array(selectedRecipients).filter { key in
            trustService.getTrustWarning(for: key) != nil
        }
    }

    private func toggleSelection(_ key: PGPKeyModel) {
        if selectedRecipients.contains(key) {
            selectedRecipients.remove(key)
        } else {
            selectedRecipients.insert(key)
        }
    }

    private func trustBadge(for key: PGPKeyModel) -> RecipientRow.TrustBadge? {
        guard key.trustLevel != .unknown else { return nil }
        return RecipientRow.TrustBadge(title: key.trustLevel.displayName, color: key.trustLevel.color)
    }
}

#Preview {
    let keyringService = KeyringService()
    let trustService = TrustService(keyringService: keyringService)

    return RecipientPickerView(selectedRecipients: .constant([]))
        .environment(keyringService)
        .environment(trustService)
        .padding()
        .frame(width: 400)
}
