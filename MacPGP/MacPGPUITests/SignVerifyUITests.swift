//
//  SignVerifyUITests.swift
//  MacPGPUITests
//

import AppKit
import XCTest

final class SignVerifyUITests: XCTestCase {
    private let testPassphrase = "SignVerifyPassphrase123!"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        NSPasteboard.general.clearContents()
    }

    private func isolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-keyring"]
        return app
    }

    private func navigateToSign(_ app: XCUIApplication) {
        let signButton = app.buttons["Sign"]
        XCTAssertTrue(signButton.waitForExistence(timeout: 3))
        signButton.tap()
    }

    private func navigateToVerify(_ app: XCUIApplication) {
        let verifyButton = app.buttons["Verify"]
        XCTAssertTrue(verifyButton.waitForExistence(timeout: 3))
        verifyButton.tap()
    }

    private func generateTestKey(
        _ app: XCUIApplication,
        name: String = "Sign Verify User",
        email: String = "signverify@example.com",
        passphrase: String = "SignVerifyPassphrase123!"
    ) {
        guard app.openKeyGenerationView() else { return }

        let nameField = textField(app, named: AccessibilityIdentifiers.KeyGeneration.fullNameField, index: 0)
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)

        let emailField = textField(app, named: AccessibilityIdentifiers.KeyGeneration.emailField, index: 1)
        emailField.tap()
        emailField.typeText(email)

        let passphraseField = secureTextField(app, named: AccessibilityIdentifiers.KeyGeneration.passphraseField, index: 0)
        passphraseField.tap()
        passphraseField.typeText(passphrase)

        let confirmField = secureTextField(app, named: AccessibilityIdentifiers.KeyGeneration.confirmPassphraseField, index: 1)
        confirmField.tap()
        confirmField.typeText(passphrase)

        let generateButton = app.buttons["Generate"]
        XCTAssertTrue(generateButton.isEnabled)
        generateButton.tap()

        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 30))
        doneButton.tap()
    }

    private func textField(_ app: XCUIApplication, named name: String, index: Int) -> XCUIElement {
        let namedField = app.textFields[name]
        if namedField.exists {
            return namedField
        }

        return app.textFields.element(boundBy: index)
    }

    private func secureTextField(_ app: XCUIApplication, named name: String, index: Int) -> XCUIElement {
        let namedField = app.secureTextFields[name]
        if namedField.exists {
            return namedField
        }

        return app.secureTextFields.element(boundBy: index)
    }

    private func pasteText(_ text: String, into app: XCUIApplication) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        let pasteButton = app.buttons["Paste"]
        XCTAssertTrue(pasteButton.waitForExistence(timeout: 3))
        pasteButton.tap()
    }

    private func signActionButton(_ app: XCUIApplication) -> XCUIElement {
        let toolbarButton = app.toolbars.buttons["Sign"]
        if toolbarButton.exists {
            return toolbarButton
        }

        let buttons = app.buttons.matching(NSPredicate(format: "label == %@", "Sign"))
        return buttons.element(boundBy: max(buttons.count - 1, 0))
    }

    private func verifyActionButton(_ app: XCUIApplication) -> XCUIElement {
        let toolbarButton = app.toolbars.buttons["Verify"]
        if toolbarButton.exists {
            return toolbarButton
        }

        let buttons = app.buttons.matching(NSPredicate(format: "label == %@", "Verify"))
        return buttons.element(boundBy: max(buttons.count - 1, 0))
    }

    private func selectSigningKey(_ app: XCUIApplication, containing name: String = "Sign Verify User") {
        let namedPicker = app.popUpButtons["Select Key"]
        let keyPicker = namedPicker.exists ? namedPicker : app.popUpButtons.firstMatch
        XCTAssertTrue(keyPicker.waitForExistence(timeout: 3))
        keyPicker.tap()

        let keyOption = app.menuItems.matching(NSPredicate(format: "title == %@", name)).element(boundBy: 0)
        let titleOption = app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", name)).element(boundBy: 0)
        if keyOption.waitForExistence(timeout: 1) {
            keyOption.tap()
        } else if titleOption.waitForExistence(timeout: 1) {
            titleOption.tap()
        } else {
            XCTFail("No signing key option matching \(name) was available")
            app.typeKey(.escape, modifierFlags: [])
            return
        }

        XCTAssertTrue(keyPicker.waitForExistence(timeout: 2))
        let selectedValue = (keyPicker.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(selectedValue.isEmpty, "Expected a signing key selection")
        XCTAssertFalse(selectedValue.contains("Select a key"), "Expected a signing key to be selected")
    }

    private func signMessage(
        _ message: String,
        in app: XCUIApplication,
        keyName: String = "Sign Verify User",
        passphrase: String = "SignVerifyPassphrase123!"
    ) -> String {
        navigateToSign(app)
        selectSigningKey(app, containing: keyName)
        pasteText(message, into: app)

        let signButton = signActionButton(app)
        XCTAssertTrue(signButton.isEnabled)
        signButton.tap()

        let passphraseField = app.secureTextFields["Passphrase"]
        XCTAssertTrue(passphraseField.waitForExistence(timeout: 3))
        passphraseField.tap()
        passphraseField.typeText(passphrase)

        let alertSignButton = app.dialogs.buttons["Sign"].exists
            ? app.dialogs.buttons["Sign"]
            : app.sheets.buttons["Sign"]
        if alertSignButton.waitForExistence(timeout: 1) {
            alertSignButton.tap()
        } else {
            app.typeKey(.return, modifierFlags: [])
        }

        let copyButton = app.buttons["Copy"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 20))
        copyButton.tap()

        let signedMessage = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertTrue(signedMessage.contains("-----BEGIN PGP SIGNED MESSAGE-----"))
        return signedMessage
    }

    @MainActor
    func testSignViewElements() throws {
        let app = isolatedApp()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        generateTestKey(app)
        navigateToSign(app)

        XCTAssertTrue(app.radioButtons["Text"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.radioButtons["File"].exists)
        XCTAssertTrue(app.checkBoxes["Cleartext"].exists)
        XCTAssertTrue(app.checkBoxes["Detached"].exists)
        XCTAssertTrue(app.checkBoxes["Armor"].exists)
        XCTAssertTrue(app.popUpButtons.firstMatch.exists)
        XCTAssertTrue(signActionButton(app).exists)
    }

    @MainActor
    func testSignButtonDisabledWhenNoSigningKeySelected() throws {
        let app = isolatedApp()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        generateTestKey(app)
        navigateToSign(app)
        pasteText("Message ready to sign", into: app)

        XCTAssertFalse(signActionButton(app).isEnabled)
    }

    @MainActor
    func testSignButtonDisabledWhenNoInputProvided() throws {
        let app = isolatedApp()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        generateTestKey(app)
        navigateToSign(app)
        selectSigningKey(app)

        XCTAssertFalse(signActionButton(app).isEnabled)
    }

    @MainActor
    func testVerifyViewElements() throws {
        let app = isolatedApp()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        navigateToVerify(app)

        XCTAssertTrue(app.radioButtons["Text"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.radioButtons["File"].exists)
        XCTAssertTrue(app.radioButtons["Inline"].exists)
        XCTAssertTrue(app.radioButtons["Detached"].exists)
        XCTAssertTrue(verifyActionButton(app).exists)
    }

    @MainActor
    func testVerifyFlowDisplaysValidResultForSignedMessage() throws {
        let app = isolatedApp()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        generateTestKey(app)

        let signedMessage = signMessage("Pre-populated signed message", in: app)

        navigateToVerify(app)
        pasteText(signedMessage, into: app)

        let verifyButton = verifyActionButton(app)
        XCTAssertTrue(verifyButton.isEnabled)
        verifyButton.tap()

        XCTAssertTrue(app.staticTexts["Signature Valid"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Signature is valid"].exists)
    }

    @MainActor
    func testSignThenVerifyRoundTrip() throws {
        let app = isolatedApp()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        generateTestKey(app)

        let message = "Round-trip sign and verify message"
        let signedMessage = signMessage(message, in: app)

        navigateToVerify(app)
        pasteText(signedMessage, into: app)
        verifyActionButton(app).tap()

        XCTAssertTrue(app.staticTexts["Signature Valid"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts[message].exists)
    }
}
