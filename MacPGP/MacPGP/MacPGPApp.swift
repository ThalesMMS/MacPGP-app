import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var servicesProvider: ServicesProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize and register Services menu integration
        let keyringService = KeyringService()
        servicesProvider = ServicesProvider(keyringService: keyringService)
        NSApp.servicesProvider = servicesProvider
    }
}

@main
struct MacPGPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var keyringService = KeyringService()
    @State private var sessionState = SessionStateManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(keyringService)
                .environment(sessionState)
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
}
