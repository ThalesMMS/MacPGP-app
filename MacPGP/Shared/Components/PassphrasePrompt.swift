import SwiftUI

extension View {
    func passphrasePromptAlert(
        isPresented: Binding<Bool>,
        passphrase: Binding<String>,
        message: String,
        submitTitle: String,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping () -> Void
    ) -> some View {
        modifier(PassphrasePromptAlertModifier(
            isPresented: isPresented,
            passphrase: passphrase,
            message: message,
            submitTitle: submitTitle,
            onCancel: onCancel,
            onSubmit: onSubmit
        ))
    }
}

private struct PassphrasePromptAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var passphrase: String
    let message: String
    let submitTitle: String
    let onCancel: () -> Void
    let onSubmit: () -> Void

    func body(content: Content) -> some View {
        content.alert("Passphrase Required", isPresented: $isPresented) {
            SecureField("Passphrase", text: $passphrase)
            Button("Cancel", role: .cancel, action: onCancel)
            Button(submitTitle, action: onSubmit)
        } message: {
            Text(message)
        }
    }
}

struct PassphrasePromptCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @Binding var passphrase: String
    let submitTitle: LocalizedStringKey
    var cancelTitle: LocalizedStringKey = "Cancel"
    let onCancel: () -> Void
    let onSubmit: (String) -> Void

    @State private var isSecure = true

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "lock.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            passphraseField

            HStack(spacing: 12) {
                Button(cancelTitle, action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(submitTitle) {
                    onSubmit(passphrase)
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

    private var passphraseField: some View {
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
    }
}
