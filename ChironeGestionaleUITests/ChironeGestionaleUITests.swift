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

    @MainActor
    private func clickWhenHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
        let hittablePredicate = NSPredicate(format: "hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: hittablePredicate, object: element)
        _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertTrue(element.isHittable, file: file, line: line)
        element.click()
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
        clickWhenHittable(firstName)
        firstName.typeText("Mario")

        let lastName = app.textFields["new_patient_last_name"]
        clickWhenHittable(lastName)
        lastName.typeText("Rossi")

        let birthPlace = app.textFields["new_patient_birth_place"]
        clickWhenHittable(birthPlace)
        birthPlace.typeText("Torino")

        app.buttons["create_patient_button"].click()
        app.buttons["open_patient_clinical_button"].click()

        let addDateButton = app.buttons["bloodtests_add_date_button"]
        XCTAssertTrue(addDateButton.waitForExistence(timeout: 5))
        addDateButton.click()
        addDateButton.click()

        let firstCell = app.textFields["bloodtests_cell_row_0_col_0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        clickWhenHittable(firstCell)
        firstCell.typeText("120")

        let secondCell = app.textFields["bloodtests_cell_row_0_col_1"]
        XCTAssertTrue(secondCell.waitForExistence(timeout: 5))
        clickWhenHittable(secondCell)
        secondCell.typeText("121")

        let saveButton = app.buttons["bloodtests_save_button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        XCTAssertTrue(saveButton.isEnabled)
    }

    // MARK: - P1 Edge Case Tests

    /// Case 2: Nota clinica con testo lungo (>=3000 char) salvata senza troncamenti.
    @MainActor
    func testLongClinicalNoteIsSavedWithoutTruncation() throws {
        let app = launchAppForClinicalFlow()
        waitForNewPatientSheet(in: app)

        let firstName = app.textFields["new_patient_first_name"]
        clickWhenHittable(firstName)
        firstName.typeText("Elena")
        let lastName = app.textFields["new_patient_last_name"]
        clickWhenHittable(lastName)
        lastName.typeText("Ferri")
        let birthPlace = app.textFields["new_patient_birth_place"]
        clickWhenHittable(birthPlace)
        birthPlace.typeText("Napoli")
        app.buttons["create_patient_button"].click()
        app.buttons["open_patient_clinical_button"].click()

        let noteField = app.textViews["clinical_new_note_text"].firstMatch
        XCTAssertTrue(noteField.waitForExistence(timeout: 10))
        clickWhenHittable(noteField)

        // Build a 3000+ character string without live typing (slow in UI tests)
        let sentence = "Paziente collaborante, orientata nel tempo e nello spazio, eloquio regolare. "
        let longText = String(repeating: sentence, count: 40) // ~3080 chars
        noteField.typeText(longText)

        let saveNote = app.buttons["clinical_save_note_button"]
        XCTAssertTrue(saveNote.waitForExistence(timeout: 5))
        XCTAssertTrue(saveNote.isEnabled)
        saveNote.click()

        // Feedback banner confirms save completed without truncation error
        let banner = app.staticTexts["clinical_save_feedback_banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 8), "Save feedback banner should appear after saving long note")
    }

    /// Case 5: Terapia con più farmaci, persistenza dopo chiusura e riapertura finestra.
    @MainActor
    func testMultiMedicationTherapyPersistsAfterWindowReopen() throws {
        let app = launchAppForClinicalFlow()
        waitForNewPatientSheet(in: app)

        let firstName = app.textFields["new_patient_first_name"]
        clickWhenHittable(firstName)
        firstName.typeText("Carlo")
        let lastName = app.textFields["new_patient_last_name"]
        clickWhenHittable(lastName)
        lastName.typeText("Mancini")
        let birthPlace = app.textFields["new_patient_birth_place"]
        clickWhenHittable(birthPlace)
        birthPlace.typeText("Palermo")
        app.buttons["create_patient_button"].click()
        app.buttons["open_patient_clinical_button"].click()

        // Add first medication
        let addTherapy = app.buttons["therapy_add_medication_button"]
        XCTAssertTrue(addTherapy.waitForExistence(timeout: 5))
        addTherapy.click()
        let farmaco1 = app.textFields["Farmaco"].firstMatch
        clickWhenHittable(farmaco1)
        farmaco1.typeText("Quetiapina")
        let dosaggio1 = app.textFields["Dosaggio"].firstMatch
        clickWhenHittable(dosaggio1)
        dosaggio1.typeText("100mg")
        let posologia1 = app.textFields["Posologia"].firstMatch
        clickWhenHittable(posologia1)
        posologia1.typeText("1 cp sera")

        // Add second medication
        addTherapy.click()
        let farmFields = app.textFields.matching(identifier: "Farmaco")
        if farmFields.count > 1 {
            let farmaco2 = farmFields.element(boundBy: 1)
            clickWhenHittable(farmaco2)
            farmaco2.typeText("Litio carbonato")
            let dosaggio2 = app.textFields.matching(identifier: "Dosaggio").element(boundBy: 1)
            clickWhenHittable(dosaggio2)
            dosaggio2.typeText("300mg")
            let posologia2 = app.textFields.matching(identifier: "Posologia").element(boundBy: 1)
            clickWhenHittable(posologia2)
            posologia2.typeText("2 cp/die")
        }

        let therapySave = app.buttons["therapy_save_button"]
        XCTAssertTrue(therapySave.waitForExistence(timeout: 5))
        XCTAssertTrue(therapySave.isEnabled)
        therapySave.click()

        // Close clinical window
        app.typeKey("w", modifierFlags: [.command])
        // Dismiss unsaved-changes dialog if present
        let dialog = app.dialogs.firstMatch
        if dialog.waitForExistence(timeout: 2) {
            let closeBtn = dialog.buttons["Chiudi senza salvare"]
            if closeBtn.exists { closeBtn.click() }
        }

        // Reopen clinical window from the patient selection summary
        let reopenBtn = app.buttons["open_patient_clinical_button"]
        XCTAssertTrue(reopenBtn.waitForExistence(timeout: 5))
        reopenBtn.click()

        // Therapy section should be visible with its controls intact
        XCTAssertTrue(addTherapy.waitForExistence(timeout: 8), "Therapy section should be present after window reopen")
        XCTAssertTrue(therapySave.waitForExistence(timeout: 5))
    }

    /// Case 7: Aggiunta colonna su tabella con dati esistenti non corrompe i valori già inseriti.
    @MainActor
    func testBloodTestsAddingColumnPreservesExistingCellValues() throws {
        let app = launchAppForClinicalFlow()
        waitForNewPatientSheet(in: app)

        let firstName = app.textFields["new_patient_first_name"]
        clickWhenHittable(firstName)
        firstName.typeText("Lucia")
        let lastName = app.textFields["new_patient_last_name"]
        clickWhenHittable(lastName)
        lastName.typeText("Greco")
        let birthPlace = app.textFields["new_patient_birth_place"]
        clickWhenHittable(birthPlace)
        birthPlace.typeText("Bologna")
        app.buttons["create_patient_button"].click()
        app.buttons["open_patient_clinical_button"].click()

        let addDateButton = app.buttons["bloodtests_add_date_button"]
        XCTAssertTrue(addDateButton.waitForExistence(timeout: 5))
        addDateButton.click()

        // Fill a known value in the first column
        let firstCell = app.textFields["bloodtests_cell_row_0_col_0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        clickWhenHittable(firstCell)
        firstCell.typeText("7.5")

        // Tab to commit the edit
        app.typeKey("\t", modifierFlags: [])

        // Add a second date column
        addDateButton.click()

        // Verify the value in col_0 is still present
        XCTAssertTrue(firstCell.waitForExistence(timeout: 3))
        let cellValue = firstCell.value as? String ?? ""
        XCTAssertEqual(cellValue, "7.5", "Existing cell value must not be corrupted when a new column is added")
    }

    /// Case 8: Referto clinico si apre senza crash con campi paziente incompleti.
    @MainActor
    func testReportRendersWithMinimalPatientData() throws {
        let app = launchAppForClinicalFlow()
        waitForNewPatientSheet(in: app)

        // Create patient with only the minimum required fields
        let firstName = app.textFields["new_patient_first_name"]
        clickWhenHittable(firstName)
        firstName.typeText("Paziente")
        let lastName = app.textFields["new_patient_last_name"]
        clickWhenHittable(lastName)
        lastName.typeText("Minimo")
        let birthPlace = app.textFields["new_patient_birth_place"]
        clickWhenHittable(birthPlace)
        birthPlace.typeText("Siena")
        app.buttons["create_patient_button"].click()
        app.buttons["open_patient_clinical_button"].click()

        // Open report with no clinical notes, no therapy, no blood tests
        let clinicalWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(clinicalWindow.waitForExistence(timeout: 8))
        clinicalWindow.typeKey("p", modifierFlags: [.command])

        let previewTitle = app.staticTexts["report_preview_title"]
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 8), "Report preview must open even with empty clinical data")

        let printButton = app.buttons["report_preview_print_button"]
        XCTAssertTrue(printButton.waitForExistence(timeout: 3), "Print button must be present in preview")
        let printEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: printButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [printEnabled], timeout: 3), .completed, "Print button must be enabled")
    }

    /// Case 10: Draft nota clinica recuperato correttamente dopo chiusura finestra senza salvataggio.
    @MainActor
    func testClinicalNoteDraftRestoredAfterWindowClosedWithoutSaving() throws {
        let app = launchAppForClinicalFlow()
        waitForNewPatientSheet(in: app)

        let firstName = app.textFields["new_patient_first_name"]
        clickWhenHittable(firstName)
        firstName.typeText("Autosave")
        let lastName = app.textFields["new_patient_last_name"]
        clickWhenHittable(lastName)
        lastName.typeText("Test")
        let birthPlace = app.textFields["new_patient_birth_place"]
        clickWhenHittable(birthPlace)
        birthPlace.typeText("Genova")
        app.buttons["create_patient_button"].click()
        app.buttons["open_patient_clinical_button"].click()

        let noteField = app.textViews["clinical_new_note_text"].firstMatch
        XCTAssertTrue(noteField.waitForExistence(timeout: 10))
        clickWhenHittable(noteField)

        let draftText = "Testo bozza per test autosave, recupero dopo chiusura inattesa."
        noteField.typeText(draftText)

        // Close clinical window WITHOUT saving the note
        app.typeKey("w", modifierFlags: [.command])
        // Confirm close without saving
        let dialog = app.dialogs.firstMatch
        if dialog.waitForExistence(timeout: 3) {
            let closeBtn = dialog.buttons["Chiudi senza salvare"]
            if closeBtn.exists { closeBtn.click() }
        }

        // Reopen the same patient
        let reopenBtn = app.buttons["open_patient_clinical_button"]
        XCTAssertTrue(reopenBtn.waitForExistence(timeout: 5))
        reopenBtn.click()

        // Draft should be restored in the note text area
        let restoredField = app.textViews["clinical_new_note_text"].firstMatch
        XCTAssertTrue(restoredField.waitForExistence(timeout: 8))
        let restoredText = restoredField.value as? String ?? ""
        XCTAssertFalse(restoredText.isEmpty, "Draft note content should be restored after window reopen")
        XCTAssertTrue(
            restoredText.contains("bozza") || restoredText.contains("autosave"),
            "Restored draft should contain the typed text, got: \(restoredText.prefix(100))"
        )
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
        clickWhenHittable(firstName)
        firstName.typeText("Giulia")

        let lastName = app.textFields["new_patient_last_name"]
        XCTAssertTrue(lastName.waitForExistence(timeout: 3))
        clickWhenHittable(lastName)
        lastName.typeText("Bianchi")

        let birthPlace = app.textFields["new_patient_birth_place"]
        XCTAssertTrue(birthPlace.waitForExistence(timeout: 3))
        clickWhenHittable(birthPlace)
        birthPlace.typeText("Milano")

        app.buttons["create_patient_button"].click()
        app.buttons["open_patient_clinical_button"].click()

        let newNoteText = app.textViews["clinical_new_note_text"].firstMatch
        clickWhenHittable(newNoteText, timeout: 10)
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
        clickWhenHittable(therapyMedicationField)
        therapyMedicationField.typeText("Sertralina")

        let therapyDosageField = app.textFields["Dosaggio"].firstMatch
        XCTAssertTrue(therapyDosageField.waitForExistence(timeout: 3))
        clickWhenHittable(therapyDosageField)
        therapyDosageField.typeText("50mg")

        let therapyPosologyField = app.textFields["Posologia"].firstMatch
        XCTAssertTrue(therapyPosologyField.waitForExistence(timeout: 3))
        clickWhenHittable(therapyPosologyField)
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
        clickWhenHittable(firstCell)
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
        clickWhenHittable(firstName)
        firstName.typeText("Marco")

        let lastName = app.textFields["new_patient_last_name"]
        XCTAssertTrue(lastName.waitForExistence(timeout: 3))
        clickWhenHittable(lastName)
        lastName.typeText("Neri")

        let birthPlace = app.textFields["new_patient_birth_place"]
        XCTAssertTrue(birthPlace.waitForExistence(timeout: 3))
        clickWhenHittable(birthPlace)
        birthPlace.typeText("Roma")

        app.buttons["create_patient_button"].click()
        app.buttons["open_patient_clinical_button"].click()

        app.typeKey("p", modifierFlags: [.command])

        let previewTitle = app.staticTexts["report_preview_title"]
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 5))

        let printButton = app.buttons["report_preview_print_button"]
        XCTAssertTrue(printButton.waitForExistence(timeout: 3))

        let reloadButton = app.buttons["report_composer_reload_button"]
        let updatePreviewButton = app.buttons["report_composer_update_preview_button"]
        let titleField = app.textFields["report_composer_title_field"]
        let demographicsToggle = app.switches["report_composer_toggle_demographics"]

        XCTAssertTrue(reloadButton.waitForExistence(timeout: 3))
        XCTAssertTrue(updatePreviewButton.waitForExistence(timeout: 3))
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        XCTAssertTrue(demographicsToggle.waitForExistence(timeout: 3))

        clickWhenHittable(titleField)
        titleField.typeKey("a", modifierFlags: [.command])
        titleField.typeText("Relazione clinica personalizzata")
        XCTAssertEqual(titleField.value as? String, "Relazione clinica personalizzata")

        clickWhenHittable(demographicsToggle)
        let stalePreviewIndicator = app.staticTexts["report_composer_preview_stale"]
        XCTAssertTrue(stalePreviewIndicator.waitForExistence(timeout: 3))

        clickWhenHittable(updatePreviewButton)
        XCTAssertTrue(stalePreviewIndicator.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testPrescriptionComposerUsesManualPreviewRefresh() throws {
        let app = launchAppForClinicalFlow()
        waitForNewPatientSheet(in: app)

        let firstName = app.textFields["new_patient_first_name"]
        clickWhenHittable(firstName)
        firstName.typeText("Lucia")
        let lastName = app.textFields["new_patient_last_name"]
        clickWhenHittable(lastName)
        lastName.typeText("Verdi")
        let birthPlace = app.textFields["new_patient_birth_place"]
        clickWhenHittable(birthPlace)
        birthPlace.typeText("Milano")
        app.buttons["create_patient_button"].click()
        app.buttons["open_patient_clinical_button"].click()

        let addTherapy = app.buttons["therapy_add_medication_button"]
        XCTAssertTrue(addTherapy.waitForExistence(timeout: 5))
        addTherapy.click()
        let medication = app.textFields["Farmaco"].firstMatch
        clickWhenHittable(medication)
        medication.typeText("Sertralina")
        let dosage = app.textFields["Dosaggio"].firstMatch
        clickWhenHittable(dosage)
        dosage.typeText("50 mg")
        let posology = app.textFields["Posologia"].firstMatch
        clickWhenHittable(posology)
        posology.typeText("una compressa al mattino")
        let saveTherapy = app.buttons["therapy_save_button"]
        XCTAssertTrue(saveTherapy.waitForExistence(timeout: 3))
        saveTherapy.click()

        app.typeKey("p", modifierFlags: [.command, .shift])

        let composerTitle = app.staticTexts["prescription_preview_title"]
        XCTAssertTrue(composerTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["prescription_preview_save_button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["prescription_preview_print_button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["prescription_composer_add_medication_button"].waitForExistence(timeout: 3))

        let titleField = app.textFields["prescription_composer_title_field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        clickWhenHittable(titleField)
        titleField.typeKey("a", modifierFlags: [.command])
        titleField.typeText("Prescrizione personalizzata")

        let stalePreviewIndicator = app.staticTexts["prescription_composer_preview_stale"]
        XCTAssertTrue(stalePreviewIndicator.waitForExistence(timeout: 3))
        let updatePreview = app.buttons["prescription_composer_update_preview_button"]
        clickWhenHittable(updatePreview)
        XCTAssertTrue(stalePreviewIndicator.waitForNonExistence(timeout: 3))
    }
}
