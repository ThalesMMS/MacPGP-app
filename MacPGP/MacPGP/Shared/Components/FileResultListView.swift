import SwiftUI
import AppKit

/// Displays a list of output files with per-file reveal buttons and a summary header.
/// Used by EncryptView, DecryptView, and SignView to show file operation results.
struct FileResultListView: View {
    let files: [URL]
    let successTitle: String

    private var summaryTitle: String {
        let title = files.count == 1 ? singularized(successTitle) : successTitle
        return "\(files.count) \(title.lowercased())"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(summaryTitle, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(files, id: \.path) { file in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.lastPathComponent)
                                    .fontWeight(.medium)
                                Text(file.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([file])
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(12)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func singularized(_ title: String) -> String {
        guard title.hasSuffix("s") else { return title }
        return String(title.dropLast())
    }
}
