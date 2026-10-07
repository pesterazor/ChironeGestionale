import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import ChironeGestionale

@MainActor
final class PsychometricDateAndMADRSTests: XCTestCase {
    func testMADRSScoreRangeAndSeverityBoundaries() {
        for score in 0...60 {
            let expected: MADRSSeverity = score <= 6 ? .minimal : score <= 19 ? .mild : score <= 34 ? .moderate : .severe
            XCTAssertEqual(MADRSSeverity.from(score: score), expected, "MADRS \(score)")
        }
        XCTAssertNil(MADRSSeverity.from(score: -1))
        XCTAssertNil(MADRSSeverity.from(score: 61))
        XCTAssertEqual(MADRS.totalScore(for: Array(repeating: 0, count: 10)), 0)
        XCTAssertEqual(MADRS.totalScore(for: Array(repeating: 6, count: 10)), 60)
        XCTAssertEqual(MADRS.totalScore(for: [1, 3, 5, 1, 3, 5, 1, 3, 5, 3]), 30)
    }

    func testMADRSRejectsIncompleteAndInvalidScores() {
        for scores in [[], Array(repeating: 0, count: 9), Array(repeating: 0, count: 11),
                       [-1] + Array(repeating: 0, count: 9), [7] + Array(repeating: 0, count: 9)] {
            let assessment = MADRSAssessment(scores: scores)
            XCTAssertNil(assessment.totalScore)
            XCTAssertNil(assessment.severity)
        }
    }

    func testMADRSClinicalReviewIsIndependentOfTotalAndCompletion() {
        for score in 1...6 {
            let complete = Array(repeating: 0, count: 9) + [score]
            XCTAssertEqual(MADRS.totalScore(for: complete), score)
            XCTAssertTrue(MADRS.requiresClinicalReview(scores: complete))
            let incomplete = Array(repeating: -1, count: 9) + [score]
            XCTAssertNil(MADRS.totalScore(for: incomplete))
            XCTAssertTrue(MADRS.requiresClinicalReview(scores: incomplete))
        }
        XCTAssertFalse(MADRS.requiresClinicalReview(scores: []))
        XCTAssertFalse(MADRS.requiresClinicalReview(scores: Array(repeating: 0, count: 10)))
        XCTAssertFalse(MADRS.requiresClinicalReview(scores: Array(repeating: 6, count: 9) + [0]))
    }

    func testMADRSHasTenDistinctItemsAndAllSevenResponseValues() {
        XCTAssertEqual(MADRS.questions.count, 10)
        XCTAssertEqual(Set(MADRS.questions.map(\.title)).count, 10)
        XCTAssertEqual(MADRS.questions.last?.title, "Idee di suicidio")
        for question in MADRS.questions {
            XCTAssertEqual(question.anchors.count, 4)
            XCTAssertFalse(question.description.isEmpty)
            for score in 0...6 { XCTAssertFalse(question.answerLabel(for: score).isEmpty) }
            XCTAssertEqual(question.answerLabel(for: 5), "Valore intermedio tra 4 e 6")
        }
    }

