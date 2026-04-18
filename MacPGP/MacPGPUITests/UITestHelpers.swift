import XCTest

enum AccessibilityIdentifiers {
    enum KeyGeneration {
        static let fullNameField = "keyGeneration.fullNameField"
        static let emailField = "keyGeneration.emailField"
        static let commentField = "keyGeneration.commentField"
        static let algorithmLabel = "keyGeneration.algorithmLabel"
        static let algorithmValue = "keyGeneration.algorithmValue"
        static let keySizePicker = "keyGeneration.keySizePicker"
        static let neverExpiresToggle = "keyGeneration.neverExpiresToggle"
        static let expirationPicker = "keyGeneration.expirationPicker"
        static let passphraseField = "keyGeneration.passphraseField"
        static let confirmPassphraseField = "keyGeneration.confirmPassphraseField"
        static let storePassphraseToggle = "keyGeneration.storePassphraseToggle"
    }

    enum TrustLevelPicker {
        static let ultimateTrustWarningDescription = "Ultimate Trust Warning Description"
        static let trustLevelUpdatedMessage = "Trust Level Updated Message"

        static func description(token: String) -> String {
            "TrustDescription_\(token)"
        }

        static func canCertifyDescription(token: String) -> String {
            "TrustDescription_\(token)_CanCertify"
        }
    }
}

extension XCUIApplication {
    /// Opens the key generation form using the best available mechanism.
    ///
    /// Tries, in order: empty-state button, Cmd+N shortcut, File menu item.
    /// The Keyring sidebar item is tapped first if visible so the empty-state
    /// button is reachable when the keyring has no keys yet.
    @discardableResult
    func openKeyGenerationView(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let keyringButton = buttons["Keyring"]
        if keyringButton.exists {
            keyringButton.tap()
        }

        let emptyStateButton = buttons["Generate New Key"]
        if emptyStateButton.waitForExistence(timeout: 1) {
            emptyStateButton.tap()
            if textFields[AccessibilityIdentifiers.KeyGeneration.fullNameField].waitForExistence(timeout: 2) {
                return true
            }
        }

        activate()
        typeKey("n", modifierFlags: .command)
        if textFields[AccessibilityIdentifiers.KeyGeneration.fullNameField].waitForExistence(timeout: 2) {
            return true
        }

        let fileMenu = menuBars.menuBarItems["File"]
        if fileMenu.exists {
            fileMenu.click()

            let generateMenuItem = menuItems["Generate New Key..."].exists
                ? menuItems["Generate New Key..."]
                : menuItems["menu.generate_key"]
            if generateMenuItem.waitForExistence(timeout: 2) {
                generateMenuItem.tap()
                if textFields[AccessibilityIdentifiers.KeyGeneration.fullNameField].waitForExistence(timeout: 2) {
                    return true
                }
            } else {
                typeKey(.escape, modifierFlags: [])
            }
        }

        XCTFail("Timed out opening key generation form", file: file, line: line)
        return false
    }
}
