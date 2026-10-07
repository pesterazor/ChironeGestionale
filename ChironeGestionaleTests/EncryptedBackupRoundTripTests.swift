import Foundation
import SwiftData
import XCTest
@testable import ChironeGestionale

@MainActor
final class EncryptedBackupRoundTripTests: XCTestCase {
    private let password = "Archivio di prova – password 🔐"
    private let date = Date(timeIntervalSince1970: 1_760_000_000.125)

    func testEncryptedRoundTripPreservesAllFieldsAndSixScalesAfterReopeningStore() throws {
        let source = try makeContext()
        let originalPatients = try populateArchive(source)
        let expected = try snapshot(source)
        let originalCiphertext = try XCTUnwrap(originalPatients.first?.encryptedPrimaryDiagnosis)
        let data = try EncryptedBackupService.shared.exportBackup(from: source, password: password)
        XCTAssertEqual(try JSONDecoder.chirone.decode(EncryptedBackupEnvelope.self, from: data).metadata.schemaVersion, 5)
        let envelopeText = try XCTUnwrap(String(data: data, encoding: .utf8))
        for secret in ["Cognome sintetico", "Diagnosi primaria sintetica", "Valutatore sintetico", originalCiphertext] {
            XCTAssertFalse(envelopeText.contains(secret), "Plaintext or a local ciphertext escaped into the envelope")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("restored.store")
        let backupURL = directory.appendingPathComponent("synthetic.chdb")
        try data.write(to: backupURL, options: .atomic)
        let savedBackup = try Data(contentsOf: backupURL)
        XCTAssertEqual(savedBackup, data)

        // Release both context and container before opening the persisted archive again.
        try autoreleasepool {
            let destination = try makeContext(storeURL: storeURL)
            try populateArchive(destination)
            try EncryptedBackupService.shared.restoreBackup(into: destination, password: password, backupData: savedBackup)
            assertArchive(expected, equals: try snapshot(destination))
            XCTAssertFalse(destination.hasChanges)
        }

        let reopened = try makeContext(storeURL: storeURL)
        assertArchive(expected, equals: try snapshot(reopened))
        let restoredPatients = try reopened.fetch(FetchDescriptor<Patient>())
        let restored = try XCTUnwrap(restoredPatients.first { $0.id == originalPatients[0].id })
        XCTAssertEqual(restored.dateOfBirth, originalPatients[0].dateOfBirth)
        XCTAssertEqual(restored.createdAt, originalPatients[0].createdAt)
        XCTAssertEqual(restored.updatedAt, originalPatients[0].updatedAt)
        XCTAssertNotEqual(restored.encryptedPrimaryDiagnosis, originalCiphertext)
        for patient in restoredPatients {
            XCTAssertEqual(patient.primaryDiagnosis, "")
            XCTAssertEqual(patient.secondaryDiagnosis, "")
            XCTAssertNil(patient.medicalComorbidities)
            XCTAssertNil(patient.remotePsychiatricHistory)
            XCTAssertEqual(patient.allergies, "")
            XCTAssertNotNil(patient.encryptedPrimaryDiagnosis)
        }
        for note in try reopened.fetch(FetchDescriptor<ClinicalNote>()) {
            XCTAssertEqual(note.content, "")
            XCTAssertNotNil(note.encryptedContent)
        }
        // The BDI-II answer variants must survive as selected options, not only as scores.
        for assessment in try reopened.fetch(FetchDescriptor<BeckAssessment>()) where assessment.scale == .bdiII {
            XCTAssertEqual(assessment.answerIndices[15], 6)
            XCTAssertEqual(assessment.answerIndices[17], 5)
        }
    }

    func testWrongPasswordAndDamagedCiphertextsNeverReplaceExistingArchive() throws {
        let source = try makeContext()
        try populateArchive(source)
        let data = try EncryptedBackupService.shared.exportBackup(from: source, password: password)
        let destination = try makeContext()
        try populateArchive(destination)
        let before = try snapshot(destination)

        let attempts: [(Data, String, EncryptedBackupError)] = [
            (data, "password errata", .invalidPassword),
            (data, "", .invalidPassword),
            (try corruptLastByte(in: data, field: "wrappedDEKBase64"), password, .invalidPassword),
            (try corruptLastByte(in: data, field: "payloadBase64"), password, .decryptionFailed)
        ]
        for (backup, candidate, expectedError) in attempts {
            XCTAssertThrowsError(try EncryptedBackupService.shared.restoreBackup(
                into: destination, password: candidate, backupData: backup
            )) {
                XCTAssertEqual($0 as? EncryptedBackupError, expectedError)
            }
            assertArchive(before, equals: try snapshot(destination))
            XCTAssertFalse(destination.hasChanges)
        }
    }

    func testAppendPreservesBothCompleteArchivesAndReplacementRemovesEveryOldRecordType() throws {
        let source = try makeContext()
        try populateArchive(source)
        let imported = try snapshot(source)
        let prepared = try EncryptedBackupService.shared.decryptBackup(
            password: password,
            backupData: EncryptedBackupService.shared.exportBackup(from: source, password: password)
        )
        let destination = try makeContext()
        try populateArchive(destination)
        let existing = try snapshot(destination)
        try EncryptedBackupService.shared.restorePreparedBackup(prepared, into: destination, replaceExisting: false)
        let combined = existing.merging(imported) { _, incoming in incoming }
        assertArchive(combined, equals: try snapshot(destination))

        try EncryptedBackupService.shared.restorePreparedBackup(prepared, into: destination)
        assertArchive(imported, equals: try snapshot(destination))
    }

    func testEmptyEncryptedBackupReplacesArchiveIncludingAllScalesAndOrphanRecords() throws {
        let empty = try makeContext()
        let data = try EncryptedBackupService.shared.exportBackup(from: empty, password: password)
        let destination = try makeContext()
        try populateArchive(destination)
        XCTAssertFalse(try snapshot(destination).isEmpty)
        try EncryptedBackupService.shared.restoreBackup(into: destination, password: password, backupData: data)
        XCTAssertTrue(try snapshot(destination).isEmpty)
    }

    func testSubsecondAssessmentDatesAndChronologicalTieBreakersSurviveEncryption() throws {
        let source = try makeContext()
        let patient = Patient(firstName: "Cronologia", lastName: "Sintetica")
        source.insert(patient)
        let earlier = MADRSAssessment(date: date, scores: Array(repeating: 1, count: 10), patient: patient)
        earlier.id = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        earlier.createdAt = date
        let later = MADRSAssessment(date: date, scores: Array(repeating: 2, count: 10), patient: patient)
        later.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        later.createdAt = date.addingTimeInterval(0.5)
        source.insert(earlier)
        source.insert(later)
        try source.save()
        let expectedOrder = AssessmentDateEditing.sorted(patient.madrsAssessments).map(\.id)
        XCTAssertEqual(expectedOrder, [later.id, earlier.id])

        let data = try EncryptedBackupService.shared.exportBackup(from: source, password: password)
        let destination = try makeContext()
        try EncryptedBackupService.shared.restoreBackup(into: destination, password: password, backupData: data)
        let restored = try XCTUnwrap(destination.fetch(FetchDescriptor<Patient>()).first)
        XCTAssertEqual(AssessmentDateEditing.sorted(restored.madrsAssessments).map(\.id), expectedOrder)
        let restoredEarlier = try XCTUnwrap(restored.madrsAssessments.first { $0.id == earlier.id })
        let restoredLater = try XCTUnwrap(restored.madrsAssessments.first { $0.id == later.id })
        XCTAssertEqual(restoredEarlier.date, date)
        XCTAssertEqual(restoredEarlier.createdAt, earlier.createdAt)
        XCTAssertEqual(restoredLater.createdAt, later.createdAt)
    }

    func testLegacySchema4WithMADRSRestoresAndCanBeExportedInCurrentFormat() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/madrs-valid-schema4.json")
        let context = try makeContext()
        try EncryptedBackupService.shared.restoreBackup(
            into: context, password: "BeckFixturePassword", backupData: Data(contentsOf: fixtureURL)
        )
        let patient = try XCTUnwrap(context.fetch(FetchDescriptor<Patient>()).first)
        XCTAssertEqual(patient.beckAssessments.count, 1)
        let madrs = try XCTUnwrap(patient.madrsAssessments.first)
        XCTAssertEqual(madrs.scores, [0, 1, 2, 3, 4, 5, 6, 1, 3, 5])
        XCTAssertEqual(madrs.raterName, "Valutatore legacy sintetico")
        XCTAssertEqual(madrs.patient?.id, patient.id)
        let expected = try snapshot(context)
        let current = try EncryptedBackupService.shared.exportBackup(from: context, password: password)
        let destination = try makeContext()
        try EncryptedBackupService.shared.restoreBackup(into: destination, password: password, backupData: current)
        assertArchive(expected, equals: try snapshot(destination))
    }

