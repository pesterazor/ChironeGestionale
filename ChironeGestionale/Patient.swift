//
//  Patient.swift
//  ChironeGestionale
//
//  Created by Peste on 21/04/2026.
//

import Foundation
import SwiftData

@Model
final class Patient {
    var id: UUID

    // MARK: - Identificazione essenziale
    var firstName: String
    var lastName: String
    var dateOfBirth: Date?
    var gender: String?
    var taxCode: String

    // MARK: - Contatti e anagrafica estesa
    var placeOfBirth: String
    var birthProvince: String?
    var residence: String
    var residenceAddress: String?
    var residenceCity: String?
    var residenceProvince: String?
    var phoneNumber: String
    var emergencyContact: String
    var generalPractitioner: String
    var privacyConsentSigned: Bool

    // MARK: - Contesto clinico-amministrativo
    var referenceCSM: String
    var referringClinician: String
    var primaryDiagnosis: String
    var secondaryDiagnosis: String
    var medicalHistory: String
    var medicalComorbidities: String?
    var remotePsychiatricHistory: String?
    var allergies: String
    var exemptions: String

    // MARK: - Terapia attuale (testuale legacy per MVP)
    var currentTherapySummary: String

    // MARK: - Funzionalità d'organo (verde/giallo/rosso)
    var heartFunctionStatus: String?
    var liverFunctionStatus: String?
    var kidneyFunctionStatus: String?

    // MARK: - Relazioni
    @Relationship(deleteRule: .cascade, inverse: \TherapyMedication.patient)
    var therapyItems: [TherapyMedication]

    @Relationship(deleteRule: .cascade, inverse: \ClinicalNote.patient)
    var clinicalNotes: [ClinicalNote]

    // MARK: - Metadati
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        firstName: String = "",
        lastName: String = "",
        dateOfBirth: Date? = nil,
        gender: String? = nil,
        taxCode: String = "",
        placeOfBirth: String = "",
        birthProvince: String? = nil,
        residence: String = "",
        residenceAddress: String? = nil,
        residenceCity: String? = nil,
        residenceProvince: String? = nil,
        phoneNumber: String = "",
        emergencyContact: String = "",
        generalPractitioner: String = "",
        privacyConsentSigned: Bool = false,
        referenceCSM: String = "",
        referringClinician: String = "",
        primaryDiagnosis: String = "",
        secondaryDiagnosis: String = "",
        medicalHistory: String = "",
        medicalComorbidities: String? = nil,
        remotePsychiatricHistory: String? = nil,
        allergies: String = "",
        exemptions: String = "",
        currentTherapySummary: String = "",
        heartFunctionStatus: String? = nil,
        liverFunctionStatus: String? = nil,
        kidneyFunctionStatus: String? = nil,
        therapyItems: [TherapyMedication] = [],
        clinicalNotes: [ClinicalNote] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.taxCode = taxCode
        self.placeOfBirth = placeOfBirth
        self.birthProvince = birthProvince
        self.residence = residence
        self.residenceAddress = residenceAddress
        self.residenceCity = residenceCity
        self.residenceProvince = residenceProvince
        self.phoneNumber = phoneNumber
        self.emergencyContact = emergencyContact
        self.generalPractitioner = generalPractitioner
        self.privacyConsentSigned = privacyConsentSigned
        self.referenceCSM = referenceCSM
        self.referringClinician = referringClinician
        self.primaryDiagnosis = primaryDiagnosis
        self.secondaryDiagnosis = secondaryDiagnosis
        self.medicalHistory = medicalHistory
        self.medicalComorbidities = medicalComorbidities
        self.remotePsychiatricHistory = remotePsychiatricHistory
        self.allergies = allergies
        self.exemptions = exemptions
        self.currentTherapySummary = currentTherapySummary
        self.heartFunctionStatus = heartFunctionStatus
        self.liverFunctionStatus = liverFunctionStatus
        self.kidneyFunctionStatus = kidneyFunctionStatus
        self.therapyItems = therapyItems
        self.clinicalNotes = clinicalNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Patient {
    private static let italianShortDateStyle = Date.FormatStyle
        .dateTime
        .day()
        .month(.abbreviated)
        .locale(Locale(identifier: "it_IT"))

    var fullName: String {
        let composed = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return composed.isEmpty ? "Paziente senza nome" : composed
    }

    var displayTitle: String {
        if !lastName.isEmpty || !firstName.isEmpty {
            return "\(lastName) \(firstName)".trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !taxCode.isEmpty {
            return taxCode
        }
        return "Nuovo paziente"
    }

    var searchableTokens: [String] {
        [
            firstName,
            lastName,
            taxCode,
            fullName,
            displayTitle,
            phoneNumber
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
    }

    var hasRequiredDemographics: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        dateOfBirth != nil
    }

    var lastVisitDate: Date? {
        clinicalNotes
            .map(\.createdAt)
            .max()
    }

    var lastVisitDateLabel: String? {
        guard let lastVisitDate else { return nil }
        return lastVisitDate.formatted(Self.italianShortDateStyle).lowercased()
    }
}
