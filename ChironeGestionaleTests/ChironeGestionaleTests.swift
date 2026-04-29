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
}