    func testPatientPortabilityExportContainsEveryScaleAndLegacyClinicalFields() throws {
        let context = try makeContext()
        let patient = try XCTUnwrap(populateArchive(context).first)
        let data = try BackupUIService().makePatientPortabilityData(for: patient)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let patientData = try XCTUnwrap(object["patient"] as? [String: Any])
        XCTAssertEqual(patientData["medicalHistory"] as? String, patient.medicalHistory)
        XCTAssertEqual(patientData["currentTherapySummary"] as? String, patient.currentTherapySummary)
        XCTAssertEqual(patientData["primaryDiagnosis"] as? String, patient.readablePrimaryDiagnosis)
        for key in ["phq9Assessments", "gad7Assessments", "mdqAssessments", "beckAssessments", "madrsAssessments"] {
            let records = try XCTUnwrap(object[key] as? [[String: Any]])
            XCTAssertEqual(records.count, key == "beckAssessments" ? 2 : 1, key)
            XCTAssertTrue(records.allSatisfy { $0["patientID"] as? String == patient.id.uuidString }, key)
        }
        let beck = try XCTUnwrap(object["beckAssessments"] as? [[String: Any]])
        let bdi = try XCTUnwrap(beck.first { $0["scaleRawValue"] as? String == BeckScale.bdiII.rawValue })
        XCTAssertEqual((bdi["answerIndices"] as? [Int])?[15], 6)
        XCTAssertEqual((bdi["answerIndices"] as? [Int])?[17], 5)
        let madrs = try XCTUnwrap((object["madrsAssessments"] as? [[String: Any]])?.first)
        XCTAssertEqual(madrs["raterName"] as? String, patient.madrsAssessments.first?.raterName)
        XCTAssertEqual(madrs["scores"] as? [Int], patient.madrsAssessments.first?.scores)
    }

