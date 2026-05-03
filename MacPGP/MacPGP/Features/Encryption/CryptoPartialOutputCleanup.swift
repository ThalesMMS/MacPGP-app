import Foundation

/// Utilities for deterministically cleaning up any partially-written output artifacts
/// after a crypto operation fails or is cancelled.
///
/// Rationale:
/// - Decrypt (file mode) can produce multiple output files; if any one fails, any
///   previously-produced outputs should be removed.
/// - Encrypt (file mode) can also produce multiple outputs; cleanup is symmetric.
/// - Text mode produces no file artifacts; no cleanup required.
///
/// This is intentionally minimal and non-throwing: cleanup is best-effort.
enum CryptoPartialOutputCleanup {
    /// Removes each URL using FileManager. Any errors are ignored.
    static func removeFiles(_ urls: [URL], fileManager: FileManager = .default) {
        for url in urls {
            try? fileManager.removeItem(at: url)
        }
    }
}
