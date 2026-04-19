import Foundation

enum SecureScopedFileAccess {
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

    static func writeData(
        _ data: Data,
        to url: URL,
        options: Data.WritingOptions = []
    ) throws {
        try withSecurityScopedAccess(to: url) { scopedURL in
            try data.write(to: scopedURL, options: options)
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