    func testPatientPortabilityRefusesUnreadableClinicalFieldsAndInvalidScales() throws {
        let context = try makeContext()
        let patient = try XCTUnwrap(populateArchive(context).first)
        let original = patient.encryptedPrimaryDiagnosis
        patient.encryptedPrimaryDiagnosis = "unreadable-ciphertext"
        XCTAssertThrowsError(try BackupUIService().makePatientPortabilityData(for: patient)) {
            XCTAssertEqual($0 as? EncryptedBackupError, .unreadableClinicalData)
        }
        patient.encryptedPrimaryDiagnosis = original
        patient.madrsAssessments.first?.scores = [7]
        XCTAssertThrowsError(try BackupUIService().makePatientPortabilityData(for: patient)) {
            XCTAssertEqual($0 as? EncryptedBackupError, .invalidAssessmentData)
        }
    }

    @discardableResult
    private func populateArchive(_ context: ModelContext) throws -> [Patient] {
        let bloodColumn = UUID()
        let bloodTests = BloodTestsTablePayload(
            columns: [.init(id: bloodColumn, dateText: "07/10/2026")],
            rows: [.init(id: UUID(), testName: "Esame sintetico", values: [bloodColumn.uuidString: "12,3"])]
        )
        let complete = Patient(
            firstName: "Nome sintetico è", lastName: "Cognome sintetico",
            dateOfBirth: date.addingTimeInterval(-1_000_000_000), gender: "F",
            taxCode: "CODICE-SINTETICO", placeOfBirth: "Comune nascita", birthProvince: "TO",
            residence: "Residenza storica", residenceAddress: "Via sintetica 12",
            residenceCity: "Comune residenza", residenceProvince: "MI",
            phoneNumber: "+39 000000000", emergencyContact: "Contatto sintetico",
            generalPractitioner: "MMG sintetico", privacyConsentSigned: true,
            referenceCSM: "CSM sintetico", referringClinician: "Inviante sintetico",
            medicalHistory: "Anamnesi generale\nSeconda riga Ω", exemptions: "ESENZIONE-SINTETICA",
            currentTherapySummary: "Terapia testuale storica", heartFunctionStatus: "green",
            liverFunctionStatus: "yellow", kidneyFunctionStatus: "red",
            bloodTestsTableJSON: String(decoding: try JSONEncoder().encode(bloodTests), as: UTF8.self),
            createdAt: date.addingTimeInterval(-86400), updatedAt: date.addingTimeInterval(0.75)
        )
        XCTAssertTrue(complete.protectPrimaryDiagnosis("Diagnosi primaria sintetica\ncon Unicode α"))
        XCTAssertTrue(complete.protectSecondaryDiagnosis("Diagnosi secondaria sintetica"))
        XCTAssertTrue(complete.protectMedicalComorbidities("Comorbidità sintetica"))
        XCTAssertTrue(complete.protectRemotePsychiatricHistory("Anamnesi psichiatrica sintetica"))
        XCTAssertTrue(complete.protectAllergies("Allergia sintetica"))

        // Legacy plaintext fields must remain readable while becoming protected at import.
        let legacy = Patient(
            firstName: "Anagrafica", lastName: "Minima", primaryDiagnosis: "Diagnosi storica in chiaro",
            secondaryDiagnosis: "Secondaria storica", allergies: "Allergia storica",
            createdAt: date.addingTimeInterval(1), updatedAt: date.addingTimeInterval(2)
        )
        let patients = [complete, legacy]
        for patient in patients { context.insert(patient) }

        // A nil relationship is valid in the current model and must not get attached to another patient.
        let owners: [Patient?] = patients.map { Optional($0) } + [nil]
        for (index, owner) in owners.enumerated() {
            let stamp = date.addingTimeInterval(Double(index) * 86400)
            let note = ClinicalNote(
                content: "  Nota storica sintetica \(index)\nSeconda riga\n  ", wellbeingScore: index * 5,
                createdAt: stamp, updatedAt: stamp.addingTimeInterval(0.5), patient: owner
            )
            if index == 0 { XCTAssertTrue(note.protectContent("Nota cifrata sintetica\nSeconda riga")) }
            context.insert(note)
            context.insert(TherapyMedication(
                medicationName: "Farmaco sintetico \(index)", dosage: "Dose sintetica", posology: "Posologia\nseconda riga",
                isActive: index != 1, createdAt: stamp, updatedAt: stamp.addingTimeInterval(1.25), patient: owner
            ))
            let phq9 = PHQ9Assessment(date: stamp, scores: [0, 1, 2, 3, 0, 1, 2, 3, 1], patient: owner)
            phq9.createdAt = stamp.addingTimeInterval(0.125)
            context.insert(phq9)
            let gad7 = GAD7Assessment(date: stamp, scores: [3, 2, 1, 0, 1, 2, 3], patient: owner)
            gad7.createdAt = stamp.addingTimeInterval(0.25)
            context.insert(gad7)
            let mdq = MDQAssessment(
                date: stamp, part1Answers: [1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1],
                part2Answer: index != 1, part3RawValue: index + 1, patient: owner
            )
            mdq.createdAt = stamp.addingTimeInterval(0.375)
            context.insert(mdq)
            for scale in BeckScale.allCases {
                var answers = (0..<21).map { $0 % 4 }
                if scale == .bdiII {
                    answers[15] = 6
                    answers[17] = 5
                }
                let beck = BeckAssessment(scale: scale, date: stamp, answerIndices: answers, patient: owner)
                beck.createdAt = stamp.addingTimeInterval(0.5)
                context.insert(beck)
            }
            let madrs = MADRSAssessment(
                date: stamp, scores: [0, 1, 2, 3, 4, 5, 6, 1, 3, 5],
                raterName: "Valutatore sintetico \(index) – Ω", patient: owner
            )
            madrs.createdAt = stamp.addingTimeInterval(0.625)
            context.insert(madrs)
        }
        try context.save()
        return patients
    }

