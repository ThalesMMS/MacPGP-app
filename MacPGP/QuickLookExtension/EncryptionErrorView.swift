import SwiftUI

struct EncryptionErrorView: View {
    let fileURL: URL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("quicklook_unable_to_read_title")
                .font(.headline)

            Text(fileURL.lastPathComponent)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("quicklook_unable_to_read_message")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(minWidth: 400, minHeight: 300)
        .padding()
    }
}
