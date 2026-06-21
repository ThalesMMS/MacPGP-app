import Foundation

nonisolated extension String {
    func formattedAsFingerprint() -> String {
        let cleaned = String(filter(\.isHexDigit)).uppercased()
        return stride(from: 0, to: cleaned.count, by: 4).map { i -> String in
            let start = cleaned.index(cleaned.startIndex, offsetBy: i)
            let end = cleaned.index(start, offsetBy: min(4, cleaned.count - i))
            return String(cleaned[start..<end])
        }.joined(separator: " ")
    }

    var normalizedFingerprint: String {
        String(filter(\.isHexDigit)).lowercased()
    }
}