    // Independent model snapshots catch missing mappings in BOTH export and import. Dates retain
    // their exact Double representation, and relationship arrays retain duplicate IDs if present.
    private func snapshot(_ context: ModelContext) throws -> [String: [String: String]] {
        var records: [String: [String: String]] = [:]
        for patient in try context.fetch(FetchDescriptor<Patient>()) {
            var row: [String: String] = [:]
            row["id"] = patient.id.uuidString
            row["firstName"] = patient.firstName
            row["lastName"] = patient.lastName
            row["dateOfBirth"] = patient.dateOfBirth.map(timestamp) ?? "<nil>"
            row["gender"] = patient.gender ?? "<nil>"
            row["taxCode"] = patient.taxCode
            row["placeOfBirth"] = patient.placeOfBirth
            row["birthProvince"] = patient.birthProvince ?? "<nil>"
            row["residence"] = patient.residence
            row["residenceAddress"] = patient.residenceAddress ?? "<nil>"
            row["residenceCity"] = patient.residenceCity ?? "<nil>"
            row["residenceProvince"] = patient.residenceProvince ?? "<nil>"
            row["phoneNumber"] = patient.phoneNumber
            row["emergencyContact"] = patient.emergencyContact
            row["generalPractitioner"] = patient.generalPractitioner
            row["privacyConsentSigned"] = String(patient.privacyConsentSigned)
            row["referenceCSM"] = patient.referenceCSM
            row["referringClinician"] = patient.referringClinician
            row["primaryDiagnosis"] = patient.readablePrimaryDiagnosis
            row["secondaryDiagnosis"] = patient.readableSecondaryDiagnosis
            row["medicalHistory"] = patient.medicalHistory
            row["medicalComorbidities"] = patient.readableMedicalComorbidities
            row["remotePsychiatricHistory"] = patient.readableRemotePsychiatricHistory
            row["allergies"] = patient.readableAllergies
            row["exemptions"] = patient.exemptions
            row["currentTherapySummary"] = patient.currentTherapySummary
            row["heartFunctionStatus"] = patient.heartFunctionStatus ?? "<nil>"
            row["liverFunctionStatus"] = patient.liverFunctionStatus ?? "<nil>"
            row["kidneyFunctionStatus"] = patient.kidneyFunctionStatus ?? "<nil>"
            row["bloodTestsTableJSON"] = patient.bloodTestsTableJSON ?? "<nil>"
            row["createdAt"] = timestamp(patient.createdAt)
            row["updatedAt"] = timestamp(patient.updatedAt)
            row["clinicalNotes"] = identifiers(patient.clinicalNotes.map(\.id))
            row["therapyItems"] = identifiers(patient.therapyItems.map(\.id))
            row["phq9Assessments"] = identifiers(patient.phq9Assessments.map(\.id))
            row["gad7Assessments"] = identifiers(patient.gad7Assessments.map(\.id))
            row["mdqAssessments"] = identifiers(patient.mdqAssessments.map(\.id))
            row["beckAssessments"] = identifiers(patient.beckAssessments.map(\.id))
            row["madrsAssessments"] = identifiers(patient.madrsAssessments.map(\.id))
            records["patient:\(patient.id)"] = row
        }
        for note in try context.fetch(FetchDescriptor<ClinicalNote>()) {
            records["note:\(note.id)"] = [
                "id": note.id.uuidString, "patientID": note.patient?.id.uuidString ?? "<nil>",
                "content": note.readableContent, "wellbeingScore": String(note.wellbeingScore),
                "createdAt": timestamp(note.createdAt), "updatedAt": timestamp(note.updatedAt)
            ]
        }
        for medication in try context.fetch(FetchDescriptor<TherapyMedication>()) {
            records["medication:\(medication.id)"] = [
                "id": medication.id.uuidString, "patientID": medication.patient?.id.uuidString ?? "<nil>",
                "medicationName": medication.medicationName, "dosage": medication.dosage,
                "posology": medication.posology, "isActive": String(medication.isActive),
                "createdAt": timestamp(medication.createdAt), "updatedAt": timestamp(medication.updatedAt)
            ]
        }
        for assessment in try context.fetch(FetchDescriptor<PHQ9Assessment>()) {
            var row = assessmentFields(assessment.id, assessment.date, assessment.createdAt, assessment.patient)
            row["scores"] = String(describing: assessment.scores)
            records["phq9:\(assessment.id)"] = row
        }
        for assessment in try context.fetch(FetchDescriptor<GAD7Assessment>()) {
            var row = assessmentFields(assessment.id, assessment.date, assessment.createdAt, assessment.patient)
            row["scores"] = String(describing: assessment.scores)
            records["gad7:\(assessment.id)"] = row
        }
        for assessment in try context.fetch(FetchDescriptor<MDQAssessment>()) {
            var row = assessmentFields(assessment.id, assessment.date, assessment.createdAt, assessment.patient)
            row["part1Answers"] = String(describing: assessment.part1Answers)
            row["part2Answer"] = String(assessment.part2Answer)
            row["part3RawValue"] = String(assessment.part3RawValue)
            records["mdq:\(assessment.id)"] = row
        }
        for assessment in try context.fetch(FetchDescriptor<BeckAssessment>()) {
            var row = assessmentFields(assessment.id, assessment.date, assessment.createdAt, assessment.patient)
            row["scaleRawValue"] = assessment.scaleRawValue
            row["answerIndices"] = String(describing: assessment.answerIndices)
            records["beck:\(assessment.id)"] = row
        }
        for assessment in try context.fetch(FetchDescriptor<MADRSAssessment>()) {
            var row = assessmentFields(assessment.id, assessment.date, assessment.createdAt, assessment.patient)
            row["scores"] = String(describing: assessment.scores)
            row["raterName"] = assessment.raterName
            records["madrs:\(assessment.id)"] = row
        }
        return records
    }

