import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    private let fileAnalyzer = PGPFileAnalyzer()
    private let encryptedBadgeIdentifier = "com.macpgp.finder.encrypted"
    private let mainAppBundleIdentifier = "com.macpgp.MacPGP"
    private let appGroupIdentifier = "group.com.macpgp.shared"
    private let finderSyncErrorsKey = "com.macpgp.finderSync.errors"

    override init() {
        super.init()

        let finderSync = FIFinderSyncController.default()
        if let mountedVolumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) {
            finderSync.directoryURLs = Set<URL>(mountedVolumes)
        }

        // Register badge for encrypted files
        setupBadges()
    }

    // MARK: - Badge Setup

    private func setupBadges() {
        let finderSync = FIFinderSyncController.default()

        // Create a lock badge image using SF Symbols
        if let lockImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Encrypted") {
            let badgeImage = NSImage(size: NSSize(width: 320, height: 320))
            badgeImage.lockFocus()

            // Draw lock icon in the badge
            lockImage.draw(in: NSRect(x: 0, y: 0, width: 320, height: 320))

            badgeImage.unlockFocus()

            finderSync.setBadgeImage(badgeImage, label: "Encrypted", forBadgeIdentifier: encryptedBadgeIdentifier)
        }
    }

    // MARK: - Badge Identifiers

    override func requestBadgeIdentifier(for url: URL) {
        let finderSync = FIFinderSyncController.default()

        // Check if this is a PGP file
        guard PGPFileAnalyzer.isPGPFile(url: url) else {
            finderSync.setBadgeIdentifier("", for: url)
            return
        }

        // Check if the file is encrypted
        if fileAnalyzer.isEncrypted(fileAt: url) {
            finderSync.setBadgeIdentifier(encryptedBadgeIdentifier, for: url)
        } else {
            finderSync.setBadgeIdentifier("", for: url)
        }
    }

    // MARK: - Menu and toolbar item support

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        // Only provide menu for contextual menu on items
        guard menuKind == .contextualMenuForItems else {
            return nil
        }

        let menu = NSMenu(title: "")

        // Get the selected items to determine what menu items to show
        let selectedItems = FIFinderSyncController.default().selectedItemURLs() ?? []

        // Only show options if there are selected items
        guard !selectedItems.isEmpty else {
            return nil
        }

        // Check if any selected files are encrypted PGP files
        let hasEncryptedFiles = selectedItems.contains { url in
            PGPFileAnalyzer.isPGPFile(url: url) && fileAnalyzer.isEncrypted(fileAt: url)
        }

        // Add "Decrypt with MacPGP" menu item for encrypted files
        if hasEncryptedFiles {
            let decryptItem = NSMenuItem(
                title: "Decrypt with MacPGP",
                action: #selector(decryptSelectedItems(_:)),
                keyEquivalent: ""
            )
            decryptItem.target = self
            menu.addItem(decryptItem)
        }

        // Add "Encrypt with MacPGP" menu item
        let encryptItem = NSMenuItem(
            title: "Encrypt with MacPGP",
            action: #selector(encryptSelectedItems(_:)),
            keyEquivalent: ""
        )
        encryptItem.target = self
        menu.addItem(encryptItem)

        return menu
    }

    // MARK: - Menu Actions

    /// Handles the "Encrypt with MacPGP" menu action
    /// Opens the main application to encrypt the selected files
    @objc private func encryptSelectedItems(_ sender: AnyObject?) {
        guard let selectedItems = FIFinderSyncController.default().selectedItemURLs(),
              !selectedItems.isEmpty else {
            return
        }

        openFilesWithMainApp(selectedItems)
    }

    /// Handles the "Decrypt with MacPGP" menu action
    /// Opens the main application to decrypt the selected encrypted files
    @objc private func decryptSelectedItems(_ sender: AnyObject?) {
        guard let selectedItems = FIFinderSyncController.default().selectedItemURLs(),
              !selectedItems.isEmpty else {
            return
        }

        // Filter to only encrypted PGP files
        let encryptedFiles = selectedItems.filter { url in
            PGPFileAnalyzer.isPGPFile(url: url) && fileAnalyzer.isEncrypted(fileAt: url)
        }

        guard !encryptedFiles.isEmpty else {
            return
        }

        openFilesWithMainApp(encryptedFiles)
    }

    private func openFilesWithMainApp(_ fileURLs: [URL]) {
        guard let mainAppURL = resolveMainAppURL() else {
            forwardErrorToContainingApp(
                title: "MacPGP app not found",
                message: "Install or reinstall MacPGP, then try the Finder action again."
            )
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            fileURLs,
            withApplicationAt: mainAppURL,
            configuration: configuration
        ) { [weak self] _, error in
            if let error = error {
                NSLog("Failed to open files with MacPGP: \(error.localizedDescription)")
                self?.forwardErrorToContainingApp(
                    title: "Could not open MacPGP",
                    message: "Open MacPGP, then try the Finder action again."
                )
            }
        }
    }

    private func resolveMainAppURL() -> URL? {
        let containingAppURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        if containingAppURL.pathExtension == "app",
           FileManager.default.fileExists(atPath: containingAppURL.path),
           Bundle(url: containingAppURL)?.bundleIdentifier == mainAppBundleIdentifier {
            return containingAppURL
        }

        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: mainAppBundleIdentifier)
    }

    private func forwardErrorToContainingApp(title: String, message: String) {
        NSLog("Finder Sync error: \(title) - \(message)")

        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("Failed to open app group defaults for Finder Sync error forwarding")
            return
        }

        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "title": title,
            "message": message,
            "createdAt": Date().timeIntervalSince1970
        ]

        var pendingErrors = defaults.array(forKey: finderSyncErrorsKey) as? [[String: Any]] ?? []
        pendingErrors.append(payload)
        defaults.set(Array(pendingErrors.suffix(20)), forKey: finderSyncErrorsKey)
    }
}
