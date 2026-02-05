import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    private let fileAnalyzer = PGPFileAnalyzer()
    private let encryptedBadgeIdentifier = "com.macpgp.finder.encrypted"

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

        // Launch the main application with the selected files
        // The main app will handle the encryption workflow
        let workspace = NSWorkspace.shared
        let appBundleIdentifier = "com.macpgp.MacPGP"

        // Try to open each selected file with the main application
        for fileURL in selectedItems {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.open(
                [fileURL],
                withApplicationAt: URL(fileURLWithPath: "/Applications/MacPGP.app"),
                configuration: configuration
            ) { _, error in
                if let error = error {
                    NSLog("Failed to open file with MacPGP: \(error.localizedDescription)")
                }
            }
        }
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

        // Launch the main application with the encrypted files
        // The main app will handle the decryption workflow
        let workspace = NSWorkspace.shared
        let appBundleIdentifier = "com.macpgp.MacPGP"

        // Try to open each encrypted file with the main application
        for fileURL in encryptedFiles {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.open(
                [fileURL],
                withApplicationAt: URL(fileURLWithPath: "/Applications/MacPGP.app"),
                configuration: configuration
            ) { _, error in
                if let error = error {
                    NSLog("Failed to open file with MacPGP: \(error.localizedDescription)")
                }
            }
        }
    }
}
