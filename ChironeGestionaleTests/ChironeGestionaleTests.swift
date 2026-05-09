//
//  ChironeGestionaleTests.swift
//  ChironeGestionaleTests
//
//  Created by Peste on 21/04/2026.
//

import XCTest
import SwiftData
@testable import ChironeGestionale

final class ChironeGestionaleTests: XCTestCase {
    func testEncryptedBackupRoundTrip() throws {
        let schema = Schema([Patient.self, ClinicalNote.self, TherapyMedication.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let patient = Patient(
            firstName: "Mario",
            lastName: "Rossi",
            primaryDiagnosis: "",
            encryptedPrimaryDiagnosis: "diagnosi-cifrata",
            allergies: "",
            encryptedAllergies: "allergie-cifrate"
        )
        context.insert(patient)

        let note = ClinicalNote(
            content: "",
            encryptedContent: "nota-cifrata",
            wellbeingScore: 7,
            patient: patient
        )
        context.insert(note)
        patient.clinicalNotes.append(note)

        let medication = TherapyMedication(
            medicationName: "Olanzapina",
            dosage: "10mg",
            posology: "1 cp la sera",
            patient: patient
        )
        context.insert(medication)
        patient.therapyItems.append(medication)
        try context.save()

        let backupData = try EncryptedBackupService.shared.exportBackup(from: context, password: "PasswordMoltoSicura!")

        let restoreContainer = try ModelContainer(for: schema, configurations: [config])
        let restoreContext = ModelContext(restoreContainer)
        try EncryptedBackupService.shared.restoreBackup(
            into: restoreContext,
            password: "PasswordMoltoSicura!",
            backupData: backupData
        )

        let restoredPatients = try restoreContext.fetch(FetchDescriptor<Patient>())
        let restoredNotes = try restoreContext.fetch(FetchDescriptor<ClinicalNote>())
        let restoredMeds = try restoreContext.fetch(FetchDescriptor<TherapyMedication>())

        XCTAssertEqual(restoredPatients.count, 1)
        XCTAssertEqual(restoredNotes.count, 1)
        XCTAssertEqual(restoredMeds.count, 1)
        XCTAssertEqual(restoredPatients.first?.firstName, "Mario")
        XCTAssertEqual(restoredPatients.first?.encryptedPrimaryDiagnosis, "diagnosi-cifrata")
        XCTAssertEqual(restoredNotes.first?.encryptedContent, "nota-cifrata")
    }

    func testClinicalTimelineSortedUsesDeterministicTieBreaker() {
        let sameCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let sameUpdatedAt = Date(timeIntervalSince1970: 1_700_000_100)

        let noteA = ClinicalNote(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            content: "A",
            wellbeingScore: 5,
            createdAt: sameCreatedAt,
            updatedAt: sameUpdatedAt
        )
        let noteB = ClinicalNote(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            content: "B",
            wellbeingScore: 5,
            createdAt: sameCreatedAt,
            updatedAt: sameUpdatedAt
        )
        let noteC = ClinicalNote(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            content: "C",
            wellbeingScore: 5,
            createdAt: sameCreatedAt,
            updatedAt: sameUpdatedAt
        )

        let ordered = ClinicalNote.timelineSorted([noteA, noteC, noteB])
        XCTAssertEqual(ordered.map(\.id.uuidString), [
            "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
            "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        ])
    }

    func testClinicalTimelineSortedPrioritizesNewestDates() {
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = Date(timeIntervalSince1970: 1_700_000_500)

        let oldest = ClinicalNote(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            content: "old",
            wellbeingScore: 5,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        let newest = ClinicalNote(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            content: "new",
            wellbeingScore: 5,
            createdAt: newDate,
            updatedAt: newDate
        )

        let ordered = ClinicalNote.timelineSorted([oldest, newest])
        XCTAssertEqual(ordered.first?.id, newest.id)
        XCTAssertEqual(ordered.last?.id, oldest.id)
    }

    func testEncryptedBackupEnvelopeMetadataAndCountsAreConsistent() throws {
        let schema = Schema([Patient.self, ClinicalNote.self, TherapyMedication.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let patientA = Patient(firstName: "Anna", lastName: "Bianchi")
        let patientB = Patient(firstName: "Luca", lastName: "Verdi")
        context.insert(patientA)
        context.insert(patientB)

        let noteA = ClinicalNote(content: "Nota A", wellbeingScore: 8, patient: patientA)
        let noteB = ClinicalNote(content: "Nota B", wellbeingScore: 6, patient: patientB)
        context.insert(noteA)
        context.insert(noteB)
        patientA.clinicalNotes.append(noteA)
        patientB.clinicalNotes.append(noteB)

        let medA = TherapyMedication(medicationName: "Farmaco A", dosage: "5mg", posology: "1/die", patient: patientA)
        let medB = TherapyMedication(medicationName: "Farmaco B", dosage: "10mg", posology: "2/die", patient: patientB)
        context.insert(medA)
        context.insert(medB)
        patientA.therapyItems.append(medA)
        patientB.therapyItems.append(medB)
        try context.save()

        let backupData = try EncryptedBackupService.shared.exportBackup(from: context, password: "PasswordMoltoSicura!")
        let envelope = try JSONDecoder.chirone.decode(EncryptedBackupEnvelope.self, from: backupData)

        XCTAssertEqual(envelope.format, "chirone-backup")
        XCTAssertEqual(envelope.version, 1)
        XCTAssertEqual(envelope.metadata.schemaVersion, 1)
        XCTAssertEqual(envelope.metadata.recordCounts.patients, 2)
        XCTAssertEqual(envelope.metadata.recordCounts.clinicalNotes, 2)
        XCTAssertEqual(envelope.metadata.recordCounts.therapyItems, 2)
    }

    func testEncryptedBackupRestoreRejectsUnsupportedSchemaVersion() throws {
        let schema = Schema([Patient.self, ClinicalNote.self, TherapyMedication.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        context.insert(Patient(firstName: "Mario", lastName: "Rossi"))
        try context.save()

        let backupData = try EncryptedBackupService.shared.exportBackup(from: context, password: "PasswordMoltoSicura!")
        var envelope = try JSONDecoder.chirone.decode(EncryptedBackupEnvelope.self, from: backupData)
        envelope = EncryptedBackupEnvelope(
            format: envelope.format,
            version: envelope.version,
            createdAt: envelope.createdAt,
            cipher: envelope.cipher,
            kdf: envelope.kdf,
            wrappedDEKBase64: envelope.wrappedDEKBase64,
            wrappedDEKNonceBase64: envelope.wrappedDEKNonceBase64,
            payloadBase64: envelope.payloadBase64,
            metadata: .init(
                appVersion: envelope.metadata.appVersion,
                schemaVersion: envelope.metadata.schemaVersion + 1,
                recordCounts: envelope.metadata.recordCounts
            )
        )
        let tamperedData = try JSONEncoder.chirone.encode(envelope)

        let restoreContainer = try ModelContainer(for: schema, configurations: [config])
        let restoreContext = ModelContext(restoreContainer)

        XCTAssertThrowsError(
            try EncryptedBackupService.shared.restoreBackup(
                into: restoreContext,
                password: "PasswordMoltoSicura!",
                backupData: tamperedData
            )
        ) { error in
            guard let backupError = error as? EncryptedBackupError else {
                return XCTFail("Expected EncryptedBackupError, got \(error)")
            }
            XCTAssertEqual(backupError, .unsupportedSchemaVersion)
        }
    }

    func testEncryptedBackupRestoreRejectsMismatchedRecordCounts() throws {
        let schema = Schema([Patient.self, ClinicalNote.self, TherapyMedication.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        context.insert(Patient(firstName: "Mario", lastName: "Rossi"))
        try context.save()

        let backupData = try EncryptedBackupService.shared.exportBackup(from: context, password: "PasswordMoltoSicura!")
        var envelope = try JSONDecoder.chirone.decode(EncryptedBackupEnvelope.self, from: backupData)
        envelope = EncryptedBackupEnvelope(
            format: envelope.format,
            version: envelope.version,
            createdAt: envelope.createdAt,
            cipher: envelope.cipher,
            kdf: envelope.kdf,
            wrappedDEKBase64: envelope.wrappedDEKBase64,
            wrappedDEKNonceBase64: envelope.wrappedDEKNonceBase64,
            payloadBase64: envelope.payloadBase64,
            metadata: .init(
                appVersion: envelope.metadata.appVersion,
                schemaVersion: envelope.metadata.schemaVersion,
                recordCounts: .init(
                    patients: envelope.metadata.recordCounts.patients + 1,
                    clinicalNotes: envelope.metadata.recordCounts.clinicalNotes,
                    therapyItems: envelope.metadata.recordCounts.therapyItems
                )
            )
        )
        let tamperedData = try JSONEncoder.chirone.encode(envelope)

        let restoreContainer = try ModelContainer(for: schema, configurations: [config])
        let restoreContext = ModelContext(restoreContainer)

        XCTAssertThrowsError(
            try EncryptedBackupService.shared.restoreBackup(
                into: restoreContext,
                password: "PasswordMoltoSicura!",
                backupData: tamperedData
            )
        ) { error in
            guard let backupError = error as? EncryptedBackupError else {
                return XCTFail("Expected EncryptedBackupError, got \(error)")
            }
            XCTAssertEqual(backupError, .invalidEnvelope)
        }
    }

    @MainActor
    func testAuditTrailReadRecordsReturnsRecentlyLoggedEvent() {
        let uniqueMarker = UUID().uuidString.lowercased()
        let since = Date().addingTimeInterval(-10)

        AuditTrailService.shared.log(
            .commandPaletteActionExecuted,
            metadata: [
                "action": "test_audit_iso8601_read",
                "marker": uniqueMarker,
                "latency_bucket": "<750ms",
                "latency_ms": "123"
            ]
        )

        let records = AuditTrailService.shared.readRecords(
            since: since,
            event: .commandPaletteActionExecuted,
            limit: 500
        )

        let match = records.first { $0.metadata["marker"] == uniqueMarker }
        XCTAssertNotNil(match, "Expected to find the audit event just logged.")
        XCTAssertEqual(match?.event, AuditEvent.commandPaletteActionExecuted.rawValue)
    }
}