    private func assessmentFields(_ id: UUID, _ date: Date, _ createdAt: Date, _ patient: Patient?) -> [String: String] {
        ["id": id.uuidString, "date": timestamp(date), "createdAt": timestamp(createdAt),
         "patientID": patient?.id.uuidString ?? "<nil>"]
    }

    private func timestamp(_ date: Date) -> String {
        String(date.timeIntervalSinceReferenceDate.bitPattern)
    }

    private func identifiers(_ ids: [UUID]) -> String {
        ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    private func assertArchive(
        _ expected: [String: [String: String]], equals actual: [String: [String: String]],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(Set(actual.keys), Set(expected.keys), file: file, line: line)
        for key in expected.keys.sorted() {
            XCTAssertEqual(actual[key], expected[key], key, file: file, line: line)
        }
    }

    private func corruptLastByte(in data: Data, field: String) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let base64 = try XCTUnwrap(object[field] as? String)
        var bytes = try XCTUnwrap(Data(base64Encoded: base64))
        bytes[bytes.count - 1] ^= 1
        object[field] = bytes.base64EncodedString()
        return try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }

    private func makeContext(storeURL: URL? = nil) throws -> ModelContext {
        let schema = Schema([
            Patient.self, ClinicalNote.self, TherapyMedication.self, PHQ9Assessment.self,
            GAD7Assessment.self, MDQAssessment.self, BeckAssessment.self, MADRSAssessment.self
        ])
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
