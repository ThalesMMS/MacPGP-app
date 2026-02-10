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

    init() {
        let keyring = KeyringService()
        _keyringService = State(initialValue: keyring)
        _sessionState = State(initialValue: SessionStateManager())
        _trustService = State(initialValue: TrustService(keyringService: keyring))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(keyringService)
                .environment(sessionState)
                .environment(trustService)
                .frame(minWidth: 1024, minHeight: 768)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Generate New Key...") {
                    NotificationCenter.default.post(name: .showKeyGeneration, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Import Key...") {
                    NotificationCenter.default.post(name: .importKey, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])

                Divider()

                Button("Backup Keys...") {
                    NotificationCenter.default.post(name: .showBackupWizard, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Restore Keys...") {
                    NotificationCenter.default.post(name: .showRestoreWizard, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            CommandGroup(after: .textEditing) {
                Button("Encrypt Clipboard") {
                    NotificationCenter.default.post(name: .encryptClipboard, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Decrypt Clipboard") {
                    NotificationCenter.default.post(name: .decryptClipboard, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(keyringService)
        }
    }
}

extension Notification.Name {
    static let showKeyGeneration = Notification.Name("showKeyGeneration")
    static let importKey = Notification.Name("importKey")
    static let encryptFiles = ExtensionCommunicationService.encryptFilesNotification
    static let decryptFiles = ExtensionCommunicationService.decryptFilesNotification
    static let encryptClipboard = Notification.Name("encryptClipboard")
    static let decryptClipboard = Notification.Name("decryptClipboard")
    static let showBackupWizard = Notification.Name("showBackupWizard")
    static let showRestoreWizard = Notification.Name("showRestoreWizard")
}
