import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var servicesProvider: ServicesProvider?
    private var extensionCommunicationService: ExtensionCommunicationService?
    private var backupReminderService: BackupReminderService?
    private var keyringService: KeyringService?
    private var didFinishLaunching = false

    func configure(keyringService: KeyringService) {
        self.keyringService = keyringService
        registerServicesProviderIfNeeded()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        guard !Self.isRunningTests else { return }

        // Initialize and register Services menu integration
        registerServicesProviderIfNeeded()

        // Initialize extension communication service for FinderSync integration
        extensionCommunicationService = ExtensionCommunicationService()

        // Initialize backup reminder service and schedule after launch setup is complete.
        let reminderService = BackupReminderService()
        backupReminderService = reminderService
        DispatchQueue.main.async {
            reminderService.scheduleReminderIfNeeded()
        }
    }

    /// Handles files opened from extensions or Finder
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        extensionCommunicationService?.handleOpenFiles(urls)
    }

    private func registerServicesProviderIfNeeded() {
        guard didFinishLaunching else { return }
        guard !Self.isRunningTests else { return }
        guard servicesProvider == nil else { return }
        guard let keyringService else { return }

        let provider = ServicesProvider(keyringService: keyringService)
        servicesProvider = provider
        NSApp.servicesProvider = provider
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil ||
            NSClassFromString("XCTestCase") != nil
    }
}

@main
struct MacPGPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var keyringService: KeyringService
    @State private var sessionState: SessionStateManager
    @State private var trustService: TrustService
    @State private var keyServerService: KeyServerService
    @State private var preferences: PreferencesManager

    init() {
        Self.resetKeyringIfRequested()
        Self.resetKeyServerPreferencesIfRequested()
        Self.applyUITestLanguageIfRequested()

        let keyring = KeyringService()
        _keyringService = State(initialValue: keyring)
        _sessionState = State(initialValue: SessionStateManager())
        _trustService = State(initialValue: TrustService(keyringService: keyring))
        _preferences = State(initialValue: PreferencesManager.shared)
        let keyServer = KeyServerUITestSupport.isEnabled
            ? KeyServerUITestSupport.makeKeyServerService()
            : KeyServerService()
        _keyServerService = State(initialValue: keyServer)
        appDelegate.configure(keyringService: keyring)

        // Instantiate the lock controller so it registers system lock/sleep observers.
        _ = SessionLockController.shared
    }

    /// Resets persisted keyring state for debug or test launches that include the `--reset-keyring` flag.
    ///
    /// Release launches outside XCTest ignore the flag so production runs cannot wipe persisted keys.
    /// Any errors encountered while writing persistence are caught and logged via `NSLog`.
    private static func resetKeyringIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--reset-keyring") else { return }
        guard isResetKeyringAllowed else { return }

        let persistence = KeyringPersistence()
        do {
            try persistence.saveKeys([])
            try persistence.saveMetadata(KeyringMetadata())
        } catch {
            NSLog("[MacPGPApp] Failed to reset keyring: \(error.localizedDescription)")
        }
    }

    /// Resets persisted keyserver preferences for debug or test launches that include
    /// the `--reset-keyserver-preferences` flag, so Keyserver UI tests start from a
    /// known state. Gated identically to `--reset-keyring`.
    private static func resetKeyServerPreferencesIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--reset-keyserver-preferences") else { return }
        guard isResetKeyringAllowed else { return }

        let defaults = UserDefaults.standard
        for key in ["enabledKeyServers", "defaultKeyServer", "keyServerTimeout", "insecureKeyServersAllowed"] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Forces a UI language for localization UI tests via `--uitest-language <code>`.
    /// Gated identically to `--reset-keyring`, so production launches are unaffected.
    private static func applyUITestLanguageIfRequested() {
        guard isResetKeyringAllowed else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--uitest-language"),
              index + 1 < arguments.count,
              let language = AppLanguage(rawValue: arguments[index + 1]) else { return }
        PreferencesManager.shared.appLanguage = language
    }

    private static var isResetKeyringAllowed: Bool {
        #if DEBUG
        return true
        #else
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestSessionIdentifier"] != nil ||
            NSClassFromString("XCTestCase") != nil
        #endif
    }

    private func localizedMenuLabel(_ key: String.LocalizationValue, comment: StaticString) -> String {
        String(localized: key, locale: preferences.appLanguage.locale, comment: comment)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(keyringService)
                .environment(sessionState)
                .environment(trustService)
                .environment(keyServerService)
                .environment(\.locale, preferences.appLanguage.locale)
                .frame(minWidth: 1024, minHeight: 768)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(localizedMenuLabel("menu.lock_macpgp", comment: "Menu item to lock MacPGP and clear cached passphrases")) {
                    SessionLockController.shared.lock()
                }
                .keyboardShortcut("l", modifiers: [.command, .control])
            }

            CommandGroup(replacing: .newItem) {
                Button(localizedMenuLabel("menu.generate_key", comment: "Menu item to generate a new PGP key")) {
                    NotificationCenter.default.post(name: .showKeyGeneration, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button(localizedMenuLabel("menu.import_key", comment: "Menu item to import a PGP key")) {
                    NotificationCenter.default.post(name: .importKey, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button(localizedMenuLabel("menu.search_key_server", comment: "Menu item to search for keys on a key server")) {
                    NotificationCenter.default.post(name: .showKeyServerSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                Button(localizedMenuLabel("menu.backup_keys", comment: "Menu item to backup PGP keys")) {
                    NotificationCenter.default.post(name: .showBackupWizard, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button(localizedMenuLabel("menu.restore_keys", comment: "Menu item to restore backed up PGP keys")) {
                    NotificationCenter.default.post(name: .showRestoreWizard, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            CommandGroup(after: .textEditing) {
                Button(localizedMenuLabel("menu.encrypt_clipboard", comment: "Menu item to encrypt clipboard contents")) {
                    NotificationCenter.default.post(name: .encryptClipboard, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button(localizedMenuLabel("menu.decrypt_clipboard", comment: "Menu item to decrypt clipboard contents")) {
                    NotificationCenter.default.post(name: .decryptClipboard, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(keyringService)
                .environment(keyServerService)
                .environment(\.locale, preferences.appLanguage.locale)
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
