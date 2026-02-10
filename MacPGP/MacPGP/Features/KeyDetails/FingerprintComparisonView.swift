import SwiftUI

struct FingerprintComparisonView: View {
    let keyFingerprint: String
    @State private var comparisonFingerprint: String = ""
    @State private var showMatch: Bool = false
    @State private var showMismatch: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                instructionsSection

                comparisonGrid

                if !comparisonFingerprint.isEmpty {
                    matchStatusSection
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Compare Fingerprints")
            .frame(width: 600, height: 500)
        }
        .onChange(of: comparisonFingerprint) { _, newValue in
            checkFingerprints()
        }
    }

    // MARK: - Instructions Section

    @ViewBuilder
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("How to Verify")
                    .font(.headline)
            }

            Text("Compare the fingerprint below with the one received through a trusted channel (in person, phone call, or secure message). Paste or type the received fingerprint to check if they match.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Comparison Grid

    @ViewBuilder
    private var comparisonGrid: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left Column - Key's Fingerprint
            VStack(alignment: .leading, spacing: 8) {
                Text("This Key's Fingerprint")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                fingerprintDisplayBox(fingerprint: keyFingerprint, isEditable: false)
            }
            .frame(maxWidth: .infinity)

            // Divider
            Divider()

            // Right Column - Comparison Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Fingerprint to Compare")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                fingerprintInputBox
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func fingerprintDisplayBox(fingerprint: String, isEditable: Bool) -> some View {
        Text(formattedFingerprint(fingerprint))
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 120)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var fingerprintInputBox: some View {
        TextEditor(text: $comparisonFingerprint)
            .font(.system(.body, design: .monospaced))
            .padding(8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 120)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if comparisonFingerprint.isEmpty {
                    Text("Paste or type fingerprint here...")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: - Match Status Section

    @ViewBuilder
    private var matchStatusSection: some View {
        VStack(spacing: 12) {
            if showMatch {
                matchIndicator
            } else if showMismatch {
                mismatchIndicator
            }
        }
    }

    @ViewBuilder
    private var matchIndicator: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Fingerprints Match!")
                    .font(.headline)
                    .foregroundStyle(.green)

                Text("The fingerprints are identical. This key can be trusted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var mismatchIndicator: some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text("Fingerprints Don't Match")
                    .font(.headline)
                    .foregroundStyle(.red)

                Text("The fingerprints are different. Do NOT trust this key. It may be compromised or incorrect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Helper Methods

    private func formattedFingerprint(_ fingerprint: String) -> String {
        stride(from: 0, to: fingerprint.count, by: 4).map { i -> String in
            let start = fingerprint.index(fingerprint.startIndex, offsetBy: i)
            let end = fingerprint.index(start, offsetBy: min(4, fingerprint.count - i))
            return String(fingerprint[start..<end])
        }.joined(separator: " ")
    }

    private func normalizeFingerprint(_ fingerprint: String) -> String {
        // Remove all whitespace, colons, and convert to uppercase
        fingerprint
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .uppercased()
    }

    private func checkFingerprints() {
        let normalizedKey = normalizeFingerprint(keyFingerprint)
        let normalizedComparison = normalizeFingerprint(comparisonFingerprint)

        guard !normalizedComparison.isEmpty else {
            showMatch = false
            showMismatch = false
            return
        }

        if normalizedKey == normalizedComparison {
            showMatch = true
            showMismatch = false
        } else {
            showMatch = false
            showMismatch = true
        }
    }
}

#Preview("Fingerprint Comparison") {
    FingerprintComparisonView(
        keyFingerprint: "A1B2C3D4E5F6789012345678901234567890ABCD"
    )
}
