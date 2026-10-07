import XCTest
import SwiftData
import SwiftUI
import AppKit
@testable import ChironeGestionale

@MainActor
final class BeckAssessmentTests: XCTestCase {
    func testEveryScoreHasTheCorrectScaleSpecificSeverity() {
        for score in 0...63 {
            let bai: BeckSeverity = score <= 7 ? .minimal : score <= 15 ? .mild : score <= 25 ? .moderate : .severe
            let bdi: BeckSeverity = score <= 13 ? .minimal : score <= 19 ? .mild : score <= 28 ? .moderate : .severe
            XCTAssertEqual(BeckScale.bai.severity(for: score), bai, "BAI \(score)")
            XCTAssertEqual(BeckScale.bdiII.severity(for: score), bdi, "BDI-II \(score)")
        }
        for scale in BeckScale.allCases {
            XCTAssertNil(scale.severity(for: -1))
            XCTAssertNil(scale.severity(for: 64))
        }
    }

    func testUnansweredAndInvalidItemsDoNotProduceAScore() {
        for scale in BeckScale.allCases {
            XCTAssertNil(scale.totalScore(forAnswers: []))
            XCTAssertNil(scale.totalScore(forAnswers: Array(repeating: 0, count: 20)))
            XCTAssertNil(scale.totalScore(forAnswers: Array(repeating: 0, count: 22)))
            for item in 0..<21 {
                var answers = Array(repeating: 0, count: 21)
                answers[item] = -1
                XCTAssertNil(scale.totalScore(forAnswers: answers))
                answers[item] = scale.questions[item].options.count
                XCTAssertNil(scale.totalScore(forAnswers: answers))
            }
            XCTAssertEqual(scale.totalScore(forAnswers: Array(repeating: 0, count: 21)), 0)
            let highestAnswers = scale.questions.map { $0.options.count - 1 }
            XCTAssertEqual(scale.totalScore(forAnswers: highestAnswers), 63)
        }
        XCTAssertNil(BeckScale.totalScore(for: Array(repeating: 4, count: 21)))
        XCTAssertNil(BeckScale.totalScore(for: Array(repeating: -1, count: 21)))
    }

    func testBDISleepAndAppetiteVariantsRetainTheSameNumericScore() throws {
        for item in [15, 17] {
            for (answer, expectedScore) in [0, 1, 1, 2, 2, 3, 3].enumerated() {
                var answers = Array(repeating: 0, count: 21)
                answers[item] = answer
                let assessment = BeckAssessment(scale: .bdiII, answerIndices: answers)
                XCTAssertEqual(assessment.totalScore, expectedScore)
                XCTAssertEqual(assessment.answerIndices[item], answer)
                XCTAssertEqual(assessment.scores?[item], expectedScore)
            }
            XCTAssertEqual(BeckScale.bdiII.questions[item].options.map(\.code), ["0", "1a", "1b", "2a", "2b", "3a", "3b"])
        }
    }

    func testClinicalReviewDoesNotDependOnTheTotalSeverityOrCompletion() {
        for answer in 1...3 {
            var answers = Array(repeating: -1, count: 21)
            answers[8] = answer
            XCTAssertTrue(BeckScale.bdiII.requiresClinicalReview(answerIndices: answers))
            XCTAssertFalse(BeckScale.bai.requiresClinicalReview(answerIndices: answers))
            answers = Array(repeating: 0, count: 21)
            answers[8] = answer
            let assessment = BeckAssessment(scale: .bdiII, answerIndices: answers)
            XCTAssertEqual(assessment.severity, .minimal)
            XCTAssertTrue(assessment.requiresClinicalReview)
        }
        XCTAssertFalse(BeckScale.bdiII.requiresClinicalReview(answerIndices: []))
        XCTAssertFalse(BeckScale.bdiII.requiresClinicalReview(answerIndices: Array(repeating: 0, count: 21)))
    }

    func testBAIItalianNormsAtEveryBoundaryOfTheProvidedTable() {
        let values = [(0,10), (1,20), (2,30), (3,40), (4,50), (6,50), (7,60), (8,70), (9,70),
                      (10,80), (12,80), (13,85), (15,85), (16,90), (18,90), (19,91), (20,93),
                      (21,94), (22,95), (23,95), (24,96), (25,96), (26,97), (27,98), (28,98), (29,99), (63,99)]
        for (score, percentile) in values {
            XCTAssertEqual(BeckScale.bai.italianPercentile(for: score), percentile)
            XCTAssertNil(BeckScale.bdiII.italianPercentile(for: score))
        }
        XCTAssertNil(BeckScale.bai.italianPercentile(for: -1))
        XCTAssertNil(BeckScale.bai.italianPercentile(for: 64))
    }

