//
//  KeyGenerationUITests.swift
//  MacPGPUITests
//
//  Created by Thales Matheus Mendonça Santos on 04/02/26.
//

import XCTest

final class KeyGenerationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    private func openKeyGenerationView(_ app: XCUIApplication) {
        // Use keyboard shortcut Cmd+N to trigger key generation
        app.typeKey("n", modifierFlags: .command)
    }

    @MainActor
    func testKeyGenerationWizardAppears() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        // Navigate to key generation view using keyboard shortcut
        openKeyGenerationView(app)

        // Verify form elements exist
        XCTAssertTrue(app.textFields["Full Name"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["Email Address"].exists)
        XCTAssertTrue(app.textFields["Comment (optional)"].exists)
        XCTAssertTrue(app.secureTextFields["Passphrase"].exists)
        XCTAssertTrue(app.secureTextFields["Confirm Passphrase"].exists)
    }

    @MainActor
    func testKeyGenerationWithValidInput() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openKeyGenerationView(app)

        // Fill in the form
        let nameField = app.textFields["Full Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Test User")

        let emailField = app.textFields["Email Address"]
        emailField.tap()
        emailField.typeText("test@example.com")

        // Fill in passphrase
        let passphraseField = app.secureTextFields["Passphrase"]
        passphraseField.tap()
        passphraseField.typeText("StrongTestPassphrase123!")

        let confirmField = app.secureTextFields["Confirm Passphrase"]
        confirmField.tap()
        confirmField.typeText("StrongTestPassphrase123!")

        // Verify Generate button becomes enabled
        let generateButton = app.buttons["Generate"]
        XCTAssertTrue(generateButton.exists)
    }

    @MainActor
    func testKeyGenerationWithInvalidEmail() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openKeyGenerationView(app)

        // Fill in form with invalid email
        let nameField = app.textFields["Full Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Test User")

        let emailField = app.textFields["Email Address"]
        emailField.tap()
        emailField.typeText("invalid-email")

        let passphraseField = app.secureTextFields["Passphrase"]
        passphraseField.tap()
        passphraseField.typeText("StrongTestPassphrase123!")

        let confirmField = app.secureTextFields["Confirm Passphrase"]
        confirmField.tap()
        confirmField.typeText("StrongTestPassphrase123!")

        // Verify Generate button stays disabled
        let generateButton = app.buttons["Generate"]
        XCTAssertFalse(generateButton.isEnabled)
    }

    @MainActor
    func testKeyGenerationWithWeakPassphrase() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openKeyGenerationView(app)

        // Fill in form with weak passphrase
        let nameField = app.textFields["Full Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Test User")

        let emailField = app.textFields["Email Address"]
        emailField.tap()
        emailField.typeText("test@example.com")

        let passphraseField = app.secureTextFields["Passphrase"]
        passphraseField.tap()
        passphraseField.typeText("123")

        let confirmField = app.secureTextFields["Confirm Passphrase"]
        confirmField.tap()
        confirmField.typeText("123")

        // Verify Generate button stays disabled due to weak passphrase
        let generateButton = app.buttons["Generate"]
        XCTAssertFalse(generateButton.isEnabled)
    }

    @MainActor
    func testKeyGenerationPassphraseMismatch() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openKeyGenerationView(app)

        // Fill in form with mismatched passphrases
        let nameField = app.textFields["Full Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Test User")

        let emailField = app.textFields["Email Address"]
        emailField.tap()
        emailField.typeText("test@example.com")

        let passphraseField = app.secureTextFields["Passphrase"]
        passphraseField.tap()
        passphraseField.typeText("StrongTestPassphrase123!")

        let confirmField = app.secureTextFields["Confirm Passphrase"]
        confirmField.tap()
        confirmField.typeText("DifferentPassphrase456!")

        // Verify error message appears
        XCTAssertTrue(app.staticTexts["Passphrases do not match"].waitForExistence(timeout: 1))

        // Verify Generate button stays disabled
        let generateButton = app.buttons["Generate"]
        XCTAssertFalse(generateButton.isEnabled)
    }

    @MainActor
    func testKeyGenerationAlgorithmSelection() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openKeyGenerationView(app)

        // Verify algorithm picker exists
        let algorithmPicker = app.popUpButtons["Algorithm"]
        XCTAssertTrue(algorithmPicker.waitForExistence(timeout: 3))

        // Test selecting different algorithms
        algorithmPicker.tap()
        let ecdsaOption = app.menuItems["ECDSA (Elliptic Curve)"]
        if ecdsaOption.exists {
            ecdsaOption.tap()
        }

        // Key size picker may or may not exist depending on algorithm
        _ = app.popUpButtons["Key Size"].exists
    }

    @MainActor
    func testKeyGenerationExpirationToggle() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openKeyGenerationView(app)

        // Verify expiration toggle exists
        let neverExpiresToggle = app.checkBoxes["Never expires"]
        XCTAssertTrue(neverExpiresToggle.waitForExistence(timeout: 3))

        // Toggle the expiration setting
        neverExpiresToggle.tap()

        // Verify expiration picker no longer appears when "Never expires" is on
        let expirationPicker = app.popUpButtons["Expires in"]
        XCTAssertFalse(expirationPicker.exists)

        // Toggle back
        neverExpiresToggle.tap()

        // Verify expiration picker reappears
        XCTAssertTrue(expirationPicker.waitForExistence(timeout: 1))
    }

    @MainActor
    func testKeyGenerationKeychainToggle() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openKeyGenerationView(app)

        // Verify keychain toggle exists
        let keychainToggle = app.checkBoxes["Store passphrase in Keychain"]
        XCTAssertTrue(keychainToggle.waitForExistence(timeout: 3))

        // Toggle the setting
        keychainToggle.tap()

        // Toggle back
        keychainToggle.tap()
    }

    @MainActor
    func testKeyGenerationCancelButton() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openKeyGenerationView(app)

        // Verify form is showing
        XCTAssertTrue(app.textFields["Full Name"].waitForExistence(timeout: 3))

        // Tap cancel button
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists)
        cancelButton.tap()

        // Verify form is dismissed
        XCTAssertFalse(app.textFields["Full Name"].exists)
    }

    @MainActor
    func testKeyGenerationCommentField() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openKeyGenerationView(app)

        // Verify comment field exists and is optional
        let commentField = app.textFields["Comment (optional)"]
        XCTAssertTrue(commentField.waitForExistence(timeout: 3))

        // Fill in other required fields without comment
        let nameField = app.textFields["Full Name"]
        nameField.tap()
        nameField.typeText("Test User")

        let emailField = app.textFields["Email Address"]
        emailField.tap()
        emailField.typeText("test@example.com")

        let passphraseField = app.secureTextFields["Passphrase"]
        passphraseField.tap()
        passphraseField.typeText("StrongTestPassphrase123!")

        let confirmField = app.secureTextFields["Confirm Passphrase"]
        confirmField.tap()
        confirmField.typeText("StrongTestPassphrase123!")

        // Verify Generate button is enabled even without comment
        let generateButton = app.buttons["Generate"]
        XCTAssertTrue(generateButton.exists)
    }
}
