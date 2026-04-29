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
    var encryptedPrimaryDiagnosis: String?
    var secondaryDiagnosis: String
    var encryptedSecondaryDiagnosis: String?
    var medicalHistory: String
    var medicalComorbidities: String?
    var encryptedMedicalComorbidities: String?
    var remotePsychiatricHistory: String?
    var encryptedRemotePsychiatricHistory: String?
    var allergies: String
    var encryptedAllergies: String?
    var exemptions: String

    // MARK: - Terapia attuale (testuale legacy per MVP)
    var currentTherapySummary: String

    // MARK: - Funzionalità d'organo (verde/giallo/rosso)
    var heartFunctionStatus: String?
    var liverFunctionStatus: String?
    var kidneyFunctionStatus: String?

    // MARK: - Esami ematochimici (payload JSON tabellare)
    var bloodTestsTableJSON: String?

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
        encryptedPrimaryDiagnosis: String? = nil,
        secondaryDiagnosis: String = "",
        encryptedSecondaryDiagnosis: String? = nil,
        medicalHistory: String = "",
        medicalComorbidities: String? = nil,
        encryptedMedicalComorbidities: String? = nil,
        remotePsychiatricHistory: String? = nil,
        encryptedRemotePsychiatricHistory: String? = nil,
        allergies: String = "",
        encryptedAllergies: String? = nil,
        exemptions: String = "",
        currentTherapySummary: String = "",
        heartFunctionStatus: String? = nil,
        liverFunctionStatus: String? = nil,
        kidneyFunctionStatus: String? = nil,
        bloodTestsTableJSON: String? = nil,
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
        self.encryptedPrimaryDiagnosis = encryptedPrimaryDiagnosis
        self.secondaryDiagnosis = secondaryDiagnosis
        self.encryptedSecondaryDiagnosis = encryptedSecondaryDiagnosis
        self.medicalHistory = medicalHistory
        self.medicalComorbidities = medicalComorbidities
        self.encryptedMedicalComorbidities = encryptedMedicalComorbidities
        self.remotePsychiatricHistory = remotePsychiatricHistory
        self.encryptedRemotePsychiatricHistory = encryptedRemotePsychiatricHistory
        self.allergies = allergies
        self.encryptedAllergies = encryptedAllergies
        self.exemptions = exemptions
        self.currentTherapySummary = currentTherapySummary
        self.heartFunctionStatus = heartFunctionStatus
        self.liverFunctionStatus = liverFunctionStatus
        self.kidneyFunctionStatus = kidneyFunctionStatus
        self.bloodTestsTableJSON = bloodTestsTableJSON
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

    var ageInYears: Int? {
        guard let dateOfBirth else { return nil }
        let years = Calendar.current.dateComponents([.year], from: dateOfBirth, to: .now).year ?? 0
        return max(0, years)
    }

    var clinicalWindowTitle: String {
        let namePart = "\(lastName.localizedUppercase) \(firstName.localizedUppercase)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = namePart.isEmpty ? "NUOVO PAZIENTE" : namePart

        if let ageInYears {
            return "Scheda Clinica: \(resolvedName) (\(ageInYears) anni)"
        }
        return "Scheda Clinica: \(resolvedName)"
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

    private func decrypted(_ encrypted: String?, fallback: String) -> String {
        if let decrypted = SecureDataCipher.shared.decrypt(encrypted) {
            return decrypted
        }
        return fallback
    }

    private func encryptedValue(_ plaintext: String) -> String? {
        SecureDataCipher.shared.encrypt(plaintext)
    }

    var readablePrimaryDiagnosis: String {
        decrypted(encryptedPrimaryDiagnosis, fallback: primaryDiagnosis)
    }

    func protectPrimaryDiagnosis(_ value: String) {
        if let encrypted = encryptedValue(value) {
            encryptedPrimaryDiagnosis = encrypted
            primaryDiagnosis = ""
        } else {
            encryptedPrimaryDiagnosis = nil
            primaryDiagnosis = value
        }
    }

    var readableSecondaryDiagnosis: String {
        decrypted(encryptedSecondaryDiagnosis, fallback: secondaryDiagnosis)
    }

    func protectSecondaryDiagnosis(_ value: String) {
        if let encrypted = encryptedValue(value) {
            encryptedSecondaryDiagnosis = encrypted
            secondaryDiagnosis = ""
        } else {
            encryptedSecondaryDiagnosis = nil
            secondaryDiagnosis = value
        }
    }

    var readableMedicalComorbidities: String {
        decrypted(encryptedMedicalComorbidities, fallback: medicalComorbidities ?? "")
    }

    func protectMedicalComorbidities(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            encryptedMedicalComorbidities = nil
            medicalComorbidities = nil
            return
        }

        if let encrypted = encryptedValue(value) {
            encryptedMedicalComorbidities = encrypted
            medicalComorbidities = nil
        } else {
            encryptedMedicalComorbidities = nil
            medicalComorbidities = value.isEmpty ? nil : value
        }
    }

    var readableRemotePsychiatricHistory: String {
        decrypted(encryptedRemotePsychiatricHistory, fallback: remotePsychiatricHistory ?? "")
    }

    func protectRemotePsychiatricHistory(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            encryptedRemotePsychiatricHistory = nil
            remotePsychiatricHistory = nil
            return
        }

        if let encrypted = encryptedValue(value) {
            encryptedRemotePsychiatricHistory = encrypted
            remotePsychiatricHistory = nil
        } else {
            encryptedRemotePsychiatricHistory = nil
            remotePsychiatricHistory = value.isEmpty ? nil : value
        }
    }

    var readableAllergies: String {
        decrypted(encryptedAllergies, fallback: allergies)
    }

    func protectAllergies(_ value: String) {
        if let encrypted = encryptedValue(value) {
            encryptedAllergies = encrypted
            allergies = ""
        } else {
            encryptedAllergies = nil
            allergies = value
        }
    }
}
