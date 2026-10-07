import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import ChironeGestionale

@MainActor
final class ClinicalWorkflowReviewTests: XCTestCase {
    func testDraftRecoveryKeepsSmallCorrectionsWithoutPlaintextCopy() throws {
        let suite = "ClinicalWorkflowReviewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ClinicalDraftAutosaveStore(defaults: defaults)
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(store.saveDraft(patientID: id, content: "Dose: 10 mg", wellbeing: 5, noteDate: date))
        XCTAssertTrue(store.saveDraft(patientID: id, content: "Dose: 20 mg", wellbeing: 5, noteDate: date))
        XCTAssertEqual(store.loadDraft(patientID: id)?.content, "Dose: 20 mg")
        let data = try XCTUnwrap(defaults.data(forKey: "clinicalDraftAutosave.patient.\(id.uuidString)"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["encryptedContent"])
        XCTAssertNil(json["plainFallbackContent"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Dose:"))
    }

    func testFailedDraftEncryptionPreservesLastRecoverableDraft() throws {
        let suite = "ClinicalWorkflowReviewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        final class Availability { var value = true }
        let encryptionAvailable = Availability()
        let store = ClinicalDraftAutosaveStore(defaults: defaults,
            encrypt: { encryptionAvailable.value ? SecureDataCipher.shared.encrypt($0) : nil })
        let id = UUID()
        XCTAssertTrue(store.saveDraft(patientID: id, content: "Bozza precedente", wellbeing: 4, noteDate: .now))
        encryptionAvailable.value = false
        XCTAssertFalse(store.saveDraft(patientID: id, content: "Bozza nuova", wellbeing: 7, noteDate: .now))
        XCTAssertEqual(store.loadDraft(patientID: id)?.content, "Bozza precedente")
        XCTAssertEqual(store.loadDraft(patientID: id)?.wellbeing, 4)
    }

    func testLegacyPlaintextDraftIsRecoveredAndMigrated() throws {
        let suite = "ClinicalWorkflowReviewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let key = "clinicalDraftAutosave.patient.\(id.uuidString)"
        defaults.set(try JSONSerialization.data(withJSONObject: [
            "plainFallbackContent": "Nota sintetica precedente", "wellbeing": 6,
            "noteDate": "2026-01-01T12:00:00Z"
        ]), forKey: key)
        let store = ClinicalDraftAutosaveStore(defaults: defaults)
        XCTAssertEqual(store.loadDraft(patientID: id)?.content, "Nota sintetica precedente")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: key))) as? [String: Any])
        XCTAssertNil(json["plainFallbackContent"])
        XCTAssertNotNil(json["encryptedContent"])
    }

    func testFailedClinicalNoteEditRestoresOnlyOwnedFields() throws {
        enum Failure: Error { case save }
        let patient = Patient(firstName: "Test", lastName: "Originale")
        patient.updatedAt = Date(timeIntervalSince1970: 1_000)
        let note = ClinicalNote(content: "Legacy", wellbeingScore: 6,
            createdAt: Date(timeIntervalSince1970: 2_000), updatedAt: Date(timeIntervalSince1970: 3_000), patient: patient)
        let originalPatientDate = patient.updatedAt
        XCTAssertThrowsError(try ClinicalNoteEditing.save(note, content: "Nota modificata", wellbeing: 3,
            date: Date(timeIntervalSince1970: 4_000)) {
            patient.lastName = "Modifica indipendente"
            throw Failure.save
        })
        XCTAssertEqual(note.content, "Legacy")
        XCTAssertNil(note.encryptedContent)
        XCTAssertEqual(note.wellbeingScore, 6)
        XCTAssertEqual(note.createdAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(note.updatedAt, Date(timeIntervalSince1970: 3_000))
        XCTAssertEqual(patient.updatedAt, originalPatientDate)
        XCTAssertEqual(patient.lastName, "Modifica indipendente")
    }

    func testSuccessfulClinicalNoteEditPersistsProtectedContent() throws {
        let patient = Patient(firstName: "Test", lastName: "Note")
        let originalDate = Date(timeIntervalSince1970: 2_000)
        let note = ClinicalNote(content: "Legacy", wellbeingScore: 6, createdAt: originalDate, patient: patient)
        var saveCalls = 0
        try ClinicalNoteEditing.save(note, content: "  Nuova nota  ", wellbeing: 8, date: nil) { saveCalls += 1 }
        XCTAssertEqual(saveCalls, 1)
        XCTAssertEqual(note.readableContent, "Nuova nota")
        XCTAssertEqual(note.content, "")
        XCTAssertNotNil(note.encryptedContent)
        XCTAssertEqual(note.wellbeingScore, 8)
        XCTAssertEqual(note.createdAt, originalDate)
    }

    func testBloodTableCommitsLastEditedCellSynchronously() throws {
        let column = BloodTestColumnRecord(id: UUID(), dateText: "06/10/2026")
        let row = BloodTestRowRecord(id: UUID(), testName: "Test", values: [column.id.uuidString: "10"])
        var committedValue: String?
        let table = makeTable(rows: [row], columns: [column]) { _, _, value in committedValue = value }
        let coordinator = table.makeCoordinator()
        let container = BloodTestsSplitContainerView()
        coordinator.attach(container: container)
        coordinator.reloadStructureIfNeeded()
        coordinator.refreshIfNeeded(force: true)
        let cell = try XCTUnwrap(coordinator.tableView(container.rightTable,
            viewFor: container.rightTable.tableColumns[0], row: 0) as? NSTableCellView)
        let field = try XCTUnwrap(cell.textField)
        coordinator.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: field))
        field.stringValue = "20"
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        XCTAssertEqual(committedValue, "20", "The next Save action must already see the last cell value")
    }

    func testBloodTableAppliesDeferredRowsAndColumnsAfterEditing() async throws {
        let firstColumn = BloodTestColumnRecord(id: UUID(), dateText: "06/10/2026")
        let row = BloodTestRowRecord(id: UUID(), testName: "Test", values: [:])
        let table = makeTable(rows: [row], columns: [firstColumn])
        let coordinator = table.makeCoordinator()
        let container = BloodTestsSplitContainerView()
        coordinator.attach(container: container)
        coordinator.reloadStructureIfNeeded()
        coordinator.refreshIfNeeded(force: true)
        let cell = try XCTUnwrap(coordinator.tableView(container.rightTable,
            viewFor: container.rightTable.tableColumns[0], row: 0) as? NSTableCellView)
        let field = try XCTUnwrap(cell.textField)
        coordinator.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: field))
        let extraRow = BloodTestRowRecord(id: UUID(), testName: "Test 2", values: [:])
        let extraColumn = BloodTestColumnRecord(id: UUID(), dateText: "07/10/2026")
        coordinator.parent = makeTable(rows: [row, extraRow], columns: [firstColumn, extraColumn])
        coordinator.reloadStructureIfNeeded()
        coordinator.refreshIfNeeded(force: false)
        XCTAssertEqual(container.rightTable.numberOfColumns, 1)
        XCTAssertEqual(container.rightTable.numberOfRows, 1)
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(container.rightTable.numberOfColumns, 2)
        XCTAssertEqual(container.rightTable.numberOfRows, 2)
    }

    func testFailedBloodTestSaveRestoresJSONAndRemovesOnlyNewAutomaticNote() throws {
        enum Failure: Error { case save }
        let schema = Schema([Patient.self, ClinicalNote.self, TherapyMedication.self,
            PHQ9Assessment.self, GAD7Assessment.self, MDQAssessment.self, BeckAssessment.self, MADRSAssessment.self])
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let patient = Patient(firstName: "Test", lastName: "Esami")
        context.insert(patient)
        let existing = ClinicalNote(content: "Nota preesistente", patient: patient)
        context.insert(existing)
        patient.bloodTestsTableJSON = "originale"
        let originalDate = patient.updatedAt
        try context.save()
        let column = BloodTestColumnRecord(id: UUID(), dateText: "06/10/2026")
        let payload = BloodTestsTablePayload(columns: [column], rows: [
            BloodTestRowRecord(id: UUID(), testName: "TSH", values: [column.id.uuidString: "2.5"])
        ])
        XCTAssertThrowsError(try BloodTestsPersistence.save(payload, replacing: .empty, for: patient, in: context) {
            patient.firstName = "Modifica indipendente"
            throw Failure.save
        })
        XCTAssertEqual(patient.bloodTestsTableJSON, "originale")
        XCTAssertEqual(patient.updatedAt, originalDate)
        XCTAssertEqual(patient.firstName, "Modifica indipendente")
        XCTAssertEqual(patient.clinicalNotes.map(\.id), [existing.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ClinicalNote>()), 1)
    }

    func testBloodTestSavePersistsValuesAndOneProtectedAutomaticNote() throws {
        let schema = Schema([Patient.self, ClinicalNote.self, TherapyMedication.self,
            PHQ9Assessment.self, GAD7Assessment.self, MDQAssessment.self, BeckAssessment.self, MADRSAssessment.self])
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let patient = Patient(firstName: "Test", lastName: "Esami")
        context.insert(patient)
        let column = BloodTestColumnRecord(id: UUID(), dateText: "06/10/2026")
        let payload = BloodTestsTablePayload(columns: [column], rows: [
            BloodTestRowRecord(id: UUID(), testName: "TSH", values: [column.id.uuidString: "2.5"])
        ])
        try BloodTestsPersistence.save(payload, replacing: .empty, for: patient, in: context) { try context.save() }
        XCTAssertEqual(BloodTestsSectionViewModel.decodePayload(from: patient.bloodTestsTableJSON), payload)
        XCTAssertEqual(patient.clinicalNotes.count, 1)
        let note = try XCTUnwrap(patient.clinicalNotes.first)
        XCTAssertTrue(note.readableContent.contains("TSH"))
        XCTAssertEqual(note.content, "")
        XCTAssertNotNil(note.encryptedContent)
        try BloodTestsPersistence.save(payload, replacing: payload, for: patient, in: context) { try context.save() }
        XCTAssertEqual(patient.clinicalNotes.count, 1, "Repeated Save must not duplicate the automatic note")
    }

    private func makeTable(rows: [BloodTestRowRecord], columns: [BloodTestColumnRecord],
        onValue: @escaping (UUID, UUID, String) -> Void = { _, _, _ in }) -> BloodTestsAppKitTableView {
        BloodTestsAppKitTableView(rows: rows, columns: columns,
            rowNameForID: { id in rows.first(where: { $0.id == id })?.testName ?? "" },
            setRowName: { _, _ in }, cellValueForIDs: { rowID, columnID in
                rows.first(where: { $0.id == rowID })?.values[columnID.uuidString] ?? ""
            }, setCellValue: onValue, canDeleteRow: { _ in false }, deleteRow: { _ in },
            onHeaderEditColumn: { _ in }, onHeaderAddAfterColumn: { _ in }, onHeaderDeleteColumn: { _ in },
            selectedColumnID: .constant(nil))
    }
}
