import Foundation
import SwiftData
import XCTest
@testable import ChironeGestionale

@MainActor
final class BackupIntegrityTests: XCTestCase {
    private let password = "ArchivioSinteticoPassword"

    func testFailedReplacementPreservesCommittedArchiveAndEarlierPendingChanges() throws {
        enum InjectedFailure: Error { case diskFull }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = makeSchema()
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("atomic.store"))
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = true
        let original = Patient(firstName: "Originale", lastName: "Sintetico")
        let note = ClinicalNote(content: "Nota conservata", wellbeingScore: 5, patient: original)
        context.insert(original)
        context.insert(note)
        try context.save()
        let originalID = original.id
        let noteID = note.id
        original.firstName = "Modifica precedente"

        let payload = try samplePayload()
        XCTAssertThrowsError(try EncryptedBackupService.shared.restorePreparedBackup(
            .init(payload: payload), into: context, saveChanges: { throw InjectedFailure.diskFull }
        ))
        XCTAssertTrue(context.autosaveEnabled)
        XCTAssertFalse(context.hasChanges)

        // Read through a separate context: rolled-back data must also remain in the store.
        let verify = ModelContext(container)
        let patients = try verify.fetch(FetchDescriptor<Patient>())
        let notes = try verify.fetch(FetchDescriptor<ClinicalNote>())
        XCTAssertEqual(patients.map(\.id), [originalID])
        XCTAssertEqual(patients.first?.firstName, "Modifica precedente")
        XCTAssertEqual(notes.map(\.id), [noteID])
        XCTAssertEqual(notes.first?.readableContent, "Nota conservata")
    }

    func testMalformedKDFParametersAndAlgorithmsFailWithoutDerivation() throws {
        let data = try EncryptedBackupService.shared.encryptPayload(samplePayload(), password: password)
        let malformed: [(String, Any)] = [
            ("iterations", -1), ("iterations", Int.max), ("iterations", 0),
            ("keyLength", -1), ("keyLength", Int.max), ("keyLength", 16),
            ("algorithm", "unexpected"), ("saltBase64", "AA==")
        ]
        for (key, value) in malformed {
            let modified = try editedJSON(data) { object in
                var kdf = object["kdf"] as! [String: Any]
                kdf[key] = value
                object["kdf"] = kdf
            }
            XCTAssertThrowsError(try EncryptedBackupService.shared.decryptBackup(password: password, backupData: modified)) {
                XCTAssertEqual($0 as? EncryptedBackupError, .invalidEnvelope, key)
            }
        }
    }

    func testMetadataAndNonceTamperingAreRejected() throws {
        let data = try EncryptedBackupService.shared.encryptPayload(samplePayload(), password: password)
        let edits: [(inout [String: Any]) -> Void] = [
            { $0["createdAt"] = "2000-01-01T00:00:00Z" },
            { object in
                var metadata = object["metadata"] as! [String: Any]
                metadata["schemaVersion"] = 2
                object["metadata"] = metadata
            },
            { object in
                var metadata = object["metadata"] as! [String: Any]
                metadata["appVersion"] = "modified"
                object["metadata"] = metadata
            },
            { object in
                var cipher = object["cipher"] as! [String: Any]
                cipher["nonceBase64"] = Data(repeating: 0, count: 12).base64EncodedString()
                object["cipher"] = cipher
            }
        ]
        for edit in edits {
            let modified = try editedJSON(data, edit)
            XCTAssertThrowsError(try EncryptedBackupService.shared.decryptBackup(password: password, backupData: modified)) {
                XCTAssertEqual($0 as? EncryptedBackupError, .invalidEnvelope)
            }
        }
    }

    func testForgedMatchingAADStillFailsCryptographicAuthentication() throws {
        let data = try EncryptedBackupService.shared.encryptPayload(samplePayload(), password: password)
        let modified = try editedJSON(data) { object in
            var metadata = object["metadata"] as! [String: Any]
            metadata["appVersion"] = "forged"
            object["metadata"] = metadata
            var cipher = object["cipher"] as! [String: Any]
            let aadData = Data(base64Encoded: cipher["aadBase64"] as! String)!
            var aad = try! JSONSerialization.jsonObject(with: aadData) as! [String: Any]
            aad["metadata"] = metadata
            cipher["aadBase64"] = try! JSONSerialization.data(withJSONObject: aad, options: .sortedKeys).base64EncodedString()
            object["cipher"] = cipher
        }
        XCTAssertThrowsError(try EncryptedBackupService.shared.decryptBackup(password: password, backupData: modified)) {
            XCTAssertEqual($0 as? EncryptedBackupError, .invalidPassword)
        }
    }

    func testInvalidImportedRecordsAreRejectedBeforeReplacingExistingPatients() throws {
        let baseline = try JSONEncoder.chirone.encode(samplePayload())
        let mutations: [(EncryptedBackupError, (inout [String: Any]) -> Void)] = [
            (.invalidRecordData, { object in
                var patients = object["patients"] as! [[String: Any]]
                patients.append(patients[0])
                object["patients"] = patients
            }),
            (.invalidRecordData, { object in
                var notes = object["clinicalNotes"] as! [[String: Any]]
                notes[0]["patientID"] = UUID().uuidString
                object["clinicalNotes"] = notes
            }),
            (.invalidAssessmentData, { object in
                var rows = object["phq9Assessments"] as! [[String: Any]]
                rows[0]["scores"] = Array(repeating: 4, count: 9)
                object["phq9Assessments"] = rows
            }),
            (.invalidAssessmentData, { object in
                var rows = object["gad7Assessments"] as! [[String: Any]]
                rows[0]["scores"] = Array(repeating: 0, count: 6)
                object["gad7Assessments"] = rows
            }),
            (.invalidAssessmentData, { object in
                var rows = object["mdqAssessments"] as! [[String: Any]]
                rows[0]["part3RawValue"] = 99
                object["mdqAssessments"] = rows
            })
        ]
        let context = try makeContext()
        let original = Patient(firstName: "Conservare", lastName: "Sintetico")
        context.insert(original)
        try context.save()
        let originalID = original.id
        for (expected, mutation) in mutations {
            let payload = try JSONDecoder.chirone.decode(BackupPayload.self, from: editedJSON(baseline, mutation))
            XCTAssertThrowsError(try EncryptedBackupService.shared.restorePreparedBackup(.init(payload: payload), into: context)) {
                XCTAssertEqual($0 as? EncryptedBackupError, expected)
            }
            XCTAssertEqual(try context.fetch(FetchDescriptor<Patient>()).map(\.id), [originalID])
        }
    }

    func testAppendRestoreRejectsDuplicateRecords() throws {
        let context = try makeContext()
        let prepared = EncryptedBackupService.PreparedBackup(payload: try samplePayload())
        try EncryptedBackupService.shared.restorePreparedBackup(prepared, into: context)
        XCTAssertThrowsError(try EncryptedBackupService.shared.restorePreparedBackup(prepared, into: context, replaceExisting: false)) {
            XCTAssertEqual($0 as? EncryptedBackupError, .duplicateExistingRecords)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<Patient>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ClinicalNote>()).count, 1)
    }

    func testUnreadableEncryptedClinicalDataStopsExportInsteadOfLosingText() throws {
        let context = try makeContext()
        let patient = Patient(firstName: "Dato", lastName: "Sintetico")
        patient.encryptedPrimaryDiagnosis = "not-a-valid-ciphertext"
        context.insert(patient)
        try context.save()
        XCTAssertThrowsError(try EncryptedBackupService.shared.makePayload(from: context)) {
            XCTAssertEqual($0 as? EncryptedBackupError, .unreadableClinicalData)
        }
        XCTAssertEqual(patient.encryptedPrimaryDiagnosis, "not-a-valid-ciphertext")
    }

    func testCryptoRoundTripRunsOutsideMainThreadUsingOnlyValueSnapshots() async throws {
        let payload = try samplePayload()
        let service = EncryptedBackupService.shared
        let password = password
        let restored = try await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            let data = try service.encryptPayload(payload, password: password)
            let prepared = try service.decryptBackup(password: password, backupData: data)
            XCTAssertFalse(Thread.isMainThread)
            return prepared
        }.value
        try service.validatePayload(restored.payload)
        XCTAssertEqual(restored.payload.patients.map(\.id), payload.patients.map(\.id))
        XCTAssertEqual(restored.payload.clinicalNotes.first?.content, "Testo clinico sintetico")
    }

    private func samplePayload() throws -> BackupPayload {
        let context = try makeContext()
        let patient = Patient(firstName: "Importato", lastName: "Sintetico")
        let note = ClinicalNote(content: "Testo clinico sintetico", wellbeingScore: 5, patient: patient)
        context.insert(patient)
        context.insert(note)
        context.insert(PHQ9Assessment(scores: Array(repeating: 1, count: 9), patient: patient))
        context.insert(GAD7Assessment(scores: Array(repeating: 1, count: 7), patient: patient))
        context.insert(MDQAssessment(part1Answers: Array(repeating: 0, count: 13), patient: patient))
        try context.save()
        return try EncryptedBackupService.shared.makePayload(from: context)
    }

    private func editedJSON(_ data: Data, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
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
