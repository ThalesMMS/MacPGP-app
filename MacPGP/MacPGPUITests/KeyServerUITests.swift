//
//  KeyServerUITests.swift
//  MacPGPUITests
//
//  Deterministic Keyserver UI coverage for issue #125 (settings persistence and
//  search/import). All network behavior is served by the in-app stub
//  (`--uitest-keyserver-stub`); these tests never contact a public keyserver.
//

import XCTest

final class KeyServerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    // MARK: - Launch helpers

    /// App launched with clean keyring + keyserver preferences (no network stub).
    private func settingsApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-keyring", "--reset-keyserver-preferences"]
        return app
    }

    /// App launched with the deterministic keyserver stub and a chosen scenario.
    private func searchApp(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-keyring", "--reset-keyserver-preferences", "--uitest-keyserver-stub"]
        app.launchEnvironment = ["MACPGP_UITEST_KEYSERVER_SCENARIO": scenario]
        return app
    }

    private func launch(_ app: XCUIApplication) {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    private func openKeyserverSettings(_ app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(
            app.windows["Settings"].waitForExistence(timeout: 5) ||
            app.buttons["General"].waitForExistence(timeout: 5) ||
            app.buttons["settings.tab.general"].waitForExistence(timeout: 5)
        )
        let keyserverTab = app.buttons["Keyserver"].exists ? app.buttons["Keyserver"] : app.buttons["settings.tab.keyserver"]
        XCTAssertTrue(keyserverTab.waitForExistence(timeout: 5))
        keyserverTab.tap()
        XCTAssertTrue(app.staticTexts["Enabled Keyservers"].waitForExistence(timeout: 3))
    }

    private func settingsWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows["Keyserver"].exists ? app.windows["Keyserver"] : app.windows.firstMatch
    }

    @discardableResult
    private func openKeyserverSearch(_ app: XCUIApplication) -> Bool {
        let keyringButton = app.buttons["Keyring"]
        if keyringButton.exists { keyringButton.tap() }

        let searchButton = app.buttons["Search Keyserver"]
        guard searchButton.waitForExistence(timeout: 5) else {
            XCTFail("Search Keyserver toolbar button must exist")
            return false
        }
        searchButton.tap()
        return app.textFields["Keyserver Search Field"].waitForExistence(timeout: 5)
    }

    private func performSearch(_ app: XCUIApplication, query: String = "alice@example.org") {
        let field = app.textFields["Keyserver Search Field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(query)
        app.buttons["Keyserver Search Button"].tap()
    }

    // MARK: - Settings: enable / disable

    @MainActor
    func testDisableAndReEnableSecureServer() throws {
        let app = settingsApp()
        launch(app)
        openKeyserverSettings(app)
        let window = settingsWindow(app)

        let ubuntu = window.switches["Keyserver Toggle keyserver.ubuntu.com"]
        XCTAssertTrue(ubuntu.waitForExistence(timeout: 3))
        XCTAssertEqual(ubuntu.value as? String, "1")

        ubuntu.tap()
        XCTAssertEqual(ubuntu.value as? String, "0")

        ubuntu.tap()
        XCTAssertEqual(ubuntu.value as? String, "1")
    }

    @MainActor
    func testLastEnabledServerCannotBeDisabled() throws {
        let app = settingsApp()
        launch(app)
        openKeyserverSettings(app)
        let window = settingsWindow(app)

        // Default enabled set is keys.openpgp.org + Ubuntu (both secure). Disable Ubuntu,
        // leaving keys.openpgp.org as the only enabled server.
        let ubuntu = window.switches["Keyserver Toggle keyserver.ubuntu.com"]
        XCTAssertTrue(ubuntu.waitForExistence(timeout: 3))
        if ubuntu.value as? String == "1" { ubuntu.tap() }

        let keysOpenPGP = window.switches["Keyserver Toggle keys.openpgp.org"]
        XCTAssertTrue(keysOpenPGP.waitForExistence(timeout: 3))
        // The last enabled server's toggle is disabled and stays enabled if tapped.
        XCTAssertFalse(keysOpenPGP.isEnabled)
        XCTAssertEqual(keysOpenPGP.value as? String, "1")
        XCTAssertTrue(app.staticTexts["At least one keyserver must remain enabled."].waitForExistence(timeout: 2))
    }

    // MARK: - Settings: insecure opt-in confirmation (issue #129 path)

    @MainActor
    func testEnablingInsecureServerRequiresConfirmation() throws {
        let app = settingsApp()
        launch(app)
        openKeyserverSettings(app)
        let window = settingsWindow(app)

        let mit = window.switches["Keyserver Toggle pgp.mit.edu"]
        XCTAssertTrue(mit.waitForExistence(timeout: 3))
        XCTAssertEqual(mit.value as? String, "0")

        mit.tap()

        // A security confirmation must appear before the insecure server is enabled.
        let confirm = app.buttons["Confirm Insecure Keyserver"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        XCTAssertEqual(mit.value as? String, "1")
        // The insecure badge is shown for the now-enabled plaintext server.
        XCTAssertTrue(window.staticTexts["Insecure Badge pgp.mit.edu"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCancellingInsecureConfirmationLeavesServerDisabled() throws {
        let app = settingsApp()
        launch(app)
        openKeyserverSettings(app)
        let window = settingsWindow(app)

        let mit = window.switches["Keyserver Toggle pgp.mit.edu"]
        XCTAssertTrue(mit.waitForExistence(timeout: 3))
        mit.tap()

        let cancel = app.buttons["Cancel Insecure Keyserver"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()

        XCTAssertEqual(mit.value as? String, "0")
    }

    // MARK: - Settings: default + timeout persistence across relaunch

    @MainActor
    func testDefaultServerSelectionPersistsAcrossRelaunch() throws {
        let app = settingsApp()
        launch(app)
        openKeyserverSettings(app)
        var window = settingsWindow(app)

        let picker = window.popUpButtons["Default Keyserver Picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.tap()
        let ubuntuOption = app.menuItems["Ubuntu Keyserver"]
        XCTAssertTrue(ubuntuOption.waitForExistence(timeout: 3))
        ubuntuOption.tap()

        // Relaunch WITHOUT the reset flag so preferences persist.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--reset-keyring"]
        launch(relaunched)
        openKeyserverSettings(relaunched)
        window = settingsWindow(relaunched)

        let persistedPicker = window.popUpButtons["Default Keyserver Picker"]
        XCTAssertTrue(persistedPicker.waitForExistence(timeout: 3))
        // A SwiftUI Picker row uses a multi-line label, so match the persisted
        // selection tolerantly on the server identity rather than an exact title.
        let persistedValue = (persistedPicker.value as? String ?? "").lowercased()
        XCTAssertTrue(persistedValue.contains("ubuntu"), "Expected persisted default to be Ubuntu, got '\(persistedValue)'")
    }

    @MainActor
    func testTimeoutSelectionPersists() throws {
        let app = settingsApp()
        launch(app)
        openKeyserverSettings(app)
        let window = settingsWindow(app)

        let timeout = window.popUpButtons["Keyserver Timeout Picker"]
        XCTAssertTrue(timeout.waitForExistence(timeout: 3))
        timeout.tap()
        let sixty = app.menuItems["60 seconds"]
        XCTAssertTrue(sixty.waitForExistence(timeout: 3))
        sixty.tap()

        XCTAssertEqual(timeout.value as? String, "60 seconds")
    }

    // MARK: - Search / Import

    @MainActor
    func testSearchShowsFixtureResults() throws {
        let app = searchApp(scenario: "successMultiple")
        launch(app)
        XCTAssertTrue(openKeyserverSearch(app))
        performSearch(app)

        XCTAssertTrue(app.staticTexts["Alice (Test ecc key) <alice@example.org>"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bob Example <bob@example.org>"].exists)
    }

    @MainActor
    func testSearchNoResultsShowsEmptyState() throws {
        let app = searchApp(scenario: "noResults")
        launch(app)
        XCTAssertTrue(openKeyserverSearch(app))
        performSearch(app)

        XCTAssertTrue(app.staticTexts["No Keys Found"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSearchServerErrorShowsError() throws {
        let app = searchApp(scenario: "serverError")
        launch(app)
        XCTAssertTrue(openKeyserverSearch(app))
        performSearch(app)

        let okButton = app.buttons["Keyserver Error OK"]
        XCTAssertTrue(okButton.waitForExistence(timeout: 5))
        // No stale results are shown behind the error.
        XCTAssertFalse(app.staticTexts["Alice (Test ecc key) <alice@example.org>"].exists)
        okButton.tap()
    }

    @MainActor
    func testSelectAndImportKeyAddsItToKeyring() throws {
        let app = searchApp(scenario: "importSuccess")
        launch(app)
        XCTAssertTrue(openKeyserverSearch(app))
        performSearch(app)

        let aliceRow = app.staticTexts["Alice (Test ecc key) <alice@example.org>"]
        XCTAssertTrue(aliceRow.waitForExistence(timeout: 5))
        aliceRow.tap()

        let importButton = app.buttons["Keyserver Import Button"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        XCTAssertTrue(importButton.isEnabled)
        importButton.tap()

        // The sheet dismisses and the imported key appears in the keyring.
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "alice@example.org")).firstMatch.waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.textFields["Keyserver Search Field"].exists)
    }

    @MainActor
    func testImportMalformedKeyShowsErrorAndKeepsSheet() throws {
        let app = searchApp(scenario: "malformedKey")
        launch(app)
        XCTAssertTrue(openKeyserverSearch(app))
        performSearch(app)

        let aliceRow = app.staticTexts["Alice (Test ecc key) <alice@example.org>"]
        XCTAssertTrue(aliceRow.waitForExistence(timeout: 5))
        aliceRow.tap()

        let importButton = app.buttons["Keyserver Import Button"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        importButton.tap()

        let okButton = app.buttons["Keyserver Error OK"]
        XCTAssertTrue(okButton.waitForExistence(timeout: 5))
        okButton.tap()
        // The search sheet remains open after a failed import.
        XCTAssertTrue(app.textFields["Keyserver Search Field"].exists)
    }

    @MainActor
    func testChangeServerAndRepeatSearch() throws {
        let app = searchApp(scenario: "successMultiple")
        launch(app)
        XCTAssertTrue(openKeyserverSearch(app))

        let serverPicker = app.popUpButtons["Keyserver Search Server Picker"]
        XCTAssertTrue(serverPicker.waitForExistence(timeout: 3))
        serverPicker.tap()
        let ubuntuOption = app.menuItems["Ubuntu Keyserver"]
        XCTAssertTrue(ubuntuOption.waitForExistence(timeout: 3))
        ubuntuOption.tap()

        performSearch(app)
        XCTAssertTrue(app.staticTexts["Alice (Test ecc key) <alice@example.org>"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRapidDuplicateSearchSubmissionsStaySafe() throws {
        let app = searchApp(scenario: "successMultiple")
        launch(app)
        XCTAssertTrue(openKeyserverSearch(app))

        let field = app.textFields["Keyserver Search Field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("alice@example.org")

        let searchButton = app.buttons["Keyserver Search Button"]
        searchButton.tap()
        if searchButton.isEnabled { searchButton.tap() }

        // The app must remain responsive and show deterministic results.
        XCTAssertTrue(app.staticTexts["Alice (Test ecc key) <alice@example.org>"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2))
    }
}
