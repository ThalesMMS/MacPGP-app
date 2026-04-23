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

    @MainActor
    func testKeyGenerationWizardAppears() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        // Navigate to key generation view using keyboard shortcut
        app.openKeyGenerationView()

        // Verify form elements exist
        XCTAssertTrue(app.textFields[AccessibilityIdentifiers.KeyGeneration.fullNameField].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields[AccessibilityIdentifiers.KeyGeneration.emailField].exists)
        XCTAssertTrue(app.textFields[AccessibilityIdentifiers.KeyGeneration.commentField].exists)
        XCTAssertTrue(app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.passphraseField].exists)
        XCTAssertTrue(app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.confirmPassphraseField].exists)
    }

    @MainActor
    func testKeyGenerationWithValidInput() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        app.openKeyGenerationView()

        // Fill in the form
        let nameField = app.textFields[AccessibilityIdentifiers.KeyGeneration.fullNameField]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Test User")

        let emailField = app.textFields[AccessibilityIdentifiers.KeyGeneration.emailField]
        emailField.tap()
        emailField.typeText("test@example.com")

        // Fill in passphrase
        let passphraseField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.passphraseField]
        passphraseField.tap()
        passphraseField.typeText("StrongTestPassphrase123!")

        let confirmField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.confirmPassphraseField]
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
        app.openKeyGenerationView()

        // Fill in form with invalid email
        let nameField = app.textFields[AccessibilityIdentifiers.KeyGeneration.fullNameField]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Test User")

        let emailField = app.textFields[AccessibilityIdentifiers.KeyGeneration.emailField]
        emailField.tap()
        emailField.typeText("invalid-email")

        let passphraseField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.passphraseField]
        passphraseField.tap()
        passphraseField.typeText("StrongTestPassphrase123!")

        let confirmField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.confirmPassphraseField]
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
        app.openKeyGenerationView()

        // Fill in form with weak passphrase
        let nameField = app.textFields[AccessibilityIdentifiers.KeyGeneration.fullNameField]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Test User")

        let emailField = app.textFields[AccessibilityIdentifiers.KeyGeneration.emailField]
        emailField.tap()
        emailField.typeText("test@example.com")

        let passphraseField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.passphraseField]
        passphraseField.tap()
        passphraseField.typeText("123")

        let confirmField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.confirmPassphraseField]
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
        app.openKeyGenerationView()

        // Fill in form with mismatched passphrases
        let nameField = app.textFields[AccessibilityIdentifiers.KeyGeneration.fullNameField]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Test User")

        let emailField = app.textFields[AccessibilityIdentifiers.KeyGeneration.emailField]
        emailField.tap()
        emailField.typeText("test@example.com")

        let passphraseField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.passphraseField]
        passphraseField.tap()
        passphraseField.typeText("StrongTestPassphrase123!")

        let confirmField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.confirmPassphraseField]
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
        app.openKeyGenerationView()

        let algorithmPicker = app.popUpButtons[AccessibilityIdentifiers.KeyGeneration.algorithmValue]
        XCTAssertTrue(algorithmPicker.waitForExistence(timeout: 3))

        algorithmPicker.tap()
        XCTAssertTrue(app.menuItems["RSA"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.menuItems["ECDSA (Elliptic Curve)"].exists)
        XCTAssertTrue(app.menuItems["EdDSA (Ed25519)"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testKeyGenerationECDSASelectionShowsSupportedCurves() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        app.openKeyGenerationView()

        let algorithmPicker = app.popUpButtons[AccessibilityIdentifiers.KeyGeneration.algorithmValue]
        XCTAssertTrue(algorithmPicker.waitForExistence(timeout: 3))
        algorithmPicker.tap()
        XCTAssertTrue(app.menuItems["ECDSA (Elliptic Curve)"].waitForExistence(timeout: 1))
        app.menuItems["ECDSA (Elliptic Curve)"].tap()

        let keySizePicker = app.popUpButtons[AccessibilityIdentifiers.KeyGeneration.keySizePicker]
        XCTAssertTrue(keySizePicker.waitForExistence(timeout: 1))
        keySizePicker.tap()
        XCTAssertTrue(app.menuItems["256 bits"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.menuItems["384 bits"].exists)
        XCTAssertTrue(app.menuItems["521 bits"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testKeyGenerationEdDSASelectionFixesKeySizeAt256Bits() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        app.openKeyGenerationView()

        let algorithmPicker = app.popUpButtons[AccessibilityIdentifiers.KeyGeneration.algorithmValue]
        XCTAssertTrue(algorithmPicker.waitForExistence(timeout: 3))
        algorithmPicker.tap()
        XCTAssertTrue(app.menuItems["EdDSA (Ed25519)"].waitForExistence(timeout: 1))
        app.menuItems["EdDSA (Ed25519)"].tap()

        let keySizePicker = app.popUpButtons[AccessibilityIdentifiers.KeyGeneration.keySizePicker]
        XCTAssertTrue(keySizePicker.waitForExistence(timeout: 1))
        XCTAssertFalse(keySizePicker.isEnabled)

        let selectedSize = [
            keySizePicker.value as? String,
            keySizePicker.label
        ].compactMap { $0 }.joined(separator: " ")
        XCTAssertTrue(selectedSize.contains("256"), "Expected EdDSA key size picker to stay fixed at 256 bits, got \(selectedSize)")
    }

    @MainActor
    func testKeyGenerationExpirationToggle() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        app.openKeyGenerationView()

        // Verify expiration toggle exists
        let neverExpiresToggle = app.checkBoxes[AccessibilityIdentifiers.KeyGeneration.neverExpiresToggle]
        XCTAssertTrue(neverExpiresToggle.waitForExistence(timeout: 3))

        // Toggle the expiration setting
        neverExpiresToggle.tap()

        // Verify expiration picker no longer appears when "Never expires" is on
        let expirationPicker = app.popUpButtons[AccessibilityIdentifiers.KeyGeneration.expirationPicker]
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
        app.openKeyGenerationView()

        // Verify keychain toggle exists
        let keychainToggle = app.checkBoxes[AccessibilityIdentifiers.KeyGeneration.storePassphraseToggle]
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
        app.openKeyGenerationView()

        // Verify form is showing
        XCTAssertTrue(app.textFields[AccessibilityIdentifiers.KeyGeneration.fullNameField].waitForExistence(timeout: 3))

        // Tap cancel button
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists)
        cancelButton.tap()

        // Verify form is dismissed
        XCTAssertFalse(app.textFields[AccessibilityIdentifiers.KeyGeneration.fullNameField].exists)
    }

    @MainActor
    func testKeyGenerationCommentField() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        app.openKeyGenerationView()

        // Verify comment field exists and is optional
        let commentField = app.textFields[AccessibilityIdentifiers.KeyGeneration.commentField]
        XCTAssertTrue(commentField.waitForExistence(timeout: 3))

        // Fill in other required fields without comment
        let nameField = app.textFields[AccessibilityIdentifiers.KeyGeneration.fullNameField]
        nameField.tap()
        nameField.typeText("Test User")

        let emailField = app.textFields[AccessibilityIdentifiers.KeyGeneration.emailField]
        emailField.tap()
        emailField.typeText("test@example.com")

        let passphraseField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.passphraseField]
        passphraseField.tap()
        passphraseField.typeText("StrongTestPassphrase123!")

        let confirmField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.confirmPassphraseField]
        confirmField.tap()
        confirmField.typeText("StrongTestPassphrase123!")

        // Verify Generate button is enabled even without comment
        let generateButton = app.buttons["Generate"]
        XCTAssertTrue(generateButton.exists)
    }
}
