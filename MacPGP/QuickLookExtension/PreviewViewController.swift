import Cocoa
import Quartz
import SwiftUI

final class PreviewViewController: NSViewController, QLPreviewingController {
    private var hostingController: NSHostingController<AnyView>?
    private var previewRequestID = UUID()

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

        guard isPGPFile(url) else {
            handler(NSError(domain: "com.macpgp.quicklook", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not a PGP file"]))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let rootView: AnyView
            do {
                let metadata = try PGPMetadataExtractor().extractMetadata(from: url)
                rootView = AnyView(EncryptionMetadataView(metadata: metadata, fileURL: url))
            } catch {
                rootView = AnyView(EncryptionErrorView(fileURL: url))
            }

            DispatchQueue.main.async {
                if self.previewRequestID == requestID {
                    self.show(rootView: rootView)
                }

                handler(nil)
            }
        }
    }

    private func isPGPFile(_ url: URL) -> Bool {
        PGPFileAnalyzer.isPGPFile(url: url)
    }

    private func show<Content: View>(rootView: Content) {
        let rootView = AnyView(rootView)
        if let hostingController {
            hostingController.rootView = rootView
            return
        }

        let hostingController = NSHostingController(rootView: rootView)
        self.hostingController = hostingController

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
