import AppKit
import SwiftUI

@MainActor
final class PreviewHostingControllerContainer {
    private unowned let parentViewController: NSViewController
    private(set) var hostingController: NSHostingController<AnyView>?

    init(parentViewController: NSViewController) {
        self.parentViewController = parentViewController
    }

    func show<Content: View>(_ rootView: Content) {
        clear()

        let hostingController = NSHostingController(rootView: AnyView(rootView))
        self.hostingController = hostingController

        parentViewController.addChild(hostingController)
        parentViewController.view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: parentViewController.view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: parentViewController.view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: parentViewController.view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: parentViewController.view.bottomAnchor)
        ])
    }

    func clear() {
        if let hostingController {
            hostingController.view.removeFromSuperview()
            hostingController.removeFromParent()
            self.hostingController = nil
        }
    }
}
