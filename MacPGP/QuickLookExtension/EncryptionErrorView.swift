import SwiftUI

struct EncryptionErrorView: View {
    let fileURL: URL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Unable to Read Encrypted File")
                .font(.headline)

            Text(fileURL.lastPathComponent)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("MacPGP could not display this preview. Open the file in MacPGP to inspect it.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(minWidth: 400, minHeight: 300)
        .padding()
    }
}
