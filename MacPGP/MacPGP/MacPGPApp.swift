import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var servicesProvider: ServicesProvider?
    private var extensionCommunicationService: ExtensionCommunicationService?
    private var backupReminderService: BackupReminderService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Skip service initialization if running tests
        // Check both environment variable and if XCTest is loaded
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                            ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil ||
                            NSClassFromString("XCTestCase") != nil
        guard !isRunningTests else { return }

        // Initialize and register Services menu integration
        let keyringService = KeyringService()
        servicesProvider = ServicesProvider(keyringService: keyringService)
        NSApp.servicesProvider = servicesProvider

        // Initialize extension communication service for FinderSync integration
        extensionCommunicationService = ExtensionCommunicationService()

        // Initialize backup reminder service
        backupReminderService = BackupReminderService()
    }

    /// Handles files opened from extensions or Finder
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        extensionCommunicationService?.handleOpenFiles(urls)
    }
}

@main
struct MacPGPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var keyringService = KeyringService()
    @State private var sessionState = SessionStateManager()
    @State private var trustService: TrustService
    @State private var keyServerService = KeyServerService()

    init() {
        let keyring = KeyringService()
        _keyringService = State(initialValue: keyring)
        _sessionState = State(initialValue: SessionStateManager())
        _trustService = State(initialValue: TrustService(keyringService: keyring))
        _keyServerService = State(initialValue: KeyServerService())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(keyringService)
                .environment(sessionState)
                .environment(trustService)
                .environment(keyServerService)
                .frame(minWidth: 1024, minHeight: 768)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "menu.generate_key", comment: "Menu item to generate a new PGP key")) {
                    NotificationCenter.default.post(name: .showKeyGeneration, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button(String(localized: "menu.import_key", comment: "Menu item to import a PGP key")) {
                    NotificationCenter.default.post(name: .importKey, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button(String(localized: "menu.search_key_server", comment: "Menu item to search for keys on a key server")) {
                    NotificationCenter.default.post(name: .showKeyServerSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                Button(String(localized: "menu.backup_keys", comment: "Menu item to backup PGP keys")) {
                    NotificationCenter.default.post(name: .showBackupWizard, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button(String(localized: "menu.restore_keys", comment: "Menu item to restore backed up PGP keys")) {
                    NotificationCenter.default.post(name: .showRestoreWizard, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            CommandGroup(after: .textEditing) {
                Button(String(localized: "menu.encrypt_clipboard", comment: "Menu item to encrypt clipboard contents")) {
                    NotificationCenter.default.post(name: .encryptClipboard, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button(String(localized: "menu.decrypt_clipboard", comment: "Menu item to decrypt clipboard contents")) {
                    NotificationCenter.default.post(name: .decryptClipboard, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(keyringService)
                .environment(keyServerService)
        }
    }
}

extension Notification.Name {
    static let showKeyGeneration = Notification.Name("showKeyGeneration")
    static let importKey = Notification.Name("importKey")
    static let showKeyServerSearch = Notification.Name("showKeyServerSearch")
    static let encryptFiles = ExtensionCommunicationService.encryptFilesNotification
    static let decryptFiles = ExtensionCommunicationService.decryptFilesNotification
    static let encryptClipboard = Notification.Name("encryptClipboard")
    static let decryptClipboard = Notification.Name("decryptClipboard")
    static let showBackupWizard = Notification.Name("showBackupWizard")
    static let showRestoreWizard = Notification.Name("showRestoreWizard")
}
