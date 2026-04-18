//
//  SettingsUITests.swift
//  MacPGPUITests
//

import XCTest

final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    private func isolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-keyring"]
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .command)

        XCTAssertTrue(
            app.windows["Settings"].waitForExistence(timeout: 3) ||
            app.buttons["General"].waitForExistence(timeout: 3) ||
            app.buttons["settings.tab.general"].waitForExistence(timeout: 3)
        )
    }

    private func tabButton(_ app: XCUIApplication, named name: String, fallbackKey: String) -> XCUIElement {
        let button = app.buttons[name]
        if button.exists {
            return button
        }

        return app.buttons[fallbackKey]
    }

    private func openTab(_ app: XCUIApplication, named name: String, fallbackKey: String) {
        let button = tabButton(app, named: name, fallbackKey: fallbackKey)
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
    }

    private func assertAnyStaticTextExists(_ app: XCUIApplication, _ labels: [String]) {
        let exists = labels.contains { label in
            app.staticTexts[label].exists ||
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch.exists
        }

        XCTAssertTrue(exists, "Expected one of \(labels) to exist")
    }

    private func keyserverSettingsWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows["Keyserver"].exists ? app.windows["Keyserver"] : app.windows.firstMatch
    }

    private func isOn(_ control: XCUIElement) -> Bool {
        if let intValue = control.value as? Int {
            return intValue == 1
        }

        if let numberValue = control.value as? NSNumber {
            return numberValue.intValue == 1
        }

        if let stringValue = control.value as? String {
            let normalized = stringValue.lowercased()
            return normalized == "1" || normalized == "true" || normalized == "on"
        }

        return false
    }

    @MainActor
    func testSettingsWindowOpensWithKeyboardShortcut() throws {
        let app = isolatedApp()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openSettings(app)
    }

    @MainActor
    func testAllSettingsTabsAreAccessible() throws {
        let app = isolatedApp()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openSettings(app)

        openTab(app, named: "General", fallbackKey: "settings.tab.general")
        assertAnyStaticTextExists(app, ["Language", "settings.general.language"])

        openTab(app, named: "Keys", fallbackKey: "settings.tab.keys")
        assertAnyStaticTextExists(app, ["Default Key Generation Settings", "settings.keys.section_title"])

        openTab(app, named: "Security", fallbackKey: "settings.tab.security")
        assertAnyStaticTextExists(app, ["Passphrase Storage", "settings.security.passphrase_storage"])

        openTab(app, named: "Backup", fallbackKey: "settings.tab.backup")
        assertAnyStaticTextExists(app, ["Backup Reminders", "settings.backup.reminders"])

        openTab(app, named: "Keyserver", fallbackKey: "settings.tab.keyserver")
        XCTAssertTrue(app.staticTexts["Enabled Keyservers"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testKeyserverTabTogglesAndDefaultServerPicker() throws {
        let app = isolatedApp()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openSettings(app)
        openTab(app, named: "Keyserver", fallbackKey: "settings.tab.keyserver")

        let settingsWindow = keyserverSettingsWindow(app)
        XCTAssertTrue(app.staticTexts["keys.openpgp.org"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Ubuntu Keyserver"].exists)
        XCTAssertTrue(app.staticTexts["MIT PGP Keyserver"].exists)

        let keysOpenPGP = settingsWindow.switches["Keyserver Toggle keys.openpgp.org"]
        let ubuntu = settingsWindow.switches["Keyserver Toggle keyserver.ubuntu.com"]
        let mit = settingsWindow.switches["Keyserver Toggle pgp.mit.edu"]

        XCTAssertTrue(keysOpenPGP.waitForExistence(timeout: 2))
        XCTAssertTrue(ubuntu.exists)
        XCTAssertTrue(mit.exists)

        if !isOn(mit) {
            mit.tap()
        }
        XCTAssertTrue(isOn(mit))

        let serverPicker = settingsWindow.popUpButtons["Default Keyserver Picker"]
        XCTAssertTrue(serverPicker.waitForExistence(timeout: 2))
        serverPicker.tap()

        XCTAssertTrue(app.menuItems["MIT PGP Keyserver"].waitForExistence(timeout: 2))
        app.menuItems["MIT PGP Keyserver"].tap()

        let selectedServer = [
            serverPicker.value as? String,
            serverPicker.label
        ].compactMap { $0 }.joined(separator: " ")
        XCTAssertTrue(
            selectedServer.contains("MIT PGP Keyserver") || selectedServer.contains("pgp.mit.edu"),
            "Expected MIT PGP Keyserver to be selected, got \(selectedServer)"
        )
    }

    @MainActor
    func testResetToDefaultsShowsConfirmationDialog() throws {
        let app = isolatedApp()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openSettings(app)
        openTab(app, named: "General", fallbackKey: "settings.tab.general")

        let resetButton = app.buttons["Reset to Defaults"].exists
            ? app.buttons["Reset to Defaults"]
            : app.buttons["settings.general.reset_button"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 2))
        resetButton.tap()

        let confirmationTitle = app.staticTexts["Reset Settings"]
        let fallbackTitle = app.staticTexts["settings.reset_dialog.title"]
        XCTAssertTrue(
            confirmationTitle.waitForExistence(timeout: 2) ||
            fallbackTitle.waitForExistence(timeout: 2)
        )

        let sheet = app.sheets.firstMatch
        let cancelButton = sheet.buttons["Cancel"].exists
            ? sheet.buttons["Cancel"]
            : sheet.buttons["settings.button.cancel"]
        if cancelButton.exists {
            cancelButton.tap()
        }
    }
}
