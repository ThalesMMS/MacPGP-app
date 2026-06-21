//
//  LocalizationUITests.swift
//  MacPGPUITests
//
//  Non-English UI smoke test for issue #131: launching in Portuguese shows
//  translated navigation and a localized crypto-feature surface.
//

import XCTest

final class LocalizationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testPortugueseLaunchTranslatesNavigationAndSignFeature() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-keyring", "--uitest-language", "pt"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        // Sidebar navigation is translated to Portuguese (Sign -> "Assinar",
        // Verify -> "Verificar", Keyring -> "Chaveiro").
        let signItem = firstElement(app, label: "Assinar")
        XCTAssertTrue(signItem.waitForExistence(timeout: 5), "Expected Portuguese 'Assinar' navigation item")
        XCTAssertTrue(elementExists(app, label: "Verificar"), "Expected Portuguese 'Verificar' navigation item")
        XCTAssertTrue(elementExists(app, label: "Chaveiro"), "Expected Portuguese 'Chaveiro' navigation item")

        // Navigate into the Sign feature and confirm its localized toolbar button.
        signItem.tap()
        XCTAssertTrue(
            app.buttons["Assinar"].waitForExistence(timeout: 5),
            "Expected the localized Sign action button in Portuguese"
        )
    }

    private func firstElement(_ app: XCUIApplication, label: String) -> XCUIElement {
        if app.buttons[label].exists { return app.buttons[label] }
        if app.staticTexts[label].exists { return app.staticTexts[label] }
        return app.descendants(matching: .any)[label]
    }

    private func elementExists(_ app: XCUIApplication, label: String) -> Bool {
        app.buttons[label].exists || app.staticTexts[label].exists
    }
}
