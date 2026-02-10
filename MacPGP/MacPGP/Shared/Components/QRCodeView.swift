import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let data: String
    let size: CGFloat

    init(_ data: String, size: CGFloat = 200) {
        self.data = data
        self.size = size
    }

    var body: some View {
        if let qrImage = generateQRCode(from: data) {
            Image(nsImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Text("Unable to generate QR code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                )
        }
    }

    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        guard let data = string.data(using: .utf8) else {
            return nil
        }

        filter.message = data
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else {
            return nil
        }

        // Scale up the QR code for better quality
        let scale = size / ciImage.extent.width
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        return nsImage
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("QR Code Preview")
            .font(.headline)

        QRCodeView("A1B2C3D4E5F6789012345678901234567890ABCD", size: 200)

        Text("Test Fingerprint")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
    .frame(width: 300)
}
