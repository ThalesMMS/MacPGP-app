import SwiftUI

struct PassphraseField: View {
    let title: String
    @Binding var passphrase: String
    var showStrengthIndicator: Bool = false
    var strengthProvider: ((String) -> PassphraseStrength)?

    @State private var isSecure = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Group {
                    if isSecure {
                        SecureField(title, text: $passphrase)
                    } else {
                        TextField(title, text: $passphrase)
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

            if showStrengthIndicator, let strengthProvider = strengthProvider, !passphrase.isEmpty {
                PassphraseStrengthView(strength: strengthProvider(passphrase))
            }
        }
    }
}

#Preview {
    VStack {
        PassphraseField(
            title: "Enter passphrase",
            passphrase: .constant("test123"),
            showStrengthIndicator: true,
            strengthProvider: { passphrase in
                KeyGenerationService.shared.passphraseStrength(passphrase)
            }
        )
    }
    .padding()
    .frame(width: 300)
}
