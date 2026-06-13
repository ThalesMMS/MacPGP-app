import AppKit
@testable import MacPGP
import SwiftUI
import Testing

@Suite("Quick Look Preview State")
@MainActor
struct QuickLookPreviewStateTests {
    @Test("consecutive encrypted previews replace the hosting controller")
    func showingNewPreviewReplacesHostingController() throws {
        let parentViewController = NSViewController()
        parentViewController.view = NSView()
        let previewHost = PreviewHostingControllerContainer(parentViewController: parentViewController)

        previewHost.show(EncryptedPreviewStatefulRoot(filename: "first.pgp"))
        let firstHost = try #require(previewHost.hostingController)

        previewHost.show(EncryptedPreviewStatefulRoot(filename: "second.pgp"))
        let secondHost = try #require(previewHost.hostingController)

        #expect(firstHost !== secondHost)
        #expect(firstHost.parent == nil)
        #expect(firstHost.view.superview == nil)
        #expect(parentViewController.children.count == 1)
        #expect(parentViewController.children.first === secondHost)
        #expect(secondHost.view.superview === parentViewController.view)
    }

    @Test("clearing preview removes encrypted preview state")
    func clearingPreviewRemovesEncryptedPreviewState() throws {
        let parentViewController = NSViewController()
        parentViewController.view = NSView()
        let previewHost = PreviewHostingControllerContainer(parentViewController: parentViewController)

        previewHost.show(EncryptedPreviewStatefulRoot(filename: "first.pgp"))
        let host = try #require(previewHost.hostingController)

        previewHost.clear()

        #expect(previewHost.hostingController == nil)
        #expect(host.parent == nil)
        #expect(host.view.superview == nil)
        #expect(parentViewController.children.isEmpty)
    }
}

private struct EncryptedPreviewStatefulRoot: View {
    let filename: String

    @State private var passphrase = ""
    @State private var decryptedPlaintext: String?

    var body: some View {
        VStack {
            Text(filename)
            SecureField("Passphrase", text: $passphrase)
            if let decryptedPlaintext {
                Text(decryptedPlaintext)
            }
        }
    }
}
