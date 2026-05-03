import Foundation

enum PreviewMetadataFormatter {
    static func keyID(_ keyID: String) -> String {
        // Format key ID as: XXXX XXXX XXXX XXXX
        let chunks = stride(from: 0, to: keyID.count, by: 4).map {
            String(keyID.dropFirst($0).prefix(4))
        }
        return chunks.joined(separator: " ")
    }

    static func fileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
