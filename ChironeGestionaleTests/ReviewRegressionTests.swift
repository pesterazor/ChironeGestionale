import AppKit
import SwiftUI
import SwiftData
import XCTest
@testable import ChironeGestionale

@MainActor
final class ReviewRegressionTests: XCTestCase {
    func testFailedMultiRecordClinicalChangeRestoresTherapyAndRemovesInsertedNote() throws {
        enum Failure: Error { case save }
        let schema = Schema([Patient.self, ClinicalNote.self, TherapyMedication.self, PHQ9Assessment.self,
                             GAD7Assessment.self, MDQAssessment.self, BeckAssessment.self, MADRSAssessment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let patient = Patient(firstName: "Test", currentTherapySummary: "Terapia precedente")
        let medication = TherapyMedication(medicationName: "Farmaco di prova", dosage: "10 mg", patient: patient)
        context.insert(patient)
        context.insert(medication)
        patient.therapyItems = [medication]
        try context.save()
        patient.lastName = "Modifica anagrafica precedente"
        let oldID = medication.id
        XCTAssertThrowsError(try ClinicalPersistence.perform(in: context, changes: {
            context.delete(medication)
            let replacement = TherapyMedication(medicationName: "Sostituzione", patient: patient)
            context.insert(replacement)
            patient.therapyItems = [replacement]
            let note = ClinicalNote(content: "", wellbeingScore: 0, patient: patient)
            XCTAssertTrue(note.protectContent("Aggiornamento sintetico"))
            context.insert(note)
            patient.clinicalNotes = [note]
            patient.currentTherapySummary = "Nuova terapia"
        }, save: { throw Failure.save }))
        XCTAssertEqual(patient.lastName, "Modifica anagrafica precedente")
        XCTAssertEqual(patient.currentTherapySummary, "Terapia precedente")
        XCTAssertEqual(patient.therapyItems.map(\.id), [oldID])
        XCTAssertTrue(try context.fetch(FetchDescriptor<ClinicalNote>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TherapyMedication>()).map(\.id), [oldID])
    }

    func testAssessmentDeletionPersistsAndFailurePreservesOtherChanges() throws {
        enum Failure: Error { case save }
        let schema = Schema([Patient.self, ClinicalNote.self, TherapyMedication.self, PHQ9Assessment.self,
                             GAD7Assessment.self, MDQAssessment.self, BeckAssessment.self, MADRSAssessment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let patient = Patient(firstName: "Test")
        let assessment = MADRSAssessment(scores: Array(repeating: 1, count: 10), patient: patient)
        context.insert(patient)
        context.insert(assessment)
        patient.madrsAssessments = [assessment]
        try context.save()
        patient.firstName = "Modifica precedente"
        XCTAssertThrowsError(try AssessmentDeletion.delete(assessment, in: context) { throw Failure.save })
        XCTAssertEqual(try context.fetch(FetchDescriptor<Patient>()).first?.firstName, "Modifica precedente")
        let recovered = try XCTUnwrap(context.fetch(FetchDescriptor<MADRSAssessment>()).first)
        XCTAssertEqual(recovered.id, assessment.id)
        XCTAssertEqual(recovered.scores, Array(repeating: 1, count: 10))
        try AssessmentDeletion.delete(recovered, in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MADRSAssessment>()).isEmpty)
        XCTAssertTrue(patient.madrsAssessments.isEmpty)
    }

    func testIncompleteQuestionnairesCannotBecomeZeroScoreAssessments() {
        for count in [7, 9] {
            XCTAssertFalse(PsychometricResponseValidation.isComplete(Array(repeating: -1, count: count), itemCount: count, range: 0...3))
            XCTAssertFalse(PsychometricResponseValidation.isComplete(Array(repeating: 0, count: count - 1), itemCount: count, range: 0...3))
            XCTAssertFalse(PsychometricResponseValidation.isComplete([4] + Array(repeating: 0, count: count - 1), itemCount: count, range: 0...3))
            XCTAssertTrue(PsychometricResponseValidation.isComplete(Array(repeating: 0, count: count), itemCount: count, range: 0...3))
            XCTAssertTrue(PsychometricResponseValidation.isComplete(Array(repeating: 3, count: count), itemCount: count, range: 0...3))
        }
        let noSymptoms = Array(repeating: 0, count: 13)
        XCTAssertFalse(PsychometricResponseValidation.isCompleteMDQ(part1: noSymptoms, part2: -1, part3: 0))
        XCTAssertFalse(PsychometricResponseValidation.isCompleteMDQ(part1: noSymptoms, part2: 0, part3: -1))
        XCTAssertFalse(PsychometricResponseValidation.isCompleteMDQ(part1: [-1] + noSymptoms.dropFirst(), part2: 0, part3: 0))
        XCTAssertTrue(PsychometricResponseValidation.isCompleteMDQ(part1: noSymptoms, part2: 0, part3: 0))
    }

    func testEncryptionFailurePreservesPriorClinicalValuesWithoutPlaintextFallback() throws {
        let patient = Patient()
        let priorPrimary = try XCTUnwrap(SecureDataCipher.shared.encrypt("prior-primary"))
        let priorSecondary = try XCTUnwrap(SecureDataCipher.shared.encrypt("prior-secondary"))
        let priorAllergies = try XCTUnwrap(SecureDataCipher.shared.encrypt("prior-allergies"))
        let priorComorbidities = try XCTUnwrap(SecureDataCipher.shared.encrypt("prior-comorbidities"))
        let priorHistory = try XCTUnwrap(SecureDataCipher.shared.encrypt("prior-history"))
        patient.encryptedPrimaryDiagnosis = priorPrimary
        patient.encryptedSecondaryDiagnosis = priorSecondary
        patient.encryptedAllergies = priorAllergies
        patient.encryptedMedicalComorbidities = priorComorbidities
        patient.encryptedRemotePsychiatricHistory = priorHistory
        XCTAssertFalse(patient.protectPrimaryDiagnosis("sensitive", encrypt: { _ in nil }))
        XCTAssertFalse(patient.protectSecondaryDiagnosis("sensitive", encrypt: { _ in nil }))
        XCTAssertFalse(patient.protectAllergies("sensitive", encrypt: { _ in nil }))
        XCTAssertFalse(patient.protectMedicalComorbidities("sensitive", encrypt: { _ in nil }))
        XCTAssertFalse(patient.protectRemotePsychiatricHistory("sensitive", encrypt: { _ in nil }))
        XCTAssertEqual(patient.encryptedPrimaryDiagnosis, priorPrimary)
        XCTAssertEqual(patient.encryptedSecondaryDiagnosis, priorSecondary)
        XCTAssertEqual(patient.encryptedAllergies, priorAllergies)
        XCTAssertEqual(patient.encryptedMedicalComorbidities, priorComorbidities)
        XCTAssertEqual(patient.encryptedRemotePsychiatricHistory, priorHistory)
        XCTAssertEqual(patient.primaryDiagnosis, "")
        XCTAssertEqual(patient.secondaryDiagnosis, "")
        XCTAssertEqual(patient.allergies, "")
        XCTAssertNil(patient.medicalComorbidities)
        XCTAssertNil(patient.remotePsychiatricHistory)
        XCTAssertTrue(patient.protectPrimaryDiagnosis("", encrypt: { _ in nil }))
        XCTAssertNil(patient.encryptedPrimaryDiagnosis)
        XCTAssertTrue(patient.protectMedicalComorbidities("  ", encrypt: { _ in nil }))
        XCTAssertNil(patient.encryptedMedicalComorbidities)
    }

    func testClosingChangedDocumentRequiresDiscardDecision() {
        let guardState = DocumentWindowCloseGuard()
        var asked = false
        XCTAssertTrue(guardState.permitsClosing { asked = true; return false })
        XCTAssertFalse(asked)
        guardState.hasUnexportedChanges = true
        XCTAssertFalse(guardState.permitsClosing { asked = true; return false })
        XCTAssertTrue(asked)
        XCTAssertTrue(guardState.permitsClosing { true })
    }

    func testUnansweredQuestionnaireViewsRenderForReview() throws {
        try render(PHQ9AssessmentSheet(patientFullName: "Paziente di prova", onSave: { _, _ in nil }, onCancel: {}), name: "PHQ9-unanswered", width: 820, height: 640)
        try render(GAD7AssessmentSheet(patientFullName: "Paziente di prova", onSave: { _, _ in nil }, onCancel: {}), name: "GAD7-unanswered", width: 820, height: 600)
        try render(MDQAssessmentSheet(patientFullName: "Paziente di prova", onSave: { _, _, _, _ in nil }, onCancel: {}), name: "MDQ-unanswered", width: 820, height: 680)
    }

    private func render<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat) throws {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        window.contentView = nil
    }
}
