//
//  TrustLevelUITests.swift
//  MacPGPUITests
//
//  Created by auto-claude on 10/02/26.
//

import XCTest

final class TrustLevelUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    private func launchAppAndGenerateTestKey(_ app: XCUIApplication) throws {
        app.launchArguments = ["--reset-keyring"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        XCTAssertTrue(app.openKeyGenerationView())

        // Fill in the form
        let nameField = app.textFields[AccessibilityIdentifiers.KeyGeneration.fullNameField]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Trust Test User")

        let emailField = app.textFields[AccessibilityIdentifiers.KeyGeneration.emailField]
        emailField.tap()
        emailField.typeText("trusttest@example.com")

        let passphraseField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.passphraseField]
        passphraseField.tap()
        passphraseField.typeText("TrustTestPassphrase123!")

        let confirmField = app.secureTextFields[AccessibilityIdentifiers.KeyGeneration.confirmPassphraseField]
        confirmField.tap()
        confirmField.typeText("TrustTestPassphrase123!")

        // Generate key
        clickWhenReady(app.buttons["Generate"], named: "Generate button", timeout: 2)

        // Wait for key generation to complete
        clickWhenReady(app.buttons["Done"], named: "Done button", timeout: 30)
    }

    private func openFirstKeyDetails(_ app: XCUIApplication) {
        let keyRowPredicate = NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "KeyRow-",
            "Trust Test User"
        )
        let keyRow = app.descendants(matching: .any).matching(keyRowPredicate).firstMatch
        clickWhenReady(keyRow, named: "Trust Test User key row", timeout: 5)
        XCTAssertTrue(app.buttons["Set Trust Level"].waitForExistence(timeout: 3))
    }

    private func openTrustLevelPicker(_ app: XCUIApplication) {
        // Click the "Set Trust Level" toolbar button
        clickWhenReady(app.buttons["Set Trust Level"], named: "Set Trust Level button")
    }

    private func clickWhenReady(
        _ element: XCUIElement,
        named name: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("\(name) must exist before clicking", file: file, line: line)
            return
        }

        let deadline = Date().addingTimeInterval(timeout)
        while !element.isEnabled && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        guard element.isEnabled else {
            XCTFail("\(name) must be enabled before clicking", file: file, line: line)
            return
        }

        element.click()
    }

    @MainActor
    func testTrustLevelPickerAppears() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)
        openTrustLevelPicker(app)

        // Verify trust level picker sheet appears
        XCTAssertTrue(app.staticTexts["Set Trust Level"].waitForExistence(timeout: 2))

        // Verify key information section exists
        XCTAssertTrue(app.staticTexts["Key Information"].exists)
        XCTAssertTrue(app.staticTexts["Trust Test User"].exists)
        XCTAssertTrue(app.staticTexts["trusttest@example.com"].exists)

        // Verify trust level picker exists
        XCTAssertTrue(app.staticTexts["Trust Level"].exists)

        // Verify all trust level options are visible
        XCTAssertTrue(app.radioButtons["Unknown"].exists)
        XCTAssertTrue(app.radioButtons["Never"].exists)
        XCTAssertTrue(app.radioButtons["Marginal"].exists)
        XCTAssertTrue(app.radioButtons["Full"].exists)
        XCTAssertTrue(app.radioButtons["Ultimate"].exists)

        // Verify description section exists
        XCTAssertTrue(app.staticTexts["What This Means"].exists)

        // Verify save button exists
        XCTAssertTrue(app.buttons["Save Trust Level"].exists)

        // Verify cancel button exists
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    @MainActor
    func testSaveButtonDisabledWithNoChanges() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)
        openTrustLevelPicker(app)

        // Verify save button exists and is disabled initially (no changes)
        let saveButton = app.buttons["Save Trust Level"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        XCTAssertFalse(saveButton.isEnabled)

        // Verify "No changes to save" message appears
        XCTAssertTrue(app.staticTexts["No changes to save"].exists)
    }

    @MainActor
    func testSelectingDifferentTrustLevels() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)
        openTrustLevelPicker(app)

        // Test selecting "Never"
        let neverTrustRadio = app.radioButtons["Never"]
        clickWhenReady(neverTrustRadio, named: "Never radio button", timeout: 2)

        // Verify save button becomes enabled
        let saveButton = app.buttons["Save Trust Level"]
        XCTAssertTrue(saveButton.isEnabled)

        // Test selecting "Marginal"
        let marginalTrustRadio = app.radioButtons["Marginal"]
        clickWhenReady(marginalTrustRadio, named: "Marginal radio button")
        XCTAssertTrue(saveButton.isEnabled)

        // Test selecting "Full"
        let fullTrustRadio = app.radioButtons["Full"]
        clickWhenReady(fullTrustRadio, named: "Full radio button")
        XCTAssertTrue(saveButton.isEnabled)

        // Test selecting "Ultimate"
        let ultimateTrustRadio = app.radioButtons["Ultimate"]
        clickWhenReady(ultimateTrustRadio, named: "Ultimate radio button")
        XCTAssertTrue(saveButton.isEnabled)

        // Test selecting back to "Unknown" (original value)
        let unknownRadio = app.radioButtons["Unknown"]
        clickWhenReady(unknownRadio, named: "Unknown radio button")

        // Verify save button becomes disabled again (back to original)
        XCTAssertFalse(saveButton.isEnabled)
    }

    @MainActor
    func testUltimateTrustWarningAppears() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)
        openTrustLevelPicker(app)

        // Select Ultimate
        let ultimateTrustRadio = app.radioButtons["Ultimate"]
        clickWhenReady(ultimateTrustRadio, named: "Ultimate radio button", timeout: 2)

        // Verify warning appears
        XCTAssertTrue(app.staticTexts["Ultimate Trust Warning"].waitForExistence(timeout: 1))
        XCTAssertTrue(
            app.staticTexts[
                AccessibilityIdentifiers.TrustLevelPicker.ultimateTrustWarningDescription
            ].exists
        )

        // Select a different trust level
        let marginalTrustRadio = app.radioButtons["Marginal"]
        clickWhenReady(marginalTrustRadio, named: "Marginal radio button")

        // Verify warning disappears
        XCTAssertFalse(app.staticTexts["Ultimate Trust Warning"].exists)
    }

    @MainActor
    func testSavingTrustLevel() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)
        openTrustLevelPicker(app)

        // Select Full
        let fullTrustRadio = app.radioButtons["Full"]
        clickWhenReady(fullTrustRadio, named: "Full radio button", timeout: 2)

        // Click Save button
        let saveButton = app.buttons["Save Trust Level"]
        clickWhenReady(saveButton, named: "Save Trust Level button")

        // Verify success view appears
        XCTAssertTrue(app.staticTexts["Trust Level Updated"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts[
                AccessibilityIdentifiers.TrustLevelPicker.trustLevelUpdatedMessage
            ].waitForExistence(timeout: 1)
        )

        // Verify Done button exists
        let doneButton = app.buttons["Done"]
        clickWhenReady(doneButton, named: "Done button")

        // Verify we're back at key details
        XCTAssertTrue(app.buttons["Set Trust Level"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCancelWithoutSaving() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)
        openTrustLevelPicker(app)

        // Select a different trust level
        let fullTrustRadio = app.radioButtons["Full"]
        clickWhenReady(fullTrustRadio, named: "Full radio button", timeout: 2)

        // Verify save button is enabled
        let saveButton = app.buttons["Save Trust Level"]
        XCTAssertTrue(saveButton.isEnabled)

        // Click Cancel button
        let cancelButton = app.buttons["Cancel"]
        clickWhenReady(cancelButton, named: "Cancel button")

        // Verify we're back at key details
        XCTAssertTrue(app.buttons["Set Trust Level"].waitForExistence(timeout: 2))

        // Open trust level picker again
        openTrustLevelPicker(app)

        // Verify trust level is still "Unknown" (wasn't saved)
        let unknownRadio = app.radioButtons["Unknown"]
        XCTAssertTrue(unknownRadio.waitForExistence(timeout: 2))
        XCTAssertEqual(unknownRadio.value as? Int, 1) // Radio button value 1 means selected
    }

    @MainActor
    func testTrustLevelPersistsAfterSaving() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)
        openTrustLevelPicker(app)

        // Select Marginal
        let marginalTrustRadio = app.radioButtons["Marginal"]
        clickWhenReady(marginalTrustRadio, named: "Marginal radio button", timeout: 2)

        // Save
        let saveButton = app.buttons["Save Trust Level"]
        clickWhenReady(saveButton, named: "Save Trust Level button")

        // Wait for success and close
        let doneButton = app.buttons["Done"]
        clickWhenReady(doneButton, named: "Done button")

        // Open trust level picker again
        openTrustLevelPicker(app)

        // Verify Marginal is selected
        let marginalTrustRadioAgain = app.radioButtons["Marginal"]
        XCTAssertTrue(marginalTrustRadioAgain.waitForExistence(timeout: 2))
        XCTAssertEqual(marginalTrustRadioAgain.value as? Int, 1) // Radio button value 1 means selected

        // Verify save button is disabled (no changes from saved state)
        let saveButtonAgain = app.buttons["Save Trust Level"]
        XCTAssertFalse(saveButtonAgain.isEnabled)
    }

    @MainActor
    func testTrustLevelDisplayedInKeyDetails() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)
        openTrustLevelPicker(app)

        // Select Full
        let fullTrustRadio = app.radioButtons["Full"]
        clickWhenReady(fullTrustRadio, named: "Full radio button", timeout: 2)

        // Save
        let saveButton = app.buttons["Save Trust Level"]
        clickWhenReady(saveButton, named: "Save Trust Level button")

        // Close success view
        let doneButton = app.buttons["Done"]
        clickWhenReady(doneButton, named: "Done button")
        XCTAssertTrue(app.buttons["Set Trust Level"].waitForExistence(timeout: 3))

        // Verify trust level badge is visible in key details
        XCTAssertTrue(app.descendants(matching: .any)["Trust Level Badge Full"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testMultipleTrustLevelChanges() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)

        // First change: Unknown -> Marginal
        openTrustLevelPicker(app)
        clickWhenReady(app.radioButtons["Marginal"], named: "Marginal radio button")
        clickWhenReady(app.buttons["Save Trust Level"], named: "Save Trust Level button")
        clickWhenReady(app.buttons["Done"], named: "Done button")

        // Second change: Marginal -> Full
        openTrustLevelPicker(app)
        clickWhenReady(app.radioButtons["Full"], named: "Full radio button")
        clickWhenReady(app.buttons["Save Trust Level"], named: "Save Trust Level button")
        clickWhenReady(app.buttons["Done"], named: "Done button")

        // Third change: Full -> Never
        openTrustLevelPicker(app)
        clickWhenReady(app.radioButtons["Never"], named: "Never radio button")
        clickWhenReady(app.buttons["Save Trust Level"], named: "Save Trust Level button")
        clickWhenReady(app.buttons["Done"], named: "Done button")

        // Verify final state
        openTrustLevelPicker(app)
        let neverTrustRadio = app.radioButtons["Never"]
        XCTAssertTrue(neverTrustRadio.waitForExistence(timeout: 2))
        XCTAssertEqual(neverTrustRadio.value as? Int, 1)
    }

    @MainActor
    func testTrustLevelDescriptionUpdates() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)
        openTrustLevelPicker(app)

        // Verify description section exists
        XCTAssertTrue(app.staticTexts["What This Means"].waitForExistence(timeout: 2))

        // Select Never and verify description updates
        clickWhenReady(app.radioButtons["Never"], named: "Never radio button")
        XCTAssertTrue(
            app.staticTexts[
                AccessibilityIdentifiers.TrustLevelPicker.description(token: "Never")
            ].waitForExistence(timeout: 2)
        )

        // Select Full and verify description updates
        clickWhenReady(app.radioButtons["Full"], named: "Full radio button")
        XCTAssertTrue(
            app.staticTexts[
                AccessibilityIdentifiers.TrustLevelPicker.description(token: "Full")
            ].waitForExistence(timeout: 2)
        )
        // Full trust should show "Can certify other keys" indicator
        XCTAssertTrue(
            app.staticTexts[
                AccessibilityIdentifiers.TrustLevelPicker.canCertifyDescription(token: "Full")
            ].waitForExistence(timeout: 2)
        )

        // Select Marginal
        clickWhenReady(app.radioButtons["Marginal"], named: "Marginal radio button")
        XCTAssertTrue(
            app.staticTexts[
                AccessibilityIdentifiers.TrustLevelPicker.description(token: "Marginal")
            ].waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testOpenTrustPickerFromTrustBadge() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)

        // First set a trust level so the badge appears
        openTrustLevelPicker(app)
        clickWhenReady(app.radioButtons["Full"], named: "Full radio button")
        clickWhenReady(app.buttons["Save Trust Level"], named: "Save Trust Level button")
        clickWhenReady(app.buttons["Done"], named: "Done button")
        XCTAssertTrue(app.buttons["Set Trust Level"].waitForExistence(timeout: 3))

        // Now try to open trust picker by clicking on the trust badge in key details
        let trustBadge = app.descendants(matching: .any)["Trust Level Badge Full"]
        clickWhenReady(trustBadge, named: "Trust Level Badge Full", timeout: 2)
        XCTAssertTrue(app.staticTexts["Set Trust Level"].waitForExistence(timeout: 2))
    }
}
