import SwiftUI

struct TrustPathView: View {
    let key: PGPKeyModel
    @Environment(TrustService.self) private var trustService
    @Environment(KeyringService.self) private var keyringService
    @State private var trustPaths: [TrustPath] = []
    @State private var effectiveTrust: TrustLevel = .unknown
    @State private var selectedPathIndex: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection

            if !trustPaths.isEmpty {
                Divider()
                pathSelectorSection
                Divider()
                trustPathDisplay
            } else {
                Divider()
                noTrustPathSection
            }

            Divider()
            effectiveTrustSection
        }
        .padding(24)
        .frame(maxWidth: 600, alignment: .leading)
        .onAppear {
            loadTrustPaths()
        }
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Trust Path")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Verification chain for \(key.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pathSelectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available Trust Paths")
                .font(.headline)

            if trustPaths.count > 1 {
                Picker("Trust Path", selection: $selectedPathIndex) {
                    ForEach(trustPaths.indices, id: \.self) { index in
                        let path = trustPaths[index]
                        Text("Path \(index + 1) (\(path.length) hops, \(path.effectiveTrust.displayName))")
                            .tag(index)
                    }
                }
                .pickerStyle(.segmented)
            } else if trustPaths.count == 1 {
                Text("\(trustPaths[0].length) hop\(trustPaths[0].length == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trustPathDisplay: some View {
        VStack(alignment: .leading, spacing: 0) {
            if selectedPathIndex < trustPaths.count {
                let path = trustPaths[selectedPathIndex]

                ForEach(Array(path.nodes.enumerated()), id: \.offset) { index, node in
                    TrustPathNodeView(
                        node: node,
                        isFirst: index == 0,
                        isLast: index == path.nodes.count - 1
                    )

                    if index < path.nodes.count - 1 {
                        trustPathArrow
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var trustPathArrow: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 2, height: 24)
                .padding(.leading, 24)

            Image(systemName: "arrow.down")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("certifies")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var noTrustPathSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("No Trust Path Found")
                        .font(.headline)

                    Text("This key has no certification chain from your trusted keys.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Text("To establish trust:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Set this key's trust level directly", systemImage: "shield.fill")
                    Label("Have a trusted key sign this key", systemImage: "signature")
                    Label("Verify and mark your own key as ultimate trust", systemImage: "checkmark.seal.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private var effectiveTrustSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Effective Trust Level")
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: trustLevelIcon(for: effectiveTrust))
                    .font(.title3)
                    .foregroundStyle(trustLevelColor(for: effectiveTrust))

                VStack(alignment: .leading, spacing: 2) {
                    Text(effectiveTrust.displayName)
                        .font(.body)
                        .fontWeight(.semibold)

                    Text(effectiveTrust.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(trustLevelColor(for: effectiveTrust).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func loadTrustPaths() {
        trustPaths = trustService.findTrustPaths(to: key)
        effectiveTrust = trustService.calculateEffectiveTrust(for: key)
        selectedPathIndex = 0
    }

    private func trustLevelIcon(for level: TrustLevel) -> String {
        switch level {
        case .unknown: return "questionmark.circle"
        case .never: return "xmark.shield"
        case .marginal: return "shield.lefthalf.filled"
        case .full: return "shield.fill"
        case .ultimate: return "checkmark.shield.fill"
        }
    }

    private func trustLevelColor(for level: TrustLevel) -> Color {
        switch level {
        case .unknown: return .gray
        case .never: return .red
        case .marginal: return .orange
        case .full: return .green
        case .ultimate: return .purple
        }
    }
}

// MARK: - Trust Path Node View

struct TrustPathNodeView: View {
    let node: TrustNode
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Trust level indicator
            ZStack {
                Circle()
                    .fill(trustLevelColor(for: node.trustLevel).opacity(0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: node.key.isSecretKey ? "key.fill" : "key")
                    .font(.title3)
                    .foregroundStyle(trustLevelColor(for: node.trustLevel))
            }

            // Key information
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(node.key.displayName)
                        .font(.body)
                        .fontWeight(.medium)

                    if isFirst {
                        Text("Your Key")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }

                    if isLast {
                        Text("Target")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                if let email = node.key.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: trustLevelIcon(for: node.trustLevel))
                    Text(node.trustLevel.displayName)
                }
                .font(.caption)
                .foregroundStyle(trustLevelColor(for: node.trustLevel))
            }

            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(trustLevelColor(for: node.trustLevel).opacity(0.3), lineWidth: 1)
        )
    }

    private func trustLevelIcon(for level: TrustLevel) -> String {
        switch level {
        case .unknown: return "questionmark.circle"
        case .never: return "xmark.shield"
        case .marginal: return "shield.lefthalf.filled"
        case .full: return "shield.fill"
        case .ultimate: return "checkmark.shield.fill"
        }
    }

    private func trustLevelColor(for level: TrustLevel) -> Color {
        switch level {
        case .unknown: return .gray
        case .never: return .red
        case .marginal: return .orange
        case .full: return .green
        case .ultimate: return .purple
        }
    }
}

// MARK: - Preview

#Preview {
    let keyringService = KeyringService()
    let trustService = TrustService(keyringService: keyringService)

    TrustPathView(key: .preview)
        .environment(trustService)
        .environment(keyringService)
        .frame(width: 600, height: 500)
}
