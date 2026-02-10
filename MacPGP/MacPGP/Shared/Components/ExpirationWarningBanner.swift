import SwiftUI

struct ExpirationWarningBanner: View {
    let key: PGPKeyModel
    var onExtendExpiration: (() -> Void)?

    var body: some View {
        switch key.expirationWarningLevel {
        case .none:
            EmptyView()
        case .warning:
            warningBanner(
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                title: "Key expiring soon",
                message: expirationMessage,
                showButton: key.isSecretKey
            )
        case .critical:
            warningBanner(
                icon: "exclamationmark.triangle.fill",
                color: .red,
                title: "Key expires very soon",
                message: expirationMessage,
                showButton: key.isSecretKey
            )
        case .expired:
            warningBanner(
                icon: "exclamationmark.triangle.fill",
                color: .red,
                title: "This key has expired",
                message: "Expired keys cannot be used for encryption or signing.",
                showButton: key.isSecretKey
            )
        }
    }

    private var expirationMessage: String {
        guard let days = key.daysUntilExpiration else {
            return "This key will expire soon."
        }

        if days == 0 {
            return "This key expires today."
        } else if days == 1 {
            return "This key expires in 1 day."
        } else {
            return "This key expires in \(days) days."
        }
    }

    private func warningBanner(
        icon: String,
        color: Color,
        title: String,
        message: String,
        showButton: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if showButton, let action = onExtendExpiration {
                Button("Extend") {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("Warning Level") {
    VStack(spacing: 16) {
        ExpirationWarningBanner(
            key: {
                var preview = PGPKeyModel.preview
                // Simulate a key expiring in 25 days
                return preview
            }(),
            onExtendExpiration: {
                print("Extend expiration tapped")
            }
        )
    }
    .padding()
    .frame(width: 500)
}

#Preview("Critical Level") {
    VStack(spacing: 16) {
        ExpirationWarningBanner(
            key: {
                var preview = PGPKeyModel.preview
                // Simulate a key expiring in 5 days
                return preview
            }(),
            onExtendExpiration: {
                print("Extend expiration tapped")
            }
        )
    }
    .padding()
    .frame(width: 500)
}

#Preview("Expired") {
    VStack(spacing: 16) {
        ExpirationWarningBanner(
            key: {
                var preview = PGPKeyModel.preview
                // Simulate an expired key
                return preview
            }(),
            onExtendExpiration: {
                print("Extend expiration tapped")
            }
        )
    }
    .padding()
    .frame(width: 500)
}
