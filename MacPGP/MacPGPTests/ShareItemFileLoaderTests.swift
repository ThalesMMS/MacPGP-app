import AppKit
import Testing
import UniformTypeIdentifiers
@testable import MacPGP

@Suite("Share item file loader")
struct ShareItemFileLoaderTests {
    @Test("loads file URLs from extension item providers asynchronously")
    func loadsFileURLs() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-loader-\(UUID().uuidString).txt")
        try "payload".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let item = NSExtensionItem()
        item.attachments = [try #require(NSItemProvider(contentsOf: fileURL))]

        let urls = await ShareItemFileLoader.fileURLs(from: [item])

        #expect(urls == [fileURL])
    }

    @Test("loads multiple file URL attachments")
    func loadsMultipleFileURLAttachments() async throws {
        let fileURLs = try (0..<2).map { index in
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("share-loader-\(index)-\(UUID().uuidString).txt")
            try "payload-\(index)".write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }
        defer { fileURLs.forEach { try? FileManager.default.removeItem(at: $0) } }

        let item = NSExtensionItem()
        item.attachments = try fileURLs.map { try #require(NSItemProvider(contentsOf: $0)) }

        let urls = await ShareItemFileLoader.fileURLs(from: [item])

        #expect(urls == fileURLs)
    }

    @Test("loads file representation attachments")
    func loadsFileRepresentationAttachments() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-loader-file-representation-\(UUID().uuidString).txt")
        try "file-representation".write(to: sourceURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let provider = NSItemProvider()
        provider.suggestedName = "shared-file.txt"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.plainText.identifier, fileOptions: [], visibility: .all) { completion in
            completion(sourceURL, false, nil)
            return nil
        }
        let item = NSExtensionItem()
        item.attachments = [provider]

        let urls = await ShareItemFileLoader.fileURLs(from: [item])
        let loadedURL = try #require(urls.first)
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }

        #expect(urls.count == 1)
        #expect(try String(contentsOf: loadedURL, encoding: .utf8) == "file-representation")
        #expect(loadedURL.lastPathComponent.hasSuffix("shared-file.txt"))
    }

    @Test("loads data representation attachments")
    func loadsDataRepresentationAttachments() async throws {
        let provider = NSItemProvider()
        provider.suggestedName = "shared-message"
        provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            completion("data-representation".data(using: .utf8), nil)
            return nil
        }
        let item = NSExtensionItem()
        item.attachments = [provider]

        let urls = await ShareItemFileLoader.fileURLs(from: [item])
        let loadedURL = try #require(urls.first)
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }

        #expect(urls.count == 1)
        #expect(try String(contentsOf: loadedURL, encoding: .utf8) == "data-representation")
        #expect(loadedURL.pathExtension == "txt")
    }

    @Test("ignores attachments that do not provide file URLs")
    func ignoresNonFileURLAttachments() async {
        let item = NSExtensionItem()
        item.attachments = [NSItemProvider()]

        let urls = await ShareItemFileLoader.fileURLs(from: [item])

        #expect(urls.isEmpty)
    }

    @Test("ignores providers that fail while loading file URLs")
    func ignoresFailingFileURLProviders() async {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: "public.file-url", visibility: .all) { completion in
            completion(nil, NSError(domain: "ShareItemFileLoaderTests", code: 1))
            return nil
        }

        let item = NSExtensionItem()
        item.attachments = [provider]

        let urls = await ShareItemFileLoader.fileURLs(from: [item])

        #expect(urls.isEmpty)
    }
}
