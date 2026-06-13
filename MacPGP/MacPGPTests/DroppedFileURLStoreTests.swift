import Foundation
import Testing
@testable import MacPGP

@Suite("DroppedFileURLStore Tests")
struct DroppedFileURLStoreTests {
    @Test("concurrent file-provider completions preserve provider order")
    func concurrentFileProviderCompletionsPreserveProviderOrder() {
        let store = DroppedFileURLStore()
        let urls = (0..<100).map { index in
            URL(fileURLWithPath: "/tmp/drop-\(index).pgp")
        }

        DispatchQueue.concurrentPerform(iterations: urls.count) { offset in
            let index = urls.count - offset - 1
            store.set(urls[index], at: index)
        }

        #expect(store.snapshot() == urls)
    }
}
