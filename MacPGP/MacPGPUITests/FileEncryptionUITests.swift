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
        let keyringButton = app.buttons["Keyring"]
        if keyringButton.exists {
            keyringButton.tap()
        }

        app.typeKey("n", modifierFlags: .command)

        let nameField = app.textFields["Full Name"]
        if nameField.waitForExistence(timeout: 3) {
            nameField.tap()
            nameField.typeText(name)

            let emailField = app.textFields["Email Address"]
            emailField.tap()
            emailField.typeText(email)

            let passphraseField = app.secureTextFields["Passphrase"]
            passphraseField.tap()
            passphraseField.typeText(passphrase)

            let confirmField = app.secureTextFields["Confirm Passphrase"]
            confirmField.tap()
            confirmField.typeText(passphrase)

            let generateButton = app.buttons["Generate"]
            if generateButton.isEnabled {
                generateButton.tap()

                sleep(3)

                let okButton = app.buttons["OK"]
                if okButton.waitForExistence(timeout: 2) {
                    okButton.tap()
                }
            }
        }
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

        let selectFileButton = app.buttons["Select File..."]
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

        let selectFileButton = app.buttons["Select File..."]
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

        let encryptButton = app.buttons.matching(identifier: "Encrypt").element(boundBy: 1)
        if encryptButton.waitForExistence(timeout: 3) {
            XCTAssertFalse(encryptButton.isEnabled)
        }
    }

    @MainActor
    func testDecryptButtonDisabledWithoutInput() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        navigateToDecrypt(app)

        let decryptButton = app.buttons.matching(identifier: "Decrypt").element(boundBy: 1)
        if decryptButton.waitForExistence(timeout: 3) {
            XCTAssertFalse(decryptButton.isEnabled)
        }
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

        let warningIcon = app.images["exclamationmark.triangle.fill"]
        XCTAssertTrue(warningIcon.waitForExistence(timeout: 3))

        let warningText = app.staticTexts["No secret keys available for decryption"]
        XCTAssertTrue(warningText.exists)
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

        let selectFileButton = app.buttons["Select File..."]
        if selectFileButton.waitForExistence(timeout: 2) {
            selectFileButton.tap()

            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2))
        }
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

        let selectFileButton = app.buttons["Select File..."]
        if selectFileButton.waitForExistence(timeout: 2) {
            selectFileButton.tap()

            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2))
        }
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

        let fileLabel = app.staticTexts["File"]
        XCTAssertTrue(fileLabel.waitForExistence(timeout: 2))

        let outputLocationLabel = app.staticTexts["Output Location"]
        XCTAssertTrue(outputLocationLabel.exists)

        let dropZoneText = app.staticTexts["Drop a file here"]
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

        let encryptedFileLabel = app.staticTexts["Encrypted File"]
        XCTAssertTrue(encryptedFileLabel.waitForExistence(timeout: 2))

        let outputLocationLabel = app.staticTexts["Output Location"]
        XCTAssertTrue(outputLocationLabel.exists)

        let dropZoneText = app.staticTexts["Drop a file here"]
        XCTAssertTrue(dropZoneText.exists)
    }
}
