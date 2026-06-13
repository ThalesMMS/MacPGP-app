import Foundation
import Testing

@Suite("Share view controller lifecycle")
struct ShareViewControllerLifecycleTests {
    @Test("shared item loading uses async loader without blocking")
    func sharedItemLoadingUsesAsyncLoaderWithoutBlocking() throws {
        let source = try shareViewControllerSource()
        let extractSharedFiles = try sourceBlock(named: "private func extractSharedFiles", in: source)

        #expect(extractSharedFiles.contains("await ShareItemFileLoader.fileURLs(from: inputItems)"))
        #expect(!extractSharedFiles.contains("DispatchSemaphore"))
        #expect(!extractSharedFiles.contains(".wait("))
    }

    @Test("loaded files are presented in the SwiftUI share flow")
    func loadedFilesArePresentedInSwiftUIShareFlow() throws {
        let source = try shareViewControllerSource()
        let updateUIWithFiles = try sourceBlock(named: "private func updateUIWithFiles", in: source)

        #expect(updateUIWithFiles.contains("ShareExtensionView("))
        #expect(updateUIWithFiles.contains("NSHostingController(rootView: AnyView(shareView))"))
        #expect(updateUIWithFiles.contains("view.addSubview(hostingController.view)"))
    }

    @Test("successful encryption completes the extension request")
    func successfulEncryptionCompletesExtensionRequest() throws {
        let source = try shareViewControllerSource()
        let encryptSharedFiles = try sourceBlock(named: "private func encryptSharedFiles", in: source)
        let complete = try sourceBlock(named: "func complete(with encryptedFileURLs: [URL])", in: source)

        #expect(encryptSharedFiles.contains("let encryptedURLs = try await encryptFilesAsync(for: Array(recipients))"))
        #expect(encryptSharedFiles.contains("complete(with: encryptedURLs)"))
        #expect(complete.contains("extensionContext.completeRequest(returningItems: outputItems"))
    }

    @Test("cancel action cancels the extension request")
    func cancelActionCancelsExtensionRequest() throws {
        let source = try shareViewControllerSource()
        let updateUIWithFiles = try sourceBlock(named: "private func updateUIWithFiles", in: source)
        let cancel = try sourceBlock(named: "func cancel()", in: source)

        #expect(updateUIWithFiles.contains("onCancel: { [weak self]"))
        #expect(updateUIWithFiles.contains("self?.cancel()"))
        #expect(cancel.contains("extensionContext.cancelRequest(withError:"))
    }

    private func shareViewControllerSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ShareExtension/ShareViewController.swift")

        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func sourceBlock(named marker: String, in source: String) throws -> Substring {
        let start = try #require(source.range(of: marker)?.lowerBound)
        let remainingSource = source[start...]
        let end = remainingSource.range(of: "\n    // MARK:", options: [], range: remainingSource.index(after: start)..<remainingSource.endIndex)?.lowerBound
            ?? source.endIndex

        return source[start..<end]
    }
}