    func testAssessmentsRemainSeparateAndSortDeterministically() {
        let sameDate = Date(timeIntervalSince1970: 1_750_000_000)
        let bai = BeckAssessment(scale: .bai, date: sameDate, answerIndices: Array(repeating: 0, count: 21))
        let bdi = BeckAssessment(scale: .bdiII, date: sameDate, answerIndices: Array(repeating: 0, count: 21))
        let newerBAI = BeckAssessment(scale: .bai, date: sameDate.addingTimeInterval(86400), answerIndices: Array(repeating: 1, count: 21))
        XCTAssertEqual(BeckAssessment.sorted([bdi, bai, newerBAI], for: .bai).map(\.id), [newerBAI.id, bai.id])
        XCTAssertEqual(BeckAssessment.sorted([bdi, bai, newerBAI], for: .bdiII).map(\.id), [bdi.id])
        bai.scaleRawValue = "unknown-edition"
        XCTAssertNil(bai.totalScore)
        XCTAssertNil(bai.severity)
    }

    func testResponsesPersistOnDiskAndAreDeletedWithTheirPatient() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = makeSchema()
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("test.store"))
        var answers = Array(repeating: 0, count: 21)
        answers[15] = 6
        answers[17] = 2
        var patientID: UUID!
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let patient = Patient(firstName: "Test", lastName: "Beck")
            patientID = patient.id
            context.insert(patient)
            let assessment = BeckAssessment(scale: .bdiII, answerIndices: answers, patient: patient)
            context.insert(assessment)
            patient.beckAssessments.append(assessment)
            try context.save()
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(reopened)
        let patient = try XCTUnwrap(context.fetch(FetchDescriptor<Patient>()).first)
        let assessment = try XCTUnwrap(patient.beckAssessments.first)
        XCTAssertEqual(patient.id, patientID)
        XCTAssertEqual(assessment.answerIndices, answers)
        XCTAssertEqual(assessment.totalScore, 4)
        XCTAssertEqual(assessment.patient?.id, patientID)
        context.delete(patient)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<BeckAssessment>()).isEmpty)
    }

    func testReportIncludesBothScalesAndIndependentClinicalReview() throws {
        let patient = Patient(firstName: "Test", lastName: "Beck")
        var answers = Array(repeating: 0, count: 21)
        answers[8] = 1
        patient.beckAssessments = [
            BeckAssessment(scale: .bai, answerIndices: Array(repeating: 1, count: 21), patient: patient),
            BeckAssessment(scale: .bdiII, answerIndices: answers, patient: patient)
        ]
        let draft = PatientReportService.shared.makeDraft(for: patient, options: ReportOptions(includePsychometricScales: true))
        let section = try XCTUnwrap(draft.sections.first { $0.kind == .psychometricScales })
        XCTAssertTrue(section.isIncluded)
        XCTAssertTrue(section.text.contains("BAI del"))
        XCTAssertTrue(section.text.contains("21/63"))
        XCTAssertTrue(section.text.contains("percentile 94"))
        XCTAssertTrue(section.text.contains("BDI-II del"))
        XCTAssertTrue(section.text.contains("1/63"))
        XCTAssertTrue(section.text.contains("item 9 positivo"))
    }

    func testLegacyBackupWithoutPsychometricKeysDecodes() throws {
        let payload = Data(#"{"exportedAt":"2026-01-01T00:00:00Z","patients":[],"clinicalNotes":[],"therapyItems":[]}"#.utf8)
        let decoded = try JSONDecoder.chirone.decode(BackupPayload.self, from: payload)
        XCTAssertTrue(decoded.phq9Assessments.isEmpty)
        XCTAssertTrue(decoded.gad7Assessments.isEmpty)
        XCTAssertTrue(decoded.mdqAssessments.isEmpty)
        XCTAssertNil(decoded.beckAssessments)
        XCTAssertNil(decoded.madrsAssessments)
        let counts = Data(#"{"patients":0,"clinicalNotes":0,"therapyItems":0}"#.utf8)
        let decodedCounts = try JSONDecoder.chirone.decode(EncryptedBackupEnvelope.Metadata.RecordCounts.self, from: counts)
        XCTAssertEqual(decodedCounts.phq9Assessments, 0)
        XCTAssertEqual(decodedCounts.gad7Assessments, 0)
        XCTAssertEqual(decodedCounts.mdqAssessments, 0)
        XCTAssertNil(decodedCounts.beckAssessments)
        XCTAssertNil(decodedCounts.madrsAssessments)
    }

    func testLegacySchema2EncryptedBackupRestoresWithoutBeckRecords() throws {
        let context = try makeContext()
        let patient = Patient(firstName: "Replaced", lastName: "Test")
        context.insert(patient)
        let assessment = BeckAssessment(scale: .bai, answerIndices: Array(repeating: 0, count: 21), patient: patient)
        context.insert(assessment)
        patient.beckAssessments = [assessment]
        try context.save()
        try EncryptedBackupService.shared.restoreBackup(
            into: context,
            password: "BeckFixturePassword",
            backupData: fixture("beck-legacy-schema2")
        )
        let patients = try context.fetch(FetchDescriptor<Patient>())
        XCTAssertEqual(patients.count, 1)
        XCTAssertEqual(patients.first?.firstName, "Legacy")
        XCTAssertTrue(patients.first?.beckAssessments.isEmpty == true)
        XCTAssertTrue(try context.fetch(FetchDescriptor<BeckAssessment>()).isEmpty)
    }

    func testInvalidBeckBackupIsRejectedBeforeExistingRecordsAreDeleted() throws {
        for (name, expectedError) in [
            ("beck-invalid-responses-schema3", EncryptedBackupError.invalidAssessmentData),
            ("beck-missing-fields-schema3", EncryptedBackupError.invalidEnvelope)
        ] {
            let context = try makeContext()
            let patient = Patient(firstName: "Preserve", lastName: "Test")
            context.insert(patient)
            let assessment = BeckAssessment(scale: .bai, answerIndices: Array(repeating: 1, count: 21), patient: patient)
            context.insert(assessment)
            patient.beckAssessments = [assessment]
            try context.save()
            XCTAssertThrowsError(try EncryptedBackupService.shared.restoreBackup(
                into: context, password: "BeckFixturePassword", backupData: fixture(name)
            )) { error in
                XCTAssertEqual(error as? EncryptedBackupError, expectedError)
            }
            XCTAssertEqual(try context.fetch(FetchDescriptor<Patient>()).map(\.id), [patient.id])
            XCTAssertEqual(try context.fetch(FetchDescriptor<BeckAssessment>()).map(\.id), [assessment.id])
            XCTAssertEqual(assessment.totalScore, 21)
        }
    }

    func testInvalidAnswersCannotBeExportedAsAValidAssessment() throws {
        let context = try makeContext()
        let assessment = BeckAssessment(scale: .bai, answerIndices: Array(repeating: -1, count: 21))
        context.insert(assessment)
        XCTAssertThrowsError(try EncryptedBackupService.shared.exportBackup(from: context, password: "test")) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .invalidAssessmentData)
        }
    }

    // Offscreen rendering only: no interactions with windows or the user's database.
    func testAssessmentSheetsRenderForVisualReview() throws {
        for scale in BeckScale.allCases {
            for isCompleted in [false, true] {
                let assessment = isCompleted ? BeckAssessment(
                    scale: scale, answerIndices: scale.questions.map { $0.options.count - 1 }
                ) : nil
                let sheet = BeckAssessmentSheet(
                    scale: scale, patientFullName: "Paziente di prova", existingAssessment: assessment,
                    onSave: { _, _ in nil }, onCancel: {}
                )
                let hosting = NSHostingView(rootView: sheet
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .light))
                hosting.frame = NSRect(x: 0, y: 0, width: 820, height: 700)
                let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = hosting
                hosting.layoutSubtreeIfNeeded()
                let representation = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: representation)
                let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(png.count, 10000)
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = "\(scale.label)-\(isCompleted ? "completed" : "new")-assessment-sheet"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.contentView = nil
            }
        }
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func makeContext() throws -> ModelContext {
        let schema = makeSchema()
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func makeSchema() -> Schema {
        Schema([Patient.self, ClinicalNote.self, TherapyMedication.self,
                PHQ9Assessment.self, GAD7Assessment.self, MDQAssessment.self, BeckAssessment.self, MADRSAssessment.self])
    }
}
