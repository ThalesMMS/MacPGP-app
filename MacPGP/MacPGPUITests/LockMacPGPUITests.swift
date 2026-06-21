//
//  LockMacPGPUITests.swift
//  MacPGPUITests
//
//  UI coverage for issue #128: the Lock MacPGP command and Settings action exist
//  and are invokable. The behavioral guarantee that locking forces the next
//  protected operation to prompt again is enforced and unit-tested in
//  PassphraseCacheTests / SessionLockControllerTests (lock clears the in-memory
//  cache, so the next passphrase lookup misses and the workflow prompts).
//

import XCTest

final class LockMacPGPUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testLockNowButtonInSecuritySettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-keyring"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        app.typeKey(",", modifierFlags: .command)
        let security = app.buttons["Security"].exists ? app.buttons["Security"] : app.buttons["settings.tab.security"]
        XCTAssertTrue(security.waitForExistence(timeout: 5))
        security.tap()

        let lockButton = app.buttons["Lock MacPGP Now"]
        XCTAssertTrue(lockButton.waitForExistence(timeout: 5))
        lockButton.tap()

        // Locking must keep the app responsive (no crash).
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
    }

    @MainActor
    func testLockMacPGPMenuCommandExists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-keyring"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        // The application menu (index 1, after the Apple menu) exposes Lock MacPGP.
        let appMenu = app.menuBarItems.element(boundBy: 1)
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()

        let lockItem = app.menuItems["Lock MacPGP"]
        XCTAssertTrue(lockItem.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
    }
}
