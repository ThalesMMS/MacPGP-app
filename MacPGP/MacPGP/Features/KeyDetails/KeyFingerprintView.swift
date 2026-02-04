import SwiftUI

struct KeyFingerprintView: View {
    let fingerprint: String
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fingerprint")
                    .font(.headline)

                Spacer()

                Button {
                    copyFingerprint()
                } label: {
                    Label(showCopied ? "Copied!" : "Copy", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            Text(formattedFingerprint)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var formattedFingerprint: String {
        stride(from: 0, to: fingerprint.count, by: 4).map { i -> String in
            let start = fingerprint.index(fingerprint.startIndex, offsetBy: i)
            let end = fingerprint.index(start, offsetBy: min(4, fingerprint.count - i))
            return String(fingerprint[start..<end])
        }.joined(separator: " ")
    }

    private func copyFingerprint() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fingerprint, forType: .string)

        withAnimation {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

#Preview {
    KeyFingerprintView(fingerprint: "A1B2C3D4E5F6789012345678901234567890ABCD")
        .padding()
        .frame(width: 400)
}
