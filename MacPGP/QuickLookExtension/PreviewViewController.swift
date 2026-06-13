import Cocoa
import Quartz
import SwiftUI

final class PreviewViewController: NSViewController, QLPreviewingController {
    private var previewRequestID = UUID()
    private lazy var previewHost = PreviewHostingControllerContainer(parentViewController: self)

    override var nibName: NSNib.Name? {
        NSNib.Name("PreviewViewController")
    }

    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfSearchableItem(identifier: String, queryString: String?, completionHandler handler: @escaping (Error?) -> Void) {
        handler(nil)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let requestID = UUID()
        previewRequestID = requestID
        previewHost.clear()

        guard isPGPFile(url) else {
            handler(NSError(domain: "com.macpgp.quicklook", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not a PGP file"]))
            return
        }

        Task {
            let metadata = await Self.extractMetadata(from: url)

            await MainActor.run {
                if self.previewRequestID == requestID {
                    if let metadata {
                        self.show(rootView: EncryptionMetadataView(metadata: metadata, fileURL: url))
                    } else {
                        self.show(rootView: EncryptionErrorView(fileURL: url))
                    }
                }

                handler(nil)
            }
        }
    }

    nonisolated private static func extractMetadata(from url: URL) async -> PGPMetadataExtractor.Metadata? {
        await Task.detached(priority: .userInitiated) {
            try? PGPMetadataExtractor().extractMetadata(from: url)
        }.value
    }

    private func isPGPFile(_ url: URL) -> Bool {
        PGPFileAnalyzer.isPGPFile(url: url)
    }

    private func show<Content: View>(rootView: Content) {
        previewHost.show(rootView)
    }
}
