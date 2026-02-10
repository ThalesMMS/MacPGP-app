import Foundation
import AppKit

@Observable
final class ClipboardService {
    /// Reads text from the system clipboard
    /// - Returns: The text content if available, nil otherwise
    func readText() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }

    /// Writes text to the system clipboard
    /// - Parameter text: The text to write to clipboard
    /// - Returns: True if successful, false otherwise
    @discardableResult
    func writeText(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    /// Checks if the clipboard contains text
    /// - Returns: True if clipboard has text content, false otherwise
    func hasText() -> Bool {
        return NSPasteboard.general.string(forType: .string) != nil
    }
}
