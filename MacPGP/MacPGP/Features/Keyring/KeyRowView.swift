import SwiftUI

struct KeyRowView: View {
    let key: PGPKeyModel
    @Environment(PreferencesManager.self) private var preferences: PreferencesManager?

    private var showKeyID: Bool {
        preferences?.showKeyIDInList ?? true
    }

    var body: some View {
        HStack(spacing: 12) {
            keyIcon

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(key.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if key.isExpired {
                        Text("Expired")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.red.opacity(0.2))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }

                if let email = key.email, !email.isEmpty {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if showKeyID {
                    Text(key.shortKeyID.suffix(8))
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var keyIcon: some View {
        Image(systemName: key.isSecretKey ? "key.fill" : "key")
            .font(.title2)
            .foregroundStyle(key.isSecretKey ? .orange : .secondary)
            .frame(width: 32)
    }
}

#Preview {
    List {
        KeyRowView(key: .preview)
    }
    .frame(width: 300)
}
