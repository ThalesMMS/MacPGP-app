import Foundation
import Testing
@testable import MacPGP

@Suite("Finder Sync error queue")
struct FinderSyncErrorQueueTests {
    @Test("concurrent enqueues retain all Finder Sync errors")
    func concurrentEnqueuesRetainAllErrors() throws {
        let context = try makeQueueContext()
        defer { context.cleanup() }
        let entries = (0..<20).map { index in
            FinderSyncErrorQueue.Entry(
                id: "error-\(index)",
                title: "Title \(index)",
                message: "Message \(index)",
                createdAt: TimeInterval(index)
            )
        }

        DispatchQueue.concurrentPerform(iterations: entries.count) { offset in
            let index = entries.count - offset - 1
            FinderSyncErrorQueue.enqueue(entries[index], defaults: context.defaults, lockFileURL: context.lockFileURL)
        }

        let drained = try #require(FinderSyncErrorQueue.drain(defaults: context.defaults, lockFileURL: context.lockFileURL))

        #expect(drained.count == entries.count)
        #expect(Set(drained.map(\.id)) == Set(entries.map(\.id)))
        #expect(try #require(FinderSyncErrorQueue.drain(defaults: context.defaults, lockFileURL: context.lockFileURL)).isEmpty)
    }

    @Test("queue keeps only the newest pending Finder Sync errors")
    func queueKeepsOnlyNewestPendingErrors() throws {
        let context = try makeQueueContext()
        defer { context.cleanup() }

        for index in 0..<25 {
            FinderSyncErrorQueue.enqueue(
                FinderSyncErrorQueue.Entry(
                    id: "error-\(index)",
                    title: "Title \(index)",
                    message: "Message \(index)",
                    createdAt: TimeInterval(index)
                ),
                defaults: context.defaults,
                lockFileURL: context.lockFileURL
            )
        }

        let drained = try #require(FinderSyncErrorQueue.drain(defaults: context.defaults, lockFileURL: context.lockFileURL))

        #expect(drained.map(\.id) == (5..<25).map { "error-\($0)" })
    }

    @Test("enqueue aborts when cross-process lock cannot be opened")
    func enqueueAbortsWhenCrossProcessLockCannotBeOpened() throws {
        let context = try makeQueueContext()
        defer { context.cleanup() }
        let invalidLockFileURL = URL(fileURLWithPath: "/dev/null/finder-sync-errors.lock")

        let didEnqueue = FinderSyncErrorQueue.enqueue(
            FinderSyncErrorQueue.Entry(id: "failed-lock", title: "Title", message: "Message"),
            defaults: context.defaults,
            lockFileURL: invalidLockFileURL
        )

        #expect(!didEnqueue)
        #expect(context.defaults.array(forKey: SharedConfiguration.finderSyncErrorsKey) == nil)
    }

    @Test("drain aborts without removing entries when cross-process lock cannot be opened")
    func drainAbortsWithoutRemovingEntriesWhenCrossProcessLockCannotBeOpened() throws {
        let context = try makeQueueContext()
        defer { context.cleanup() }
        let entry = FinderSyncErrorQueue.Entry(id: "pending", title: "Title", message: "Message")
        let invalidLockFileURL = URL(fileURLWithPath: "/dev/null/finder-sync-errors.lock")
        context.defaults.set([entry.payload], forKey: SharedConfiguration.finderSyncErrorsKey)

        let drained = FinderSyncErrorQueue.drain(defaults: context.defaults, lockFileURL: invalidLockFileURL)
        let pendingErrors = try #require(context.defaults.array(forKey: SharedConfiguration.finderSyncErrorsKey) as? [[String: Any]])

        #expect(drained == nil)
        #expect(pendingErrors.first?["id"] as? String == entry.id)
    }

    private func makeQueueContext() throws -> QueueContext {
        let suiteName = "MacPGP.FinderSyncErrorQueueTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPGP-FinderSyncErrorQueueTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return QueueContext(
            suiteName: suiteName,
            defaults: defaults,
            lockFileURL: directory.appendingPathComponent("queue.lock")
        )
    }

    private struct QueueContext {
        let suiteName: String
        let defaults: UserDefaults
        let lockFileURL: URL

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: lockFileURL.deletingLastPathComponent())
        }
    }
}
