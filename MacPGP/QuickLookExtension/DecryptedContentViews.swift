import SwiftUI

struct DecryptedContentView: View {
    private static let maximumInlineDecodeSize = 1_048_576
    private static let maximumInlineImageDecodeSize = 10_485_760

    let filename: String?
    private let content: Content

    private enum Content {
        case text(String)
        case image(NSImage)
        case binary(Int)
    }

    init(data: Data, filename: String?) {
        self.filename = filename

        if data.count <= Self.maximumInlineDecodeSize,
           let text = String(data: data, encoding: .utf8),
           !text.isEmpty {
            content = .text(text)
        } else if data.count <= Self.maximumInlineImageDecodeSize,
                  let nsImage = NSImage(data: data) {
            content = .image(nsImage)
        } else {
            content = .binary(data.count)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch content {
                case .text(let text):
                    TextContentView(text: text)
                case .image(let nsImage):
                    ImageContentView(image: nsImage, filename: filename)
                case .binary(let dataSize):
                    BinaryContentView(dataSize: dataSize, filename: filename)
                }
            }
            .padding()
        }
    }
}

struct TextContentView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                Text("quicklook_text_content")
                    .font(.headline)
                Spacer()
            }

            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct ImageContentView: View {
    let image: NSImage
    let filename: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo.fill")
                    .foregroundColor(.blue)
                Text("quicklook_image_content")
                    .font(.headline)
                if let filename = filename {
                    Text(String(
                        format: NSLocalizedString(
                            "quicklook_filename_parenthesized_format",
                            comment: "Format for showing the decrypted image filename near the content title."
                        ),
                        filename
                    ))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 600, maxHeight: 400)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct BinaryContentView: View {
    let dataSize: Int
    let filename: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("quicklook_binary_content")
                .font(.headline)

            if let filename = filename {
                Text(filename)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text(String(
                format: NSLocalizedString(
                    "quicklook_content_size_format",
                    comment: "Label showing the size of decrypted binary preview content."
                ),
                PreviewMetadataFormatter.fileSize(Int64(dataSize))
            ))
                .font(.body)
                .foregroundColor(.secondary)

            Text("quicklook_binary_preview_unavailable")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
