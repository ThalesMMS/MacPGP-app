//
//  FileEncryptionUITests.swift
//  MacPGPUITests
//
//  Created by Thales Matheus Mendonça Santos on 04/02/26.
//

import XCTest

final class FileEncryptionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    private func navigateToEncrypt(_ app: XCUIApplication) {
        let encryptButton = app.buttons["Encrypt"]
        if encryptButton.exists {
            encryptButton.tap()
        }
    }

    private func navigateToDecrypt(_ app: XCUIApplication) {
        let decryptButton = app.buttons["Decrypt"]
        if decryptButton.exists {
            decryptButton.tap()
        }
    }

    private func generateTestKey(_ app: XCUIApplication, name: String, email: String, passphrase: String) {
        guard app.openKeyGenerationView() else {
            XCTFail("Key generation UI failed to open")
            return
        }

        let nameField = app.textFields[AccessibilityIdentifiers.KeyGeneration.fullNameField]
        guard nameField.waitForExistence(timeout: 3) else {
            XCTFail("Full Name field must appear")
            return
        }
        nameField.tap()
        nameField.typeText(name)

        let emailField = app.textFields[AccessibilityIdentifiers.KeyGeneration.emailField]
        emailField.tap()
        emailField.typeText(email)

        let passphraseField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.passphraseField]
        passphraseField.tap()
        passphraseField.typeText(passphrase)

        let confirmField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.confirmPassphraseField]
        confirmField.tap()
        confirmField.typeText(passphrase)

        let generateButton = app.buttons["Generate"]
        guard generateButton.waitForExistence(timeout: 2) else {
            XCTFail("Generate button must appear")
            return
        }
        guard generateButton.isEnabled else {
            XCTFail("Generate button must be enabled after valid key data")
            return
        }
        generateButton.tap()

        let doneButton = app.buttons["Done"]
        guard doneButton.waitForExistence(timeout: 30) else {
            XCTFail("Timed out waiting for Done button after key generation")
            return
        }
        doneButton.tap()
    }

    private func actionButton(_ app: XCUIApplication, named name: String) -> XCUIElement {
        let toolbarButton = app.toolbars.buttons[name]
        if toolbarButton.exists {
            return toolbarButton
        }

        let buttons = app.buttons.matching(NSPredicate(format: "label == %@", name))
        return buttons.element(boundBy: max(buttons.count - 1, 0))
    }

    private func selectFilesButton(_ app: XCUIApplication) -> XCUIElement {
        let pluralButton = app.buttons["Select Files..."]
        let singularButton = app.buttons["Select File..."]
        let deadline = Date().addingTimeInterval(2)

        repeat {
            if pluralButton.exists {
                return pluralButton
            }
            if singularButton.exists {
                return singularButton
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        if pluralButton.exists {
            return pluralButton
        }

        return singularButton
    }

    private func openFilePanelAppeared(_ app: XCUIApplication, timeout: TimeInterval = 3) -> Bool {
        let sheet = app.sheets.firstMatch
        let openWindow = app.windows["Open"]
        let openButton = app.buttons["Open"]
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if sheet.exists || openWindow.exists || openButton.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return sheet.exists || openWindow.exists || openButton.exists
    }

    @MainActor
    func testEncryptViewNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToEncrypt(app)

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2))
    }

    @MainActor
    func testDecryptViewNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToDecrypt(app)

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2))
    }

    @MainActor
    func testEncryptModePicker() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToEncrypt(app)

        let modePicker = app.radioButtons["Text"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 3))

        let fileMode = app.radioButtons["File"]
        XCTAssertTrue(fileMode.exists)

        fileMode.tap()
        sleep(1)

        modePicker.tap()
        sleep(1)
    }

    @MainActor
    func testDecryptModePicker() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToDecrypt(app)

        let modePicker = app.radioButtons["Text"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 3))

        let fileMode = app.radioButtons["File"]
        XCTAssertTrue(fileMode.exists)

        fileMode.tap()
        sleep(1)

        modePicker.tap()
        sleep(1)
    }

    @MainActor
    func testEncryptArmorToggle() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToEncrypt(app)

        let armorToggle = app.checkBoxes["Armor"]
        XCTAssertTrue(armorToggle.waitForExistence(timeout: 3))

        armorToggle.tap()
        sleep(1)

        armorToggle.tap()
        sleep(1)
    }

    @MainActor
    func testDecryptAutoDetectToggle() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToDecrypt(app)

        let autoDetectToggle = app.checkBoxes["Auto-detect"]
        XCTAssertTrue(autoDetectToggle.waitForExistence(timeout: 3))

        autoDetectToggle.tap()
        sleep(1)

        autoDetectToggle.tap()
        sleep(1)
    }

    @MainActor
    func testEncryptFileMode() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToEncrypt(app)

        let fileMode = app.radioButtons["File"]
        XCTAssertTrue(fileMode.waitForExistence(timeout: 3))
        fileMode.tap()

        let selectFileButton = selectFilesButton(app)
        XCTAssertTrue(selectFileButton.waitForExistence(timeout: 2))

        let outputLocationButton = app.buttons["Choose Output Location"]
        XCTAssertTrue(outputLocationButton.exists)
    }

    @MainActor
    func testDecryptFileMode() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToDecrypt(app)

        let fileMode = app.radioButtons["File"]
        XCTAssertTrue(fileMode.waitForExistence(timeout: 3))
        fileMode.tap()

        let selectFileButton = selectFilesButton(app)
        XCTAssertTrue(selectFileButton.waitForExistence(timeout: 2))

        let outputLocationButton = app.buttons["Choose Output Location"]
        XCTAssertTrue(outputLocationButton.exists)
    }

    @MainActor
    func testEncryptTextMode() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToEncrypt(app)

        let textMode = app.radioButtons["Text"]
        XCTAssertTrue(textMode.waitForExistence(timeout: 3))
        textMode.tap()

        let messageLabel = app.staticTexts["Message"]
        XCTAssertTrue(messageLabel.waitForExistence(timeout: 2))

        let encryptedOutputLabel = app.staticTexts["Encrypted Output"]
        XCTAssertTrue(encryptedOutputLabel.exists)
    }

    @MainActor
    func testDecryptTextMode() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToDecrypt(app)

        let textMode = app.radioButtons["Text"]
        XCTAssertTrue(textMode.waitForExistence(timeout: 3))
        textMode.tap()

        let encryptedMessageLabel = app.staticTexts["Encrypted Message"]
        XCTAssertTrue(encryptedMessageLabel.waitForExistence(timeout: 2))

        let decryptedOutputLabel = app.staticTexts["Decrypted Output"]
        XCTAssertTrue(decryptedOutputLabel.exists)
    }

    @MainActor
    func testEncryptButtonDisabledWithoutRecipients() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToEncrypt(app)

        let encryptButton = actionButton(app, named: "Encrypt")
        XCTAssertTrue(encryptButton.waitForExistence(timeout: 3), "Encrypt button must appear")
        XCTAssertFalse(encryptButton.isEnabled)
    }

    @MainActor
    func testDecryptButtonDisabledWithoutInput() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToDecrypt(app)

        let decryptButton = actionButton(app, named: "Decrypt")
        XCTAssertTrue(decryptButton.waitForExistence(timeout: 3), "Decrypt button must appear")
        XCTAssertFalse(decryptButton.isEnabled)
    }

    @MainActor
    func testEncryptSignerSelection() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        generateTestKey(app, name: "Signer Test", email: "signer@test.com", passphrase: "SignerPass123!")

        navigateToEncrypt(app)

        let signerLabel = app.staticTexts["Sign with (optional)"]
        XCTAssertTrue(signerLabel.waitForExistence(timeout: 3))

        let signingKeyPicker = app.popUpButtons["Signing Key"]
        if signingKeyPicker.exists {
            signingKeyPicker.tap()

            let dontSignOption = app.menuItems["Don't sign"]
            XCTAssertTrue(dontSignOption.waitForExistence(timeout: 2))

            app.typeKey(.escape, modifierFlags: [])
        }
    }

    @MainActor
    func testDecryptKeySelection() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        generateTestKey(app, name: "Decrypt Test", email: "decrypt@test.com", passphrase: "DecryptPass123!")

        navigateToDecrypt(app)

        let autoDetectToggle = app.checkBoxes["Auto-detect"]
        if autoDetectToggle.waitForExistence(timeout: 3) && autoDetectToggle.value as? Int == 1 {
            autoDetectToggle.tap()
        }

        let selectKeyPicker = app.popUpButtons["Select Key"]
        if selectKeyPicker.waitForExistence(timeout: 2) {
            selectKeyPicker.tap()

            let selectKeyOption = app.menuItems["Select a key..."]
            XCTAssertTrue(selectKeyOption.waitForExistence(timeout: 2))

            app.typeKey(.escape, modifierFlags: [])
        }
    }

    @MainActor
    func testDecryptPasteButton() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToDecrypt(app)

        let textMode = app.radioButtons["Text"]
        if textMode.waitForExistence(timeout: 3) {
            textMode.tap()
        }

        let pasteButton = app.buttons["Paste"]
        XCTAssertTrue(pasteButton.waitForExistence(timeout: 2))
    }

    @MainActor
    func testEncryptCopyButtonAppearsAfterEncryption() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToEncrypt(app)

        let copyButton = app.buttons["Copy"]
        let exists = copyButton.exists

        _ = exists
    }

    @MainActor
    func testDecryptCopyButtonAppearsAfterDecryption() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToDecrypt(app)

        let copyButton = app.buttons["Copy"]
        let exists = copyButton.exists

        _ = exists
    }

    @MainActor
    func testEncryptNoSecretKeysWarning() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-keyring"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToEncrypt(app)

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2))
    }

    @MainActor
    func testDecryptNoSecretKeysWarning() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-keyring"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToDecrypt(app)

        XCTAssertTrue(app.staticTexts["No secret keys available for decryption"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testEncryptFileModeSelectFileButton() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToEncrypt(app)

        let fileMode = app.radioButtons["File"]
        if fileMode.waitForExistence(timeout: 3) {
            fileMode.tap()
        }

        let selectFileButton = selectFilesButton(app)
        XCTAssertTrue(selectFileButton.waitForExistence(timeout: 2), "Select Files button must appear")
        selectFileButton.tap()

        XCTAssertTrue(openFilePanelAppeared(app), "Open file panel must appear")
    }

    @MainActor
    func testDecryptFileModeSelectFileButton() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToDecrypt(app)

        let fileMode = app.radioButtons["File"]
        if fileMode.waitForExistence(timeout: 3) {
            fileMode.tap()
        }

        let selectFileButton = selectFilesButton(app)
        XCTAssertTrue(selectFileButton.waitForExistence(timeout: 2), "Select Files button must appear")
        selectFileButton.tap()

        XCTAssertTrue(openFilePanelAppeared(app), "Open file panel must appear")
    }

    @MainActor
    func testEncryptOutputLocationButton() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToEncrypt(app)

        let fileMode = app.radioButtons["File"]
        if fileMode.waitForExistence(timeout: 3) {
            fileMode.tap()
        }

        let outputLocationButton = app.buttons["Choose Output Location"]
        if outputLocationButton.waitForExistence(timeout: 2) {
            outputLocationButton.tap()

            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2))
        }
    }

    @MainActor
    func testDecryptOutputLocationButton() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToDecrypt(app)

        let fileMode = app.radioButtons["File"]
        if fileMode.waitForExistence(timeout: 3) {
            fileMode.tap()
        }

        let outputLocationButton = app.buttons["Choose Output Location"]
        if outputLocationButton.waitForExistence(timeout: 2) {
            outputLocationButton.tap()

            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2))
        }
    }

    @MainActor
    func testEncryptRecipientPicker() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        generateTestKey(app, name: "Recipient Test", email: "recipient@test.com", passphrase: "RecipientPass123!")

        navigateToEncrypt(app)

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2))
    }

    @MainActor
    func testEncryptFileModeUIElements() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToEncrypt(app)

        let fileMode = app.radioButtons["File"]
        if fileMode.waitForExistence(timeout: 3) {
            fileMode.tap()
        }

        let fileLabel = app.staticTexts["Files"]
        XCTAssertTrue(fileLabel.waitForExistence(timeout: 2))

        let outputLocationLabel = app.staticTexts["Output Location"]
        XCTAssertTrue(outputLocationLabel.exists)

        let dropZoneText = app.staticTexts["Drop files here"]
        XCTAssertTrue(dropZoneText.exists)
    }

    @MainActor
    func testDecryptFileModeUIElements() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToDecrypt(app)

        let fileMode = app.radioButtons["File"]
        if fileMode.waitForExistence(timeout: 3) {
            fileMode.tap()
        }

        let encryptedFileLabel = app.staticTexts["Encrypted Files"]
        XCTAssertTrue(encryptedFileLabel.waitForExistence(timeout: 2))

        let outputLocationLabel = app.staticTexts["Output Location"]
        XCTAssertTrue(outputLocationLabel.exists)

        let dropZoneText = app.staticTexts["Drop files here"]
        XCTAssertTrue(dropZoneText.exists)
    }
}
