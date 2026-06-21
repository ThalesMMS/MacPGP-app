import SwiftUI

struct KeyFingerprintView: View {
    let fingerprint: String
    @State private var showCopied = false
    @State private var showQRCode = false
    @State private var audioService = FingerprintAudioService()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("common.fingerprint")
                    .font(.headline)

                Spacer()

                Button {
                    if audioService.isPlaying {
                        audioService.stop()
                    } else {
                        audioService.speak(fingerprint)
                    }
                } label: {
                    Label(audioService.isPlaying ? "Stop" : "Read Aloud", systemImage: audioService.isPlaying ? "stop.fill" : "speaker.wave.2")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Button {
                    withAnimation {
                        showQRCode.toggle()
                    }
                } label: {
                    Label(showQRCode ? "Hide QR Code" : "Show QR Code", systemImage: "qrcode")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Button {
                    copyFingerprint()
                } label: {
                    Label(showCopied ? "Copied!" : "Copy", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            Text(fingerprint.formattedAsFingerprint())
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if showQRCode {
                VStack(spacing: 8) {
                    QRCodeView(fingerprint, size: 200)
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("keydetails.scan_to_verify_fingerprint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
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
