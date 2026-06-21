import Foundation

/// Thread-safe authorization flag for an in-flight file crypto operation.
///
/// Created per operation and captured by the streaming backend call. Because
/// librnp's file APIs are blocking and Swift task cancellation is cooperative
/// (and does not propagate into a `Task.detached`), the ViewModel cannot stop a
/// running C call. Instead it calls `invalidate()` on cancel or **Lock MacPGP**
/// (from any thread/actor); the operation re-checks `isAuthorized` immediately
/// before atomic promotion and discards its output if it became unauthorized.
/// This is independent of SwiftUI/ViewModel state.
nonisolated final class FileCommitGate: @unchecked Sendable {
    private let lock = NSLock()
    private var authorized = true

    init() {}

    /// Revokes authorization. Idempotent and safe to call from any thread.
    func invalidate() {
        lock.lock()
        authorized = false
        lock.unlock()
    }

    var isAuthorized: Bool {
        lock.lock()
        defer { lock.unlock() }
        return authorized
    }
}

nonisolated enum SecureScopedFileAccess {
    static func withSecurityScopedAccess<T>(
        to url: URL,
        perform: (URL) throws -> T
    ) throws -> T {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            return try perform(url)
        } catch let error as OperationError {
            throw error
        } catch {
            if let failure = fileAccessFailure(for: error) {
                throw failure.operationError(path: url.path)
            }

            throw error
        }
    }

    static func readData(from url: URL) throws -> Data {
        try withSecurityScopedAccess(to: url) { scopedURL in
            try Data(contentsOf: scopedURL)
        }
    }

    static func readPrefix(from url: URL, maxBytes: Int) throws -> Data {
        guard maxBytes > 0 else {
            return Data()
        }

        return try withSecurityScopedAccess(to: url) { scopedURL in
            let fileHandle = try FileHandle(forReadingFrom: scopedURL)
            defer { try? fileHandle.close() }
            return try fileHandle.read(upToCount: maxBytes) ?? Data()
        }
    }

    static func fileSize(of url: URL) throws -> Int64 {
        try withSecurityScopedAccess(to: url) { scopedURL in
            let attributes = try FileManager.default.attributesOfItem(atPath: scopedURL.path)
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }
    }

    static func writeData(
        _ data: Data,
        to url: URL,
        options: Data.WritingOptions = []
    ) throws {
        try withSecurityScopedAccess(to: url) { scopedURL in
            try data.write(to: scopedURL, options: options)
        }
    }

    /// Runs a streaming file operation that writes to a temporary file in the
    /// destination's directory and atomically promotes it to `finalOutput` only on
    /// success. Preserves the `.withoutOverwriting` guarantee (a pre-existing
    /// destination is never replaced or deleted) and cleans up the partial temp file
    /// on any failure. Used so large-file crypto can stream to a path via the backend
    /// without buffering the whole output in memory.
    /// - Parameters:
    ///   - finalOutput: The destination URL to atomically create on success.
    ///   - scope: Optional security-scoped base URL (e.g. the user-chosen output
    ///     directory); defaults to `finalOutput`.
    ///   - write: Closure invoked with the temporary file path to write into.
    /// Thrown when a file crypto operation is cancelled or the session is locked
    /// before its output could be authorized for promotion. Distinct from an
    /// operation failure so callers can treat it as a (silent) cancellation.
    struct CommitCancelledError: Error {}

    static func writeFileWithoutOverwriting(
        finalOutput: URL,
        scopedBy scope: URL?,
        overwrite: Bool = false,
        afterWrite: (() -> Void)? = nil,
        canCommit: () -> Bool = { true },
        write: (_ temporaryPath: String) throws -> Void
    ) throws {
        let scopedURL = scope ?? finalOutput
        let temporaryURL = finalOutput
            .deletingLastPathComponent()
            .appendingPathComponent(".macpgp-\(UUID().uuidString).part")

        try withSecurityScopedAccess(to: scopedURL) { _ in
            do {
                try? FileManager.default.removeItem(at: temporaryURL)
                try write(temporaryURL.path)
                // The streamed output is fully written to the temp file here, before
                // the (fast) atomic promotion. Callers use this to report progress.
                afterWrite?()
                // Authorization gate: librnp's blocking write may have completed
                // after the user cancelled or locked the app. Re-check immediately
                // before promotion so cancelled/locked work never publishes its
                // output. The temporary file is removed by the catch below.
                guard canCommit() else {
                    throw CommitCancelledError()
                }
                if overwrite, FileManager.default.fileExists(atPath: finalOutput.path) {
                    // Atomic replace, used where overwriting is the documented behavior.
                    _ = try FileManager.default.replaceItemAt(finalOutput, withItemAt: temporaryURL)
                } else {
                    // moveItem fails (NSFileWriteFileExists) if the destination already
                    // exists, preserving .withoutOverwriting and never deleting a
                    // pre-existing user file.
                    try FileManager.default.moveItem(at: temporaryURL, to: finalOutput)
                }
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw error
            }
        }
    }

    private enum FileAccessFailure {
        case fileNotFound
        case permissionDenied
        case readOnlyVolume
        case diskFull
        case nameTooLong

        func operationError(path: String) -> OperationError {
            switch self {
            case .fileNotFound:
                return .fileNotFound(path: path)
            case .permissionDenied:
                return .permissionDenied(path: path)
            case .readOnlyVolume:
                return .readOnlyVolume(path: path)
            case .diskFull:
                return .diskFull(path: path)
            case .nameTooLong:
                return .nameTooLong(path: path)
            }
        }
    }

    private static func fileAccessFailure(for error: Error) -> FileAccessFailure? {
        let nsError = error as NSError

        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return .fileNotFound
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return .permissionDenied
            case NSFileWriteVolumeReadOnlyError:
                return .readOnlyVolume
            case NSFileWriteOutOfSpaceError:
                return .diskFull
            case NSFileWriteInvalidFileNameError:
                return .nameTooLong
            default:
                return nil
            }
        }

        guard nsError.domain == NSPOSIXErrorDomain else {
            return nil
        }

        switch nsError.code {
        case Int(POSIXErrorCode.ENOENT.rawValue):
            return .fileNotFound
        case Int(POSIXErrorCode.EACCES.rawValue), Int(POSIXErrorCode.EPERM.rawValue):
            return .permissionDenied
        case Int(POSIXErrorCode.EROFS.rawValue):
            return .readOnlyVolume
        case Int(POSIXErrorCode.ENOSPC.rawValue):
            return .diskFull
        case Int(POSIXErrorCode.ENAMETOOLONG.rawValue):
            return .nameTooLong
        default:
            return nil
        }
    }
}
