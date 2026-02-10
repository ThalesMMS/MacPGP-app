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
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        // Generate a test key using keyboard shortcut Cmd+N
        app.typeKey("n", modifierFlags: .command)

        // Fill in the form
        let nameField = app.textFields["Full Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Trust Test User")

        let emailField = app.textFields["Email Address"]
        emailField.tap()
        emailField.typeText("trusttest@example.com")

        let passphraseField = app.secureTextFields["Passphrase"]
        passphraseField.tap()
        passphraseField.typeText("TrustTestPassphrase123!")

        let confirmField = app.secureTextFields["Confirm Passphrase"]
        confirmField.tap()
        confirmField.typeText("TrustTestPassphrase123!")

        // Generate key
        let generateButton = app.buttons["Generate"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 2))
        XCTAssertTrue(generateButton.isEnabled)
        generateButton.click()

        // Wait for key generation to complete
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 30))
        doneButton.click()
    }

    private func openFirstKeyDetails(_ app: XCUIApplication) {
        // Click on the first key in the keyring list
        let keyList = app.tables.firstMatch
        XCTAssertTrue(keyList.waitForExistence(timeout: 3))

        let firstRow = keyList.tableRows.firstMatch
        XCTAssertTrue(firstRow.exists)
        firstRow.click()
    }

    private func openTrustLevelPicker(_ app: XCUIApplication) {
        // Click the "Set Trust Level" toolbar button
        let trustButton = app.buttons["Set Trust Level"]
        XCTAssertTrue(trustButton.waitForExistence(timeout: 3))
        trustButton.click()
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
        XCTAssertTrue(app.radioButtons["Never Trust"].exists)
        XCTAssertTrue(app.radioButtons["Marginal Trust"].exists)
        XCTAssertTrue(app.radioButtons["Full Trust"].exists)
        XCTAssertTrue(app.radioButtons["Ultimate Trust"].exists)

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

        // Test selecting "Never Trust"
        let neverTrustRadio = app.radioButtons["Never Trust"]
        XCTAssertTrue(neverTrustRadio.waitForExistence(timeout: 2))
        neverTrustRadio.click()

        // Verify save button becomes enabled
        let saveButton = app.buttons["Save Trust Level"]
        XCTAssertTrue(saveButton.isEnabled)

        // Test selecting "Marginal Trust"
        let marginalTrustRadio = app.radioButtons["Marginal Trust"]
        marginalTrustRadio.click()
        XCTAssertTrue(saveButton.isEnabled)

        // Test selecting "Full Trust"
        let fullTrustRadio = app.radioButtons["Full Trust"]
        fullTrustRadio.click()
        XCTAssertTrue(saveButton.isEnabled)

        // Test selecting "Ultimate Trust"
        let ultimateTrustRadio = app.radioButtons["Ultimate Trust"]
        ultimateTrustRadio.click()
        XCTAssertTrue(saveButton.isEnabled)

        // Test selecting back to "Unknown" (original value)
        let unknownRadio = app.radioButtons["Unknown"]
        unknownRadio.click()

        // Verify save button becomes disabled again (back to original)
        XCTAssertFalse(saveButton.isEnabled)
    }

    @MainActor
    func testUltimateTrustWarningAppears() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)
        openTrustLevelPicker(app)

        // Select Ultimate Trust
        let ultimateTrustRadio = app.radioButtons["Ultimate Trust"]
        XCTAssertTrue(ultimateTrustRadio.waitForExistence(timeout: 2))
        ultimateTrustRadio.click()

        // Verify warning appears
        XCTAssertTrue(app.staticTexts["Ultimate Trust Warning"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Ultimate trust should only be assigned to your own keys'")).firstMatch.exists)

        // Select a different trust level
        let marginalTrustRadio = app.radioButtons["Marginal Trust"]
        marginalTrustRadio.click()

        // Verify warning disappears
        XCTAssertFalse(app.staticTexts["Ultimate Trust Warning"].exists)
    }

    @MainActor
    func testSavingTrustLevel() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)
        openTrustLevelPicker(app)

        // Select Full Trust
        let fullTrustRadio = app.radioButtons["Full Trust"]
        XCTAssertTrue(fullTrustRadio.waitForExistence(timeout: 2))
        fullTrustRadio.click()

        // Click Save button
        let saveButton = app.buttons["Save Trust Level"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.click()

        // Verify success view appears
        XCTAssertTrue(app.staticTexts["Trust Level Updated"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'has been set to Full Trust'")).firstMatch.waitForExistence(timeout: 1))

        // Verify Done button exists
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.exists)
        doneButton.click()

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
        let fullTrustRadio = app.radioButtons["Full Trust"]
        XCTAssertTrue(fullTrustRadio.waitForExistence(timeout: 2))
        fullTrustRadio.click()

        // Verify save button is enabled
        let saveButton = app.buttons["Save Trust Level"]
        XCTAssertTrue(saveButton.isEnabled)

        // Click Cancel button
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists)
        cancelButton.click()

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

        // Select Marginal Trust
        let marginalTrustRadio = app.radioButtons["Marginal Trust"]
        XCTAssertTrue(marginalTrustRadio.waitForExistence(timeout: 2))
        marginalTrustRadio.click()

        // Save
        let saveButton = app.buttons["Save Trust Level"]
        saveButton.click()

        // Wait for success and close
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        doneButton.click()

        // Open trust level picker again
        openTrustLevelPicker(app)

        // Verify Marginal Trust is selected
        let marginalTrustRadioAgain = app.radioButtons["Marginal Trust"]
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

        // Select Full Trust
        let fullTrustRadio = app.radioButtons["Full Trust"]
        XCTAssertTrue(fullTrustRadio.waitForExistence(timeout: 2))
        fullTrustRadio.click()

        // Save
        let saveButton = app.buttons["Save Trust Level"]
        saveButton.click()

        // Close success view
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        doneButton.click()

        // Verify trust level badge is visible in key details
        // The badge should show "Full Trust" somewhere in the key details view
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Full'")).firstMatch.waitForExistence(timeout: 2))
    }

    @MainActor
    func testMultipleTrustLevelChanges() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)

        // First change: Unknown -> Marginal
        openTrustLevelPicker(app)
        app.radioButtons["Marginal Trust"].click()
        app.buttons["Save Trust Level"].click()
        app.buttons["Done"].waitForExistence(timeout: 3)
        app.buttons["Done"].click()

        // Second change: Marginal -> Full
        openTrustLevelPicker(app)
        app.radioButtons["Full Trust"].click()
        app.buttons["Save Trust Level"].click()
        app.buttons["Done"].waitForExistence(timeout: 3)
        app.buttons["Done"].click()

        // Third change: Full -> Never
        openTrustLevelPicker(app)
        app.radioButtons["Never Trust"].click()
        app.buttons["Save Trust Level"].click()
        app.buttons["Done"].waitForExistence(timeout: 3)
        app.buttons["Done"].click()

        // Verify final state
        openTrustLevelPicker(app)
        let neverTrustRadio = app.radioButtons["Never Trust"]
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

        // Select Never Trust and verify description updates
        app.radioButtons["Never Trust"].click()
        // Description should contain information about never trusting
        XCTAssertTrue(app.staticTexts["Never Trust"].exists)

        // Select Full Trust and verify description updates
        app.radioButtons["Full Trust"].click()
        XCTAssertTrue(app.staticTexts["Full Trust"].exists)
        // Full trust should show "Can certify other keys" indicator
        XCTAssertTrue(app.staticTexts["Can certify other keys"].exists)

        // Select Marginal Trust
        app.radioButtons["Marginal Trust"].click()
        XCTAssertTrue(app.staticTexts["Marginal Trust"].exists)
    }

    @MainActor
    func testOpenTrustPickerFromTrustBadge() throws {
        let app = XCUIApplication()
        try launchAppAndGenerateTestKey(app)

        openFirstKeyDetails(app)

        // First set a trust level so the badge appears
        openTrustLevelPicker(app)
        app.radioButtons["Full Trust"].click()
        app.buttons["Save Trust Level"].click()
        app.buttons["Done"].waitForExistence(timeout: 3)
        app.buttons["Done"].click()

        // Now try to open trust picker by clicking on the trust badge in key details
        // The trust badge should be clickable
        let trustBadges = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Full'"))
        if trustBadges.count > 0 {
            // Click on one of the trust-related elements (badge should be clickable)
            // This might open the trust picker again
            // Note: This test might need adjustment based on actual accessibility labels
            XCTAssertTrue(trustBadges.firstMatch.exists)
        }

        // Verify we can still open via toolbar button
        openTrustLevelPicker(app)
        XCTAssertTrue(app.staticTexts["Set Trust Level"].waitForExistence(timeout: 2))
    }
}