    func testDateChangesPersistForEveryScaleWithoutChangingAnswersOrIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = makeSchema()
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("dates.store"))
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let correctedDate = originalDate.addingTimeInterval(-86400 * 30)
        var originalIDs: Set<UUID> = []
        var originalCreatedAt: [UUID: Date] = [:]
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            let patient = makePatientWithEveryScale(date: originalDate)
            context.insert(patient)
            try context.save()
            for assessment in allAssessments(patient) {
                originalCreatedAt[assessment.id] = assessment.createdAt
                originalIDs.insert(assessment.id)
                try AssessmentDateEditing.update(assessment, to: correctedDate) { try context.save() }
            }
            XCTAssertGreaterThan(patient.updatedAt, originalDate)
        }
        let reopened = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(reopened)
        let patient = try XCTUnwrap(context.fetch(FetchDescriptor<Patient>()).first)
        let assessments = allAssessments(patient)
        XCTAssertEqual(assessments.count, 6)
        XCTAssertEqual(Set(assessments.map(\.id)), originalIDs)
        XCTAssertTrue(assessments.allSatisfy { $0.date == correctedDate && $0.createdAt == originalCreatedAt[$0.id] && $0.patient?.id == patient.id })
        XCTAssertEqual(patient.phq9Assessments.first?.scores, Array(repeating: 1, count: 9))
        XCTAssertEqual(patient.gad7Assessments.first?.scores, Array(repeating: 1, count: 7))
        XCTAssertEqual(patient.mdqAssessments.first?.part1Answers, Array(repeating: 1, count: 13))
        XCTAssertEqual(patient.mdqAssessments.first?.part2Answer, true)
        XCTAssertEqual(patient.mdqAssessments.first?.part3RawValue, 2)
        XCTAssertEqual(patient.beckAssessments.first { $0.scale == .bai }?.answerIndices, Array(repeating: 1, count: 21))
        XCTAssertEqual(patient.beckAssessments.first { $0.scale == .bdiII }?.answerIndices[15], 6)
        XCTAssertEqual(patient.beckAssessments.first { $0.scale == .bdiII }?.answerIndices[17], 4)
        XCTAssertEqual(patient.madrsAssessments.first?.scores, Array(repeating: 0, count: 9) + [1])
        XCTAssertEqual(patient.madrsAssessments.first?.raterName, "Clinico di prova")
        context.delete(patient)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<MADRSAssessment>()).isEmpty)
    }

    func testFailedDateSaveRestoresDateWithoutDiscardingOtherEdits() throws {
        enum SimulatedError: Error { case saveFailed }
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let patient = makePatientWithEveryScale(date: originalDate)
        patient.updatedAt = originalDate
        patient.phoneNumber = "Modifica anagrafica da conservare"
        for assessment in allAssessments(patient) {
            XCTAssertThrowsError(try AssessmentDateEditing.update(assessment, to: originalDate.addingTimeInterval(86400)) {
                throw SimulatedError.saveFailed
            })
            XCTAssertEqual(assessment.date, originalDate)
            XCTAssertEqual(patient.updatedAt, originalDate)
            XCTAssertEqual(patient.phoneNumber, "Modifica anagrafica da conservare")
        }
    }

    func testDateChangeReordersHistoryAndNewReportsForEveryScale() throws {
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let patient = makePatientWithEveryScale(date: oldDate)
        let newerDate = oldDate.addingTimeInterval(86400)
        patient.phq9Assessments.append(PHQ9Assessment(date: newerDate, scores: Array(repeating: 2, count: 9), patient: patient))
        patient.gad7Assessments.append(GAD7Assessment(date: newerDate, scores: Array(repeating: 2, count: 7), patient: patient))
        patient.mdqAssessments.append(MDQAssessment(date: newerDate, part1Answers: Array(repeating: 0, count: 13), part2Answer: false, part3RawValue: 0, patient: patient))
        for scale in BeckScale.allCases {
            patient.beckAssessments.append(BeckAssessment(scale: scale, date: newerDate, answerIndices: Array(repeating: 2, count: 21), patient: patient))
        }
        patient.madrsAssessments.append(MADRSAssessment(date: newerDate, scores: Array(repeating: 2, count: 10), patient: patient))
        let oldDraft = PatientReportService.shared.makeDraft(for: patient, options: ReportOptions(includePsychometricScales: true))
        let oldText = try XCTUnwrap(oldDraft.sections.first { $0.kind == .psychometricScales }?.text)
        for assessment in allAssessments(patient) where assessment.date == oldDate {
            try AssessmentDateEditing.update(assessment, to: newerDate.addingTimeInterval(86400)) {}
        }
        let draft = PatientReportService.shared.makeDraft(for: patient, options: ReportOptions(includePsychometricScales: true))
        let text = try XCTUnwrap(draft.sections.first { $0.kind == .psychometricScales }?.text)
        for (label, score) in [("PHQ-9", "9/27"), ("GAD-7", "7/21"), ("MDQ", "13/13"),
                               ("BAI", "21/63"), ("BDI-II", "24/63"), ("MADRS", "1/60")] {
            let line = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix(label + " del") })
            XCTAssertTrue(line.contains(score), line)
        }
        XCTAssertTrue(text.contains("MADRS: valutatore Clinico di prova"))
        XCTAssertTrue(text.contains("MADRS: item 10 con punteggio > 0"))
        XCTAssertEqual(AssessmentDateEditing.sorted(patient.madrsAssessments).first?.totalScore, 1)
        XCTAssertEqual(oldDraft.sections.first { $0.kind == .psychometricScales }?.text, oldText)
        XCTAssertTrue(oldText.contains("20/60"))
    }

    func testAssessmentSortUsesStableTieBreakers() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = MADRSAssessment(date: date, scores: Array(repeating: 0, count: 10))
        let b = MADRSAssessment(date: date, scores: Array(repeating: 0, count: 10))
        a.createdAt = date
        b.createdAt = date.addingTimeInterval(1)
        XCTAssertEqual(AssessmentDateEditing.sorted([a, b]).map(\.id), [b.id, a.id])
        b.createdAt = date
        a.id = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        b.id = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        XCTAssertEqual(AssessmentDateEditing.sorted([a, b]).map(\.id), [b.id, a.id])
    }

    func testSchema3BackupRestoresBeckAndClearsReplacedMADRS() throws {
        let context = try makeContext()
        context.insert(makePatientWithEveryScale(date: .now))
        try context.save()
        try EncryptedBackupService.shared.restoreBackup(into: context, password: "BeckFixturePassword", backupData: fixture("madrs-legacy-schema3"))
        let patient = try XCTUnwrap(context.fetch(FetchDescriptor<Patient>()).first)
        XCTAssertEqual(patient.firstName, "Legacy")
        XCTAssertEqual(patient.beckAssessments.first?.totalScore, 21)
        XCTAssertTrue(patient.madrsAssessments.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MADRSAssessment>()).isEmpty)
    }

    func testInvalidMADRSBackupsAreRejectedBeforeAnyExistingDataIsDeleted() throws {
        let cases: [(String, EncryptedBackupError)] = [
            ("madrs-incomplete-schema4", .invalidAssessmentData),
            ("madrs-unanswered-schema4", .invalidAssessmentData),
            ("madrs-out-of-range-schema4", .invalidAssessmentData),
            ("madrs-duplicate-schema4", .invalidAssessmentData),
            ("madrs-orphan-schema4", .invalidAssessmentData),
            ("madrs-missing-fields-schema4", .invalidEnvelope),
            ("madrs-count-mismatch-schema4", .invalidEnvelope)
        ]
        for (name, expected) in cases {
            let context = try makeContext()
            let patient = makePatientWithEveryScale(date: .now)
            context.insert(patient)
            try context.save()
            let originalID = try XCTUnwrap(patient.madrsAssessments.first?.id)
            XCTAssertThrowsError(try EncryptedBackupService.shared.restoreBackup(into: context, password: "BeckFixturePassword", backupData: fixture(name))) {
                XCTAssertEqual($0 as? EncryptedBackupError, expected, name)
            }
            XCTAssertEqual(try context.fetch(FetchDescriptor<Patient>()).map(\.id), [patient.id])
            XCTAssertEqual(try context.fetch(FetchDescriptor<MADRSAssessment>()).map(\.id), [originalID])
            XCTAssertEqual(patient.madrsAssessments.first?.totalScore, 1)
        }
    }

    func testInvalidMADRSAssessmentCannotBeExported() throws {
        let context = try makeContext()
        context.insert(MADRSAssessment(scores: Array(repeating: -1, count: 10)))
        XCTAssertThrowsError(try EncryptedBackupService.shared.exportBackup(from: context, password: "test")) {
            XCTAssertEqual($0 as? EncryptedBackupError, .invalidAssessmentData)
        }
    }

    // Render real SwiftUI views offscreen for inspection, without interacting with the user's app.
    func testMADRSAndDateViewsRenderForVisualReview() throws {
        let patient = makePatientWithEveryScale(date: Date(timeIntervalSince1970: 1_700_000_000))
        patient.madrsAssessments.append(MADRSAssessment(date: Date(timeIntervalSince1970: 1_760_000_000), scores: Array(repeating: 4, count: 10), patient: patient))
        for completed in [false, true] {
            let sheet = MADRSAssessmentSheet(patientFullName: patient.fullName,
                existingAssessment: completed ? patient.madrsAssessments.first : nil,
                onSave: { _, _, _ in nil }, onCancel: {})
            try render(sheet, name: "MADRS-\(completed ? "completed" : "new")", width: 820, height: 700)
        }
        try render(AssessmentDateEditorSheet(scaleLabel: "BDI-II", patientName: patient.fullName, date: .now, onSave: { _ in }, onCancel: {}), name: "Assessment-date-editor", width: 468, height: 200)
        try render(MADRSScaleContent(patient: patient).padding(24), name: "MADRS-history", width: 820, height: 620)
        try render(PHQ9ScaleContent(patient: patient).padding(24), name: "PHQ9-date-history", width: 740, height: 480)
        try render(MDQScaleContent(patient: patient).padding(24), name: "MDQ-date-history", width: 740, height: 480)
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

    private func makePatientWithEveryScale(date: Date) -> Patient {
        let patient = Patient(firstName: "Paziente", lastName: "di prova", updatedAt: date)
        patient.phq9Assessments = [PHQ9Assessment(date: date, scores: Array(repeating: 1, count: 9), patient: patient)]
        patient.gad7Assessments = [GAD7Assessment(date: date, scores: Array(repeating: 1, count: 7), patient: patient)]
        patient.mdqAssessments = [MDQAssessment(date: date, part1Answers: Array(repeating: 1, count: 13), part2Answer: true, part3RawValue: 2, patient: patient)]
        var bdiAnswers = Array(repeating: 1, count: 21)
        bdiAnswers[15] = 6
        bdiAnswers[17] = 4
        patient.beckAssessments = [BeckAssessment(scale: .bai, date: date, answerIndices: Array(repeating: 1, count: 21), patient: patient), BeckAssessment(scale: .bdiII, date: date, answerIndices: bdiAnswers, patient: patient)]
        patient.madrsAssessments = [MADRSAssessment(date: date, scores: Array(repeating: 0, count: 9) + [1], raterName: "Clinico di prova", patient: patient)]
        return patient
    }

    private func allAssessments(_ patient: Patient) -> [any DatedPsychometricAssessment] {
        var values: [any DatedPsychometricAssessment] = patient.phq9Assessments
        values.append(contentsOf: patient.gad7Assessments)
        values.append(contentsOf: patient.mdqAssessments)
        values.append(contentsOf: patient.beckAssessments)
        values.append(contentsOf: patient.madrsAssessments)
        return values
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json")))
    }

    private func makeContext() throws -> ModelContext {
        let schema = makeSchema()
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func makeSchema() -> Schema {
        Schema([Patient.self, ClinicalNote.self, TherapyMedication.self, PHQ9Assessment.self,
                GAD7Assessment.self, MDQAssessment.self, BeckAssessment.self, MADRSAssessment.self])
    }
}
