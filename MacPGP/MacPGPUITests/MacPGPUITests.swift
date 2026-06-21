//
//  MacPGPUITests.swift
//  MacPGPUITests
//
//  Created by Thales Matheus Mendonça Santos on 04/02/26.
//

import XCTest

final class MacPGPUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsPrimaryNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.buttons["Keyring"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Encrypt"].exists)
        XCTAssertTrue(app.buttons["Decrypt"].exists)
        XCTAssertTrue(app.buttons["Sign"].exists)
        XCTAssertTrue(app.buttons["Verify"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
