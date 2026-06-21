import Darwin
import Foundation

nonisolated enum FinderSyncErrorQueue {
    struct Entry: Equatable {
        let id: String
        let title: String
        let message: String
        let createdAt: TimeInterval

        init(
            id: String = UUID().uuidString,
            title: String,
            message: String,
            createdAt: TimeInterval = Date().timeIntervalSince1970
        ) {
            self.id = id
            self.title = title
            self.message = message
            self.createdAt = createdAt
        }

        init?(payload: [String: Any]) {
            guard let title = payload["title"] as? String,
                  let message = payload["message"] as? String else {
                return nil
            }

            self.id = payload["id"] as? String ?? UUID().uuidString
            self.title = title
            self.message = message
            self.createdAt = payload["createdAt"] as? TimeInterval ?? Date().timeIntervalSince1970
        }

        var payload: [String: Any] {
            [
                "id": id,
                "title": title,
                "message": message,
                "createdAt": createdAt
            ]
        }
    }

    private static let maxPendingErrors = 20
    private static let processLock = NSLock()

    @discardableResult
    static func enqueue(title: String, message: String) -> Bool {
        guard let defaults = UserDefaults(suiteName: SharedConfiguration.appGroupIdentifier) else {
            return false
        }

        return enqueue(Entry(title: title, message: message), defaults: defaults, lockFileURL: defaultLockFileURL())
    }

    @discardableResult
    static func enqueue(_ entry: Entry, defaults: UserDefaults, lockFileURL: URL?) -> Bool {
        withSerializedAccess(lockFileURL: lockFileURL) {
            _ = defaults.synchronize()
            var pendingErrors = defaults.array(forKey: SharedConfiguration.finderSyncErrorsKey) as? [[String: Any]] ?? []
            pendingErrors.append(entry.payload)
            defaults.set(Array(pendingErrors.suffix(maxPendingErrors)), forKey: SharedConfiguration.finderSyncErrorsKey)
            _ = defaults.synchronize()
            return true
        } ?? false
    }

    static func drain() -> [Entry]? {
        guard let defaults = UserDefaults(suiteName: SharedConfiguration.appGroupIdentifier) else {
            return nil
        }

        return drain(defaults: defaults, lockFileURL: defaultLockFileURL())
    }

    static func drain(defaults: UserDefaults, lockFileURL: URL?) -> [Entry]? {
        withSerializedAccess(lockFileURL: lockFileURL) {
            _ = defaults.synchronize()
            let pendingErrors = defaults.array(forKey: SharedConfiguration.finderSyncErrorsKey) as? [[String: Any]] ?? []
            defaults.removeObject(forKey: SharedConfiguration.finderSyncErrorsKey)
            _ = defaults.synchronize()
            return pendingErrors.compactMap(Entry.init(payload:))
        }
    }

    private static func defaultLockFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedConfiguration.appGroupIdentifier)?
            .appendingPathComponent(".finder-sync-errors.lock")
    }

    private static func withSerializedAccess<T>(lockFileURL: URL?, _ work: () -> T) -> T? {
        processLock.lock()
        defer { processLock.unlock() }

        guard let lockFileURL else {
            return work()
        }

        do {
            try FileManager.default.createDirectory(
                at: lockFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            NSLog("[FinderSyncErrorQueue] Failed to create lock directory at \(lockFileURL.deletingLastPathComponent().path): \(error.localizedDescription)")
            return nil
        }

        let descriptor = open(lockFileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            logPOSIXFailure("open", path: lockFileURL.path)
            return nil
        }
        defer { close(descriptor) }

        guard flock(descriptor, LOCK_EX) == 0 else {
            logPOSIXFailure("flock", path: lockFileURL.path)
            return nil
        }
        defer { flock(descriptor, LOCK_UN) }

        return work()
    }

    private static func logPOSIXFailure(_ operation: String, path: String) {
        let errorNumber = errno
        let errorMessage = String(cString: strerror(errorNumber))
        NSLog("[FinderSyncErrorQueue] Failed to \(operation) lock at \(path): \(errorMessage) (\(errorNumber))")
    }
}
