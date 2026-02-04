import SwiftUI

struct CopyableText: View {
    let text: String
    let label: String?
    let monospaced: Bool

    @State private var showCopied = false

    init(_ text: String, label: String? = nil, monospaced: Bool = false) {
        self.text = text
        self.label = label
        self.monospaced = monospaced
    }

    var body: some View {
        HStack {
            if let label = label {
                Text(label)
                    .foregroundStyle(.secondary)
            }

            Text(text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)

            Spacer()

            Button {
                copy()
            } label: {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(showCopied ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

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
    VStack {
        CopyableText("ABC123DEF456", label: "Key ID:", monospaced: true)
    }
    .padding()
    .frame(width: 300)
}
