//
//  ChironeGestionaleUITests.swift
//  ChironeGestionaleUITests
//
//  Created by Peste on 21/04/2026.
//

import XCTest

final class ChironeGestionaleUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testBloodTestsCellToCellEditingEnablesSave() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITEST_DISABLE_LOCK")
        app.launch()

        app.buttons["new_patient_button"].click()

        let firstName = app.textFields["new_patient_first_name"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 3))
        firstName.click()
        firstName.typeText("Mario")

        let lastName = app.textFields["new_patient_last_name"]
        lastName.click()
        lastName.typeText("Rossi")

        let birthPlace = app.textFields["new_patient_birth_place"]
        birthPlace.click()
        birthPlace.typeText("Torino")

        app.buttons["create_patient_button"].click()
        app.buttons["open_patient_clinical_button"].click()

        let addDateButton = app.buttons["bloodtests_add_date_button"]
        XCTAssertTrue(addDateButton.waitForExistence(timeout: 5))
        addDateButton.click()
        addDateButton.click()

        let firstCell = app.textFields["bloodtests_cell_row_0_col_0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        firstCell.click()
        firstCell.typeText("120")

        let secondCell = app.textFields["bloodtests_cell_row_0_col_1"]
        XCTAssertTrue(secondCell.waitForExistence(timeout: 5))
        secondCell.click()
        secondCell.typeText("121")

        let saveButton = app.buttons["bloodtests_save_button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        XCTAssertTrue(saveButton.isEnabled)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
