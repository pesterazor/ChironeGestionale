//
//  ChironeGestionaleTests.swift
//  ChironeGestionaleTests
//
//  Created by Peste on 21/04/2026.
//

import XCTest
import SwiftData
import PDFKit
@testable import ChironeGestionale

final class ChironeGestionaleTests: XCTestCase {
    func testEncryptedBackupRoundTrip() throws {
        let schema = Schema([
            Patient.self,
            ClinicalNote.self,
            TherapyMedication.self,
            PHQ9Assessment.self,
            GAD7Assessment.self,
            MDQAssessment.self,
            BeckAssessment.self,
            MADRSAssessment.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let patient = Patient(
            firstName: "Mario",
            lastName: "Rossi"
        )
        patient.protectPrimaryDiagnosis("Disturbo bipolare I")
        patient.protectSecondaryDiagnosis("Disturbo d'ansia generalizzato")
        patient.protectMedicalComorbidities("Ipertensione")
        patient.protectRemotePsychiatricHistory("Episodio depressivo 2019")
        patient.protectAllergies("Penicillina")
        context.insert(patient)

        let note = ClinicalNote(wellbeingScore: 7, patient: patient)
        note.protectContent("Paziente stabile, tono dell'umore eutimico.")
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

        let phq9 = PHQ9Assessment(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            scores: [1, 2, 1, 0, 1, 2, 1, 0, 0],
            patient: patient
        )
        context.insert(phq9)
        patient.phq9Assessments.append(phq9)

        let gad7 = GAD7Assessment(
            date: Date(timeIntervalSince1970: 1_750_000_500),
            scores: [2, 1, 2, 1, 0, 1, 2],
            patient: patient
        )
        context.insert(gad7)
        patient.gad7Assessments.append(gad7)

        let mdq = MDQAssessment(
            date: Date(timeIntervalSince1970: 1_750_001_000),
            part1Answers: [1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
            part2Answer: true,
            part3RawValue: 2,
            patient: patient
        )
        context.insert(mdq)
        patient.mdqAssessments.append(mdq)

        let bai = BeckAssessment(scale: .bai, answerIndices: Array(repeating: 2, count: 21), patient: patient)
        var bdiAnswers = Array(repeating: 0, count: 21)
        bdiAnswers[15] = 4 // 2b, sonno ridotto.
        bdiAnswers[17] = 5 // 3a, appetito assente.
        let bdi = BeckAssessment(scale: .bdiII, answerIndices: bdiAnswers, patient: patient)
        context.insert(bai)
        context.insert(bdi)
        patient.beckAssessments = [bai, bdi]
        let madrs = MADRSAssessment(scores: [1, 2, 3, 4, 5, 6, 0, 1, 2, 1], raterName: "Clinico di prova", patient: patient)
        context.insert(madrs)
        patient.madrsAssessments = [madrs]
        let correctedDate = Date(timeIntervalSince1970: 1_760_000_000)
        try AssessmentDateEditing.update(phq9, to: correctedDate) { try context.save() }
        try AssessmentDateEditing.update(gad7, to: correctedDate) { try context.save() }
        try AssessmentDateEditing.update(mdq, to: correctedDate) { try context.save() }
        try AssessmentDateEditing.update(bai, to: correctedDate) { try context.save() }
        try AssessmentDateEditing.update(bdi, to: correctedDate) { try context.save() }
        try AssessmentDateEditing.update(madrs, to: correctedDate) { try context.save() }

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
        let restoredPHQ9 = try restoreContext.fetch(FetchDescriptor<PHQ9Assessment>())
        let restoredGAD7 = try restoreContext.fetch(FetchDescriptor<GAD7Assessment>())
        let restoredMDQ = try restoreContext.fetch(FetchDescriptor<MDQAssessment>())
        let restoredBeck = try restoreContext.fetch(FetchDescriptor<BeckAssessment>())
        let restoredMADRS = try restoreContext.fetch(FetchDescriptor<MADRSAssessment>())

        XCTAssertEqual(restoredPatients.count, 1)
        XCTAssertEqual(restoredNotes.count, 1)
        XCTAssertEqual(restoredMeds.count, 1)
        XCTAssertEqual(restoredPHQ9.count, 1)
        XCTAssertEqual(restoredGAD7.count, 1)
        XCTAssertEqual(restoredMDQ.count, 1)
        XCTAssertEqual(restoredBeck.count, 2)
        XCTAssertEqual(restoredMADRS.count, 1)
        XCTAssertEqual(restoredMADRS.first?.id, madrs.id)
        XCTAssertEqual(restoredMADRS.first?.scores, madrs.scores)
        XCTAssertEqual(restoredMADRS.first?.totalScore, 25)
        XCTAssertEqual(restoredMADRS.first?.raterName, "Clinico di prova")
        XCTAssertEqual(restoredMADRS.first?.patient?.id, patient.id)
        XCTAssertEqual(restoredPHQ9.first?.date, correctedDate)
        XCTAssertEqual(restoredGAD7.first?.date, correctedDate)
        XCTAssertEqual(restoredMDQ.first?.date, correctedDate)
        XCTAssertTrue(restoredBeck.allSatisfy { $0.date == correctedDate })
        XCTAssertEqual(restoredMADRS.first?.date, correctedDate)
        XCTAssertEqual(restoredBeck.first { $0.scale == .bai }?.totalScore, 42)
        XCTAssertEqual(restoredBeck.first { $0.scale == .bdiII }?.answerIndices, bdiAnswers)
        XCTAssertEqual(restoredBeck.first { $0.scale == .bdiII }?.totalScore, 5)
        XCTAssertEqual(Set(restoredBeck.map(\.id)), Set([bai.id, bdi.id]))
        XCTAssertTrue(restoredBeck.allSatisfy { $0.patient?.id == patient.id })

        let restored = try XCTUnwrap(restoredPatients.first)
        XCTAssertEqual(restored.firstName, "Mario")
        XCTAssertEqual(restored.beckAssessments.count, 2)
        XCTAssertEqual(restored.madrsAssessments.count, 1)
        // I campi clinici devono essere LEGGIBILI (ricifrati con la chiave locale).
        XCTAssertEqual(restored.readablePrimaryDiagnosis, "Disturbo bipolare I")
        XCTAssertEqual(restored.readableSecondaryDiagnosis, "Disturbo d'ansia generalizzato")
        XCTAssertEqual(restored.readableMedicalComorbidities, "Ipertensione")
        XCTAssertEqual(restored.readableRemotePsychiatricHistory, "Episodio depressivo 2019")
        XCTAssertEqual(restored.readableAllergies, "Penicillina")
        // Conferma che il dato in chiaro sul disco resta vuoto (è cifrato).
        XCTAssertEqual(restored.primaryDiagnosis, "")
        XCTAssertNotNil(restored.encryptedPrimaryDiagnosis)

        let restoredNote = try XCTUnwrap(restoredNotes.first)
        XCTAssertEqual(restoredNote.readableContent, "Paziente stabile, tono dell'umore eutimico.")
        XCTAssertEqual(restoredNote.content, "")
        XCTAssertNotNil(restoredNote.encryptedContent)

        XCTAssertEqual(restoredPHQ9.first?.scores, [1, 2, 1, 0, 1, 2, 1, 0, 0])
        XCTAssertEqual(restoredGAD7.first?.scores, [2, 1, 2, 1, 0, 1, 2])
        XCTAssertEqual(restoredMDQ.first?.part1Answers, [1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0])
        XCTAssertEqual(restoredMDQ.first?.part2Answer, true)
        XCTAssertEqual(restoredMDQ.first?.part3RawValue, 2)
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

    @MainActor
    func testEncryptedBackupEnvelopeMetadataAndCountsAreConsistent() throws {
        let schema = Schema([
            Patient.self,
            ClinicalNote.self,
            TherapyMedication.self,
            PHQ9Assessment.self,
            GAD7Assessment.self,
            MDQAssessment.self,
            BeckAssessment.self,
            MADRSAssessment.self,
        ])
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

        let phq = PHQ9Assessment(patient: patientA)
        context.insert(phq)
        patientA.phq9Assessments.append(phq)

        try context.save()

        let backupData = try EncryptedBackupService.shared.exportBackup(from: context, password: "PasswordMoltoSicura!")
        let envelope = try JSONDecoder.chirone.decode(EncryptedBackupEnvelope.self, from: backupData)

        XCTAssertEqual(envelope.format, "chirone-backup")
        XCTAssertEqual(envelope.version, 1)
        XCTAssertEqual(envelope.metadata.schemaVersion, 5)
        XCTAssertEqual(envelope.metadata.recordCounts.patients, 2)
        XCTAssertEqual(envelope.metadata.recordCounts.clinicalNotes, 2)
        XCTAssertEqual(envelope.metadata.recordCounts.therapyItems, 2)
        XCTAssertEqual(envelope.metadata.recordCounts.phq9Assessments, 1)
        XCTAssertEqual(envelope.metadata.recordCounts.gad7Assessments, 0)
        XCTAssertEqual(envelope.metadata.recordCounts.mdqAssessments, 0)
        XCTAssertEqual(envelope.metadata.recordCounts.beckAssessments, 0)
        XCTAssertEqual(envelope.metadata.recordCounts.madrsAssessments, 0)
    }

    @MainActor
    func testEncryptedBackupRestoreRejectsUnsupportedSchemaVersion() throws {
        let schema = Schema([
            Patient.self,
            ClinicalNote.self,
            TherapyMedication.self,
            PHQ9Assessment.self,
            GAD7Assessment.self,
            MDQAssessment.self,
            BeckAssessment.self,
            MADRSAssessment.self,
        ])
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

    @MainActor
    func testEncryptedBackupRestoreRejectsMismatchedRecordCounts() throws {
        let schema = Schema([
            Patient.self,
            ClinicalNote.self,
            TherapyMedication.self,
            PHQ9Assessment.self,
            GAD7Assessment.self,
            MDQAssessment.self,
            BeckAssessment.self,
            MADRSAssessment.self,
        ])
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
                    therapyItems: envelope.metadata.recordCounts.therapyItems,
                    phq9Assessments: envelope.metadata.recordCounts.phq9Assessments,
                    gad7Assessments: envelope.metadata.recordCounts.gad7Assessments,
                    mdqAssessments: envelope.metadata.recordCounts.mdqAssessments,
                    beckAssessments: envelope.metadata.recordCounts.beckAssessments,
                    madrsAssessments: envelope.metadata.recordCounts.madrsAssessments
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

    @MainActor
    func testClinicalReportPreservesLongHistoryAndNoteAcrossPDFPages() throws {
        let history = "ANAMNESI-INIZIO-ÀÈÌÒÙ\n" +
            String(repeating: "Storia clinica completa senza abbreviazioni. ", count: 145) +
            "\nANAMNESI-FINE-Ω"
        let noteText = "NOTA-INIZIO\n" +
            String(repeating: "Osservazione clinica descrittiva mantenuta integralmente. ", count: 120) +
            "\nNOTA-FINE-✓"

        let patient = Patient(
            firstName: "Giulia",
            lastName: "Rossi",
            dateOfBirth: Date(timeIntervalSince1970: 500_000_000),
            placeOfBirth: "Firenze",
            primaryDiagnosis: "Disturbo depressivo maggiore",
            medicalComorbidities: "Ipertensione arteriosa",
            remotePsychiatricHistory: history,
            allergies: "Penicillina"
        )
        let note = ClinicalNote(
            content: noteText,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            patient: patient
        )
        patient.clinicalNotes = [note]
        patient.therapyItems = [
            TherapyMedication(
                medicationName: "Sertralina",
                dosage: "100 mg",
                posology: "una compressa al mattino",
                patient: patient
            )
        ]

        let draft = PatientReportService.shared.makeDraft(
            for: patient,
            generatedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
        let historySection = try XCTUnwrap(draft.sections.first { $0.kind == .remoteHistory })
        let currentSection = try XCTUnwrap(draft.sections.first { $0.kind == .currentClinicalStatus })
        let demographicsSection = try XCTUnwrap(draft.sections.first { $0.kind == .demographics })
        XCTAssertEqual(historySection.text, history)
        XCTAssertLessThanOrEqual(demographicsSection.text.components(separatedBy: "\n").count, 2)
        XCTAssertTrue(demographicsSection.text.contains(" · "))
        XCTAssertTrue(currentSection.text.contains("NOTA-INIZIO"))
        XCTAssertTrue(currentSection.text.contains("NOTA-FINE-✓"))
        XCTAssertFalse(historySection.text.contains("…"))

        let profile = ProfessionalReportProfile(
            fullName: "Dr.ssa Laura Bianchi",
            qualification: "Medico Chirurgo — Specialista in Psichiatria",
            registration: "Ordine dei Medici di Firenze n. 12345",
            address: "Via Roma 1, Firenze",
            contacts: "studio@example.it"
        )
        let document = try PatientReportService.shared.render(draft: draft, profile: profile)
        let extracted = try XCTUnwrap(document.string)

        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue(extracted.contains("ANAMNESI-INIZIO-ÀÈÌÒÙ"))
        XCTAssertTrue(extracted.contains("ANAMNESI-FINE-Ω"))
        XCTAssertTrue(extracted.contains("NOTA-INIZIO"))
        XCTAssertTrue(extracted.contains("NOTA-FINE-✓"))
        XCTAssertFalse(extracted.contains("Chirone Gestionale"))
        XCTAssertEqual(extracted.components(separatedBy: "Dr.ssa Laura Bianchi").count - 1, 2)
        XCTAssertEqual(
            extracted.components(separatedBy: "Medico Chirurgo — Specialista in Psichiatria").count - 1,
            1
        )
        XCTAssertEqual(extracted.components(separatedBy: "Ordine dei Medici di Firenze n. 12345").count - 1, 1)
        let lastPageText = try XCTUnwrap(document.page(at: document.pageCount - 1)?.string)
        XCTAssertTrue(lastPageText.contains("Sertralina"))
        XCTAssertTrue(lastPageText.contains("Dr.ssa Laura Bianchi"))
    }

    @MainActor
    func testClinicalReportOmitsMissingPlaceholdersAndKeepsSecondaryOnlyDiagnosis() throws {
        let patient = Patient(
            firstName: "Ada",
            lastName: "Bianchi",
            secondaryDiagnosis: "Disturbo d'ansia generalizzato"
        )
        let draft = PatientReportService.shared.makeDraft(for: patient)
        let diagnosis = try XCTUnwrap(draft.sections.first { $0.kind == .diagnoses })
        let generatedText = draft.sections.map(\.text).joined(separator: "\n")

        XCTAssertTrue(diagnosis.isIncluded)
        XCTAssertEqual(diagnosis.text, "Diagnosi secondaria: Disturbo d'ansia generalizzato")
        XCTAssertFalse(generatedText.localizedCaseInsensitiveContains("non disponibile"))
        XCTAssertFalse(generatedText.contains("Chirone Gestionale"))
        XCTAssertTrue(draft.issues.contains { $0.id == "patient.birthDate" })
        XCTAssertTrue(draft.issues.contains { $0.id == "clinical.currentStatus" })

        let document = try PatientReportService.shared.render(
            draft: draft,
            profile: ProfessionalReportProfile(fullName: "", qualification: "", registration: "", address: "", contacts: "")
        )
        let extracted = try XCTUnwrap(document.string)
        XCTAssertTrue(extracted.contains("Diagnosi secondaria"))
        XCTAssertFalse(extracted.localizedCaseInsensitiveContains("non disponibile"))
        XCTAssertFalse(extracted.contains("Chirone Gestionale"))
    }

    @MainActor
    func testClinicalReportExcludesAutomaticUpdatesAndRespectsRecentNotesCount() throws {
        let patient = Patient(firstName: "Marco", lastName: "Neri")
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let automatic = ClinicalNote(
            content: "Aggiornamento terapia farmacologica: variazione automatica",
            createdAt: base.addingTimeInterval(500),
            patient: patient
        )
        let current = ClinicalNote(content: "QUADRO-ATTUALE", createdAt: base.addingTimeInterval(400), patient: patient)
        let priorTwo = ClinicalNote(content: "NOTA-PRECEDENTE-2", createdAt: base.addingTimeInterval(300), patient: patient)
        let priorOne = ClinicalNote(content: "NOTA-PRECEDENTE-1", createdAt: base.addingTimeInterval(200), patient: patient)
        let tooOld = ClinicalNote(content: "NOTA-TROPPO-VECCHIA", createdAt: base.addingTimeInterval(100), patient: patient)
        patient.clinicalNotes = [tooOld, automatic, priorOne, current, priorTwo]

        let draft = PatientReportService.shared.makeDraft(
            for: patient,
            options: ReportOptions(recentNotesCount: 2, includeRecentNotes: true)
        )
        let currentSection = try XCTUnwrap(draft.sections.first { $0.kind == .currentClinicalStatus })
        let recentSection = try XCTUnwrap(draft.sections.first { $0.kind == .recentNotes })

        XCTAssertTrue(currentSection.text.contains("QUADRO-ATTUALE"))
        XCTAssertFalse(currentSection.text.contains("Aggiornamento terapia farmacologica"))
        XCTAssertTrue(recentSection.isIncluded)
        XCTAssertTrue(recentSection.text.contains("NOTA-PRECEDENTE-2"))
        XCTAssertTrue(recentSection.text.contains("NOTA-PRECEDENTE-1"))
        XCTAssertFalse(recentSection.text.contains("NOTA-TROPPO-VECCHIA"))
        XCTAssertFalse(recentSection.text.contains("QUADRO-ATTUALE"))
    }

    @MainActor
    func testClinicalReportProvidesOptionalFinalConclusions() throws {
        let patient = Patient(firstName: "Luca", lastName: "Verdi")
        var draft = PatientReportService.shared.makeDraft(for: patient)
        let conclusionsIndex = try XCTUnwrap(
            draft.sections.firstIndex { $0.kind == .conclusions }
        )

        XCTAssertEqual(conclusionsIndex, draft.sections.index(before: draft.sections.endIndex))
        XCTAssertEqual(draft.sections[conclusionsIndex].title, "Conclusioni")
        XCTAssertEqual(draft.sections[conclusionsIndex].source, .clinician)
        XCTAssertFalse(draft.sections[conclusionsIndex].isIncluded)
        XCTAssertTrue(draft.sections[conclusionsIndex].text.isEmpty)

        draft.sections[conclusionsIndex].text = "Si propone prosecuzione del monitoraggio clinico."
        draft.sections[conclusionsIndex].isIncluded = true
        let document = try PatientReportService.shared.render(
            draft: draft,
            profile: ProfessionalReportProfile(
                fullName: "Dott. Mario Rossi",
                qualification: "Medico specialista in Psichiatria",
                registration: "Ordine dei Medici n. 1234",
                address: "",
                contacts: ""
            )
        )

        let extracted = try XCTUnwrap(document.string)
        XCTAssertTrue(extracted.contains("Conclusioni"))
        XCTAssertTrue(extracted.contains("Si propone prosecuzione del monitoraggio clinico."))
    }

    @MainActor
    func testPrescriptionPreservesLongMedicationTextAndOptionalDirections() throws {
        let longPosology = "POSOLOGIA-INIZIO-ÀÈÌÒÙ\n" +
            String(repeating: "Indicazione terapeutica completa senza abbreviazioni o troncamenti. ", count: 150) +
            "\nPOSOLOGIA-FINE-Ω✓"
        let patient = Patient(
            firstName: "Elena",
            lastName: "Rossi",
            dateOfBirth: Date(timeIntervalSince1970: 600_000_000),
            taxCode: "RSSLNE89A41H501X",
            placeOfBirth: "Roma",
            birthProvince: "RM"
        )
        let included = TherapyMedication(
            medicationName: "Sertralina",
            dosage: "100 mg",
            posology: longPosology,
            patient: patient
        )
        let excluded = TherapyMedication(
            medicationName: "FARMACO-DA-ESCLUDERE",
            dosage: "10 mg",
            posology: "una compressa",
            patient: patient
        )
        let inactive = TherapyMedication(
            medicationName: "FARMACO-INATTIVO",
            dosage: "20 mg",
            posology: "non riportare",
            isActive: false,
            patient: patient
        )
        patient.therapyItems = [included, excluded, inactive]

        var draft = try PatientPrescriptionService.shared.makeDraft(
            for: patient,
            generatedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
        XCTAssertEqual(draft.patientIdentification.components(separatedBy: "\n").count, 2)
        XCTAssertTrue(draft.patientIdentification.contains(" · "))
        XCTAssertEqual(draft.medications.count, 2)
        XCTAssertFalse(draft.medications.contains { $0.text.contains("FARMACO-INATTIVO") })
        XCTAssertTrue(draft.medications.contains { $0.text.contains("POSOLOGIA-INIZIO-ÀÈÌÒÙ") })
        XCTAssertTrue(draft.medications.contains { $0.text.contains("POSOLOGIA-FINE-Ω✓") })

        let excludedIndex = try XCTUnwrap(
            draft.medications.firstIndex { $0.text.contains("FARMACO-DA-ESCLUDERE") }
        )
        draft.medications[excludedIndex].isIncluded = false
        draft.additionalDirections = "INDICAZIONI-INIZIO\nControllo clinico programmato.\nINDICAZIONI-FINE"
        draft.includesAdditionalDirections = true

        let profile = ProfessionalReportProfile(
            fullName: "Dott. Paolo Bianchi",
            qualification: "Medico specialista in Psichiatria",
            registration: "Ordine dei Medici di Roma n. 9876",
            address: "Via Salute 1, Roma",
            contacts: "studio@example.it"
        )
        let document = try PatientPrescriptionService.shared.render(
            draft: draft,
            profile: profile
        )
        let extracted = try XCTUnwrap(document.string)

        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue(extracted.contains("POSOLOGIA-INIZIO-ÀÈÌÒÙ"))
        XCTAssertTrue(extracted.contains("POSOLOGIA-FINE-Ω✓"))
        XCTAssertTrue(extracted.contains("INDICAZIONI-INIZIO"))
        XCTAssertTrue(extracted.contains("INDICAZIONI-FINE"))
        XCTAssertFalse(extracted.contains("FARMACO-DA-ESCLUDERE"))
        XCTAssertFalse(extracted.contains("FARMACO-INATTIVO"))
        XCTAssertFalse(extracted.contains("Chirone Gestionale"))
        XCTAssertFalse(extracted.localizedCaseInsensitiveContains("non disponibile"))
        XCTAssertEqual(extracted.components(separatedBy: profile.fullName).count - 1, 2)
        XCTAssertEqual(extracted.components(separatedBy: profile.qualification).count - 1, 1)
        XCTAssertEqual(extracted.components(separatedBy: profile.registration).count - 1, 1)
        let lastPageText = try XCTUnwrap(document.page(at: document.pageCount - 1)?.string)
        XCTAssertTrue(lastPageText.contains("INDICAZIONI-FINE"))
        XCTAssertTrue(lastPageText.contains(profile.fullName))
        XCTAssertEqual(
            document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
            "Prescrizione medica"
        )
    }

    @MainActor
    func testPrescriptionReportsMissingDataAndRejectsEmptySelection() throws {
        let patient = Patient(firstName: "Ada", lastName: "Neri")
        patient.therapyItems = [
            TherapyMedication(
                medicationName: "Quetiapina",
                dosage: "25 mg",
                posology: "una compressa la sera",
                patient: patient
            )
        ]

        var draft = try PatientPrescriptionService.shared.makeDraft(for: patient)
        XCTAssertTrue(draft.issues.contains { $0.id == "prescription.birthDate" })
        XCTAssertTrue(draft.issues.contains { $0.id == "prescription.birthPlace" })
        XCTAssertTrue(draft.issues.contains { $0.id == "prescription.taxCode" })
        XCTAssertFalse(draft.patientIdentification.localizedCaseInsensitiveContains("non disponibile"))

        draft.medications[0].isIncluded = false
        XCTAssertThrowsError(
            try PatientPrescriptionService.shared.render(
                draft: draft,
                profile: ProfessionalReportProfile(fullName: "", qualification: "", registration: "", address: "", contacts: "")
            )
        ) { error in
            XCTAssertEqual(error as? PatientPrescriptionServiceError, .noSelectedMedications)
        }

        XCTAssertThrowsError(try PatientPrescriptionService.shared.makeDraft(for: Patient())) { error in
            XCTAssertEqual(error as? PatientPrescriptionServiceError, .noActiveTherapy)
        }
    }
}
