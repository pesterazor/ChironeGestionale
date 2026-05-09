//
//  ChironeGestionaleUITests.swift
//  ChironeGestionaleUITests
//
//  Created by Peste on 21/04/2026.
//

import XCTest

final class ChironeGestionaleUITests: XCTestCase {
    @MainActor
    private func launchAppForClinicalFlow() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-UITEST_DISABLE_LOCK")
        app.launchArguments.append("-UITEST_AUTO_OPEN_NEW_PATIENT")
        app.launchArguments.append("-UITEST_DISABLE_WINDOW_RESTORE")
        app.launch()
        return app
    }

    @MainActor
    private func waitForNewPatientSheet(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let firstName = app.textFields["new_patient_first_name"]
        if firstName.waitForExistence(timeout: 8) {
            return
        }

        let newPatientButton = app.buttons["new_patient_button"]
        if newPatientButton.waitForExistence(timeout: 2) {
            newPatientButton.click()
        } else {
            app.typeKey("n", modifierFlags: [.command])
        }

        XCTAssertTrue(firstName.waitForExistence(timeout: 8), file: file, line: line)
    }

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
        let app = launchAppForClinicalFlow()
        waitForNewPatientSheet(in: app)

        let firstName = app.textFields["new_patient_first_name"]
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

    @MainActor
    func testCompleteVisitFlowCoreSections() throws {
        let app = launchAppForClinicalFlow()
        waitForNewPatientSheet(in: app)

        let firstName = app.textFields["new_patient_first_name"]
        firstName.click()
        firstName.typeText("Giulia")

        let lastName = app.textFields["new_patient_last_name"]
        XCTAssertTrue(lastName.waitForExistence(timeout: 3))
        lastName.click()
        lastName.typeText("Bianchi")

        let birthPlace = app.textFields["new_patient_birth_place"]
        XCTAssertTrue(birthPlace.waitForExistence(timeout: 3))
        birthPlace.click()
        birthPlace.typeText("Milano")

        app.buttons["create_patient_button"].click()
        app.buttons["open_patient_clinical_button"].click()

        let newNoteText = app.textViews["clinical_new_note_text"].firstMatch
        XCTAssertTrue(newNoteText.waitForExistence(timeout: 5))
        newNoteText.click()
        newNoteText.typeText("Paziente collaborante. Sonno migliorato rispetto al controllo precedente.")

        let saveNote = app.buttons["clinical_save_note_button"]
        XCTAssertTrue(saveNote.waitForExistence(timeout: 2))
        XCTAssertTrue(saveNote.isEnabled)
        saveNote.click()

        let addTherapy = app.buttons["therapy_add_medication_button"]
        XCTAssertTrue(addTherapy.waitForExistence(timeout: 3))
        addTherapy.click()

        let therapyMedicationField = app.textFields["Farmaco"].firstMatch
        XCTAssertTrue(therapyMedicationField.waitForExistence(timeout: 3))
        therapyMedicationField.click()
        therapyMedicationField.typeText("Sertralina")

        let therapyDosageField = app.textFields["Dosaggio"].firstMatch
        XCTAssertTrue(therapyDosageField.waitForExistence(timeout: 3))
        therapyDosageField.click()
        therapyDosageField.typeText("50mg")

        let therapyPosologyField = app.textFields["Posologia"].firstMatch
        XCTAssertTrue(therapyPosologyField.waitForExistence(timeout: 3))
        therapyPosologyField.click()
        therapyPosologyField.typeText("1 cp mattino")

        let therapySave = app.buttons["therapy_save_button"]
        XCTAssertTrue(therapySave.waitForExistence(timeout: 3))
        XCTAssertTrue(therapySave.isEnabled)
        therapySave.click()

        let addDateButton = app.buttons["bloodtests_add_date_button"]
        XCTAssertTrue(addDateButton.waitForExistence(timeout: 5))
        addDateButton.click()

        let firstCell = app.textFields["bloodtests_cell_row_0_col_0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        firstCell.click()
        firstCell.typeText("98")

        let bloodTestsSave = app.buttons["bloodtests_save_button"]
        XCTAssertTrue(bloodTestsSave.waitForExistence(timeout: 3))
        XCTAssertTrue(bloodTestsSave.isEnabled)
        bloodTestsSave.click()
    }

    @MainActor
    func testReportPreviewOpensFromActiveClinicalWindow() throws {
        let app = launchAppForClinicalFlow()
        waitForNewPatientSheet(in: app)

        let firstName = app.textFields["new_patient_first_name"]
        firstName.click()
        firstName.typeText("Marco")

        let lastName = app.textFields["new_patient_last_name"]
        XCTAssertTrue(lastName.waitForExistence(timeout: 3))
        lastName.click()
        lastName.typeText("Neri")

        let birthPlace = app.textFields["new_patient_birth_place"]
        XCTAssertTrue(birthPlace.waitForExistence(timeout: 3))
        birthPlace.click()
        birthPlace.typeText("Roma")

        app.buttons["create_patient_button"].click()
        app.buttons["open_patient_clinical_button"].click()

        app.typeKey("p", modifierFlags: [.command])

        let previewTitle = app.staticTexts["report_preview_title"]
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 5))

        let printButton = app.buttons["report_preview_print_button"]
        XCTAssertTrue(printButton.waitForExistence(timeout: 3))
    }
}
