import SwiftUI

/// A view that prompts the user to enter a passphrase for decrypting a PGP file
/// Used in Quick Look preview to allow decryption without opening the main app
struct PassphrasePromptView: View {
    @Binding var passphrase: String
    @Binding var isPresented: Bool
    let onDecrypt: (String) -> Void

    @State private var isSecure = true

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "lock.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Decrypt Preview")
                        .font(.headline)
                    Text("Enter your passphrase to decrypt this file")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Passphrase field
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Group {
                        if isSecure {
                            SecureField("Passphrase", text: $passphrase)
                        } else {
                            TextField("Passphrase", text: $passphrase)
                        }
                    }
                    .textFieldStyle(.plain)

                    Button {
                        isSecure.toggle()
                    } label: {
                        Image(systemName: isSecure ? "eye" : "eye.slash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    passphrase = ""
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Decrypt") {
                    onDecrypt(passphrase)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(passphrase.isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 10)
    }
}

#Preview {
    PassphrasePromptView(
        passphrase: .constant(""),
        isPresented: .constant(true),
        onDecrypt: { _ in }
    )
    .frame(width: 400, height: 300)
}
