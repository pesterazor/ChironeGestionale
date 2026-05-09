import Foundation
import SwiftData
import CryptoKit
import Security
import CommonCrypto

enum EncryptedBackupError: Error, Equatable {
    case invalidPassword
    case invalidEnvelope
    case unsupportedVersion
    case unsupportedSchemaVersion
    case randomGenerationFailed
    case kdfFailed(status: Int32)
    case encryptionFailed
    case decryptionFailed
}

struct EncryptedBackupEnvelope: Codable {
    struct CipherInfo: Codable {
        let algorithm: String
        let nonceBase64: String
        let aadBase64: String
    }

    struct KDFInfo: Codable {
        let algorithm: String
        let saltBase64: String
        let iterations: Int
        let keyLength: Int
    }

    struct Metadata: Codable {
        struct RecordCounts: Codable {
            let patients: Int
            let clinicalNotes: Int
            let therapyItems: Int
        }

        let appVersion: String
        let schemaVersion: Int
        let recordCounts: RecordCounts
    }

    let format: String
    let version: Int
    let createdAt: Date
    let cipher: CipherInfo
    let kdf: KDFInfo
    let wrappedDEKBase64: String
    let wrappedDEKNonceBase64: String
    let payloadBase64: String
    let metadata: Metadata
}

struct BackupPayload: Codable {
    struct PatientRecord: Codable {
        let id: UUID
        let firstName: String
        let lastName: String
        let dateOfBirth: Date?
        let gender: String?
        let taxCode: String
        let placeOfBirth: String
        let birthProvince: String?
        let residence: String
        let residenceAddress: String?
        let residenceCity: String?
        let residenceProvince: String?
        let phoneNumber: String
        let emergencyContact: String
        let generalPractitioner: String
        let privacyConsentSigned: Bool
        let referenceCSM: String
        let referringClinician: String
        let primaryDiagnosis: String
        let encryptedPrimaryDiagnosis: String?
        let secondaryDiagnosis: String
        let encryptedSecondaryDiagnosis: String?
        let medicalHistory: String
        let medicalComorbidities: String?
        let encryptedMedicalComorbidities: String?
        let remotePsychiatricHistory: String?
        let encryptedRemotePsychiatricHistory: String?
        let allergies: String
        let encryptedAllergies: String?
        let exemptions: String
        let currentTherapySummary: String
        let heartFunctionStatus: String?
        let liverFunctionStatus: String?
        let kidneyFunctionStatus: String?
        let bloodTestsTableJSON: String?
        let createdAt: Date
        let updatedAt: Date
    }

    struct ClinicalNoteRecord: Codable {
        let id: UUID
        let patientID: UUID?
        let content: String
        let encryptedContent: String?
        let wellbeingScore: Int
        let createdAt: Date
        let updatedAt: Date
    }

    struct TherapyMedicationRecord: Codable {
        let id: UUID
        let patientID: UUID?
        let medicationName: String
        let dosage: String
        let posology: String
        let isActive: Bool
        let createdAt: Date
        let updatedAt: Date
    }

    let exportedAt: Date
    let patients: [PatientRecord]
    let clinicalNotes: [ClinicalNoteRecord]
    let therapyItems: [TherapyMedicationRecord]
}

final class EncryptedBackupService {
    static let shared = EncryptedBackupService()

    private let format = "chirone-backup"
    private let version = 1
    private let schemaVersion = 1
    private let kdfIterations = 600_000
    private let keyLength = 32

    private init() {}

    func exportBackup(from modelContext: ModelContext, password: String) throws -> Data {
        let passwordData = Data(password.utf8)
        guard !passwordData.isEmpty else {
            throw EncryptedBackupError.invalidPassword
        }

        let patients = try modelContext.fetch(FetchDescriptor<Patient>())
        let notes = try modelContext.fetch(FetchDescriptor<ClinicalNote>())
        let meds = try modelContext.fetch(FetchDescriptor<TherapyMedication>())

        let payload = BackupPayload(
            exportedAt: .now,
            patients: patients.map(Self.mapPatient),
            clinicalNotes: notes.map(Self.mapNote),
            therapyItems: meds.map(Self.mapMedication)
        )

        let payloadData = try JSONEncoder.chirone.encode(payload)

        let dataEncryptionKey = SymmetricKey(size: .bits256)
        let dataNonceData = try randomData(count: 12)
        let dataNonce = try AES.GCM.Nonce(data: dataNonceData)

        let salt = try randomData(count: 16)
        let kekRaw = try deriveKey(password: passwordData, salt: salt, iterations: kdfIterations, keyLength: keyLength)
        let keyEncryptionKey = SymmetricKey(data: kekRaw)

        let wrappedNonceData = try randomData(count: 12)
        let wrappedNonce = try AES.GCM.Nonce(data: wrappedNonceData)

        let metadata = EncryptedBackupEnvelope.Metadata(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            schemaVersion: schemaVersion,
            recordCounts: .init(patients: patients.count, clinicalNotes: notes.count, therapyItems: meds.count)
        )

        let aad = try makeAAD(createdAt: .now, iterations: kdfIterations, schemaVersion: schemaVersion)

        let payloadSealed = try AES.GCM.seal(payloadData, using: dataEncryptionKey, nonce: dataNonce, authenticating: aad)
        guard let payloadCombined = payloadSealed.combined else {
            throw EncryptedBackupError.encryptionFailed
        }

        let dekRaw = dataEncryptionKey.withUnsafeBytes { Data($0) }
        let wrappedSealed = try AES.GCM.seal(dekRaw, using: keyEncryptionKey, nonce: wrappedNonce, authenticating: aad)
        guard let wrappedCombined = wrappedSealed.combined else {
            throw EncryptedBackupError.encryptionFailed
        }

        let createdAt = Date()
        let envelope = EncryptedBackupEnvelope(
            format: format,
            version: version,
            createdAt: createdAt,
            cipher: .init(
                algorithm: "AES-GCM-256",
                nonceBase64: dataNonceData.base64EncodedString(),
                aadBase64: aad.base64EncodedString()
            ),
            kdf: .init(
                algorithm: "PBKDF2-HMAC-SHA256",
                saltBase64: salt.base64EncodedString(),
                iterations: kdfIterations,
                keyLength: keyLength
            ),
            wrappedDEKBase64: wrappedCombined.base64EncodedString(),
            wrappedDEKNonceBase64: wrappedNonceData.base64EncodedString(),
            payloadBase64: payloadCombined.base64EncodedString(),
            metadata: metadata
        )

        return try JSONEncoder.chirone.encode(envelope)
    }

    func restoreBackup(into modelContext: ModelContext, password: String, backupData: Data, replaceExisting: Bool = true) throws {
        let passwordData = Data(password.utf8)
        guard !passwordData.isEmpty else {
            throw EncryptedBackupError.invalidPassword
        }

        let envelope = try JSONDecoder.chirone.decode(EncryptedBackupEnvelope.self, from: backupData)
        guard envelope.format == format else {
            throw EncryptedBackupError.invalidEnvelope
        }
        guard envelope.version == version else {
            throw EncryptedBackupError.unsupportedVersion
        }
        guard envelope.metadata.schemaVersion == schemaVersion else {
            throw EncryptedBackupError.unsupportedSchemaVersion
        }

        guard
            let salt = Data(base64Encoded: envelope.kdf.saltBase64),
            let wrappedDEK = Data(base64Encoded: envelope.wrappedDEKBase64),
            let payloadData = Data(base64Encoded: envelope.payloadBase64),
            let aad = Data(base64Encoded: envelope.cipher.aadBase64)
        else {
            throw EncryptedBackupError.invalidEnvelope
        }

        let kekRaw = try deriveKey(
            password: passwordData,
            salt: salt,
            iterations: envelope.kdf.iterations,
            keyLength: envelope.kdf.keyLength
        )
        let kek = SymmetricKey(data: kekRaw)

        let wrappedBox = try AES.GCM.SealedBox(combined: wrappedDEK)
        let dekRaw: Data
        do {
            dekRaw = try AES.GCM.open(wrappedBox, using: kek, authenticating: aad)
        } catch {
            throw EncryptedBackupError.invalidPassword
        }

        let dek = SymmetricKey(data: dekRaw)
        let payloadBox = try AES.GCM.SealedBox(combined: payloadData)
        let decryptedPayload: Data
        do {
            decryptedPayload = try AES.GCM.open(payloadBox, using: dek, authenticating: aad)
        } catch {
            throw EncryptedBackupError.decryptionFailed
        }

        let payload = try JSONDecoder.chirone.decode(BackupPayload.self, from: decryptedPayload)
        guard envelope.metadata.recordCounts.patients == payload.patients.count,
              envelope.metadata.recordCounts.clinicalNotes == payload.clinicalNotes.count,
              envelope.metadata.recordCounts.therapyItems == payload.therapyItems.count else {
            throw EncryptedBackupError.invalidEnvelope
        }

        if replaceExisting {
            try clearAllData(in: modelContext)
        }

        var patientByID: [UUID: Patient] = [:]

        for record in payload.patients {
            let patient = Patient(
                id: record.id,
                firstName: record.firstName,
                lastName: record.lastName,
                dateOfBirth: record.dateOfBirth,
                gender: record.gender,
                taxCode: record.taxCode,
                placeOfBirth: record.placeOfBirth,
                birthProvince: record.birthProvince,
                residence: record.residence,
                residenceAddress: record.residenceAddress,
                residenceCity: record.residenceCity,
                residenceProvince: record.residenceProvince,
                phoneNumber: record.phoneNumber,
                emergencyContact: record.emergencyContact,
                generalPractitioner: record.generalPractitioner,
                privacyConsentSigned: record.privacyConsentSigned,
                referenceCSM: record.referenceCSM,
                referringClinician: record.referringClinician,
                primaryDiagnosis: record.primaryDiagnosis,
                encryptedPrimaryDiagnosis: record.encryptedPrimaryDiagnosis,
                secondaryDiagnosis: record.secondaryDiagnosis,
                encryptedSecondaryDiagnosis: record.encryptedSecondaryDiagnosis,
                medicalHistory: record.medicalHistory,
                medicalComorbidities: record.medicalComorbidities,
                encryptedMedicalComorbidities: record.encryptedMedicalComorbidities,
                remotePsychiatricHistory: record.remotePsychiatricHistory,
                encryptedRemotePsychiatricHistory: record.encryptedRemotePsychiatricHistory,
                allergies: record.allergies,
                encryptedAllergies: record.encryptedAllergies,
                exemptions: record.exemptions,
                currentTherapySummary: record.currentTherapySummary,
                heartFunctionStatus: record.heartFunctionStatus,
                liverFunctionStatus: record.liverFunctionStatus,
                kidneyFunctionStatus: record.kidneyFunctionStatus,
                bloodTestsTableJSON: record.bloodTestsTableJSON,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
            modelContext.insert(patient)
            patientByID[patient.id] = patient
        }

        for record in payload.clinicalNotes {
            let note = ClinicalNote(
                id: record.id,
                content: record.content,
                encryptedContent: record.encryptedContent,
                wellbeingScore: record.wellbeingScore,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                patient: record.patientID.flatMap { patientByID[$0] }
            )
            modelContext.insert(note)
            if let patientID = record.patientID, let patient = patientByID[patientID] {
                patient.clinicalNotes.append(note)
            }
        }

        for record in payload.therapyItems {
            let item = TherapyMedication(
                id: record.id,
                medicationName: record.medicationName,
                dosage: record.dosage,
                posology: record.posology,
                isActive: record.isActive,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                patient: record.patientID.flatMap { patientByID[$0] }
            )
            modelContext.insert(item)
            if let patientID = record.patientID, let patient = patientByID[patientID] {
                patient.therapyItems.append(item)
            }
        }

        try modelContext.save()
    }

    private func clearAllData(in modelContext: ModelContext) throws {
        let allPatients = try modelContext.fetch(FetchDescriptor<Patient>())
        let allNotes = try modelContext.fetch(FetchDescriptor<ClinicalNote>())
        let allTherapy = try modelContext.fetch(FetchDescriptor<TherapyMedication>())

        for note in allNotes {
            modelContext.delete(note)
        }
        for therapy in allTherapy {
            modelContext.delete(therapy)
        }
        for patient in allPatients {
            modelContext.delete(patient)
        }

        try modelContext.save()
    }

    private func deriveKey(password: Data, salt: Data, iterations: Int, keyLength: Int) throws -> Data {
        var derived = Data(repeating: 0, count: keyLength)

        let status = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw EncryptedBackupError.kdfFailed(status: status)
        }

        return derived
    }

    private func randomData(count: Int) throws -> Data {
        var data = Data(repeating: 0, count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }

        guard status == errSecSuccess else {
            throw EncryptedBackupError.randomGenerationFailed
        }

        return data
    }

    private func makeAAD(createdAt: Date, iterations: Int, schemaVersion: Int) throws -> Data {
        let aad = AAD(
            format: format,
            version: version,
            createdAt: createdAt,
            kdfAlgorithm: "PBKDF2-HMAC-SHA256",
            kdfIterations: iterations,
            schemaVersion: schemaVersion
        )
        return try JSONEncoder.chirone.encode(aad)
    }

    private struct AAD: Codable {
        let format: String
        let version: Int
        let createdAt: Date
        let kdfAlgorithm: String
        let kdfIterations: Int
        let schemaVersion: Int
    }

    nonisolated private static func mapPatient(_ patient: Patient) -> BackupPayload.PatientRecord {
        BackupPayload.PatientRecord(
            id: patient.id,
            firstName: patient.firstName,
            lastName: patient.lastName,
            dateOfBirth: patient.dateOfBirth,
            gender: patient.gender,
            taxCode: patient.taxCode,
            placeOfBirth: patient.placeOfBirth,
            birthProvince: patient.birthProvince,
            residence: patient.residence,
            residenceAddress: patient.residenceAddress,
            residenceCity: patient.residenceCity,
            residenceProvince: patient.residenceProvince,
            phoneNumber: patient.phoneNumber,
            emergencyContact: patient.emergencyContact,
            generalPractitioner: patient.generalPractitioner,
            privacyConsentSigned: patient.privacyConsentSigned,
            referenceCSM: patient.referenceCSM,
            referringClinician: patient.referringClinician,
            primaryDiagnosis: patient.primaryDiagnosis,
            encryptedPrimaryDiagnosis: patient.encryptedPrimaryDiagnosis,
            secondaryDiagnosis: patient.secondaryDiagnosis,
            encryptedSecondaryDiagnosis: patient.encryptedSecondaryDiagnosis,
            medicalHistory: patient.medicalHistory,
            medicalComorbidities: patient.medicalComorbidities,
            encryptedMedicalComorbidities: patient.encryptedMedicalComorbidities,
            remotePsychiatricHistory: patient.remotePsychiatricHistory,
            encryptedRemotePsychiatricHistory: patient.encryptedRemotePsychiatricHistory,
            allergies: patient.allergies,
            encryptedAllergies: patient.encryptedAllergies,
            exemptions: patient.exemptions,
            currentTherapySummary: patient.currentTherapySummary,
            heartFunctionStatus: patient.heartFunctionStatus,
            liverFunctionStatus: patient.liverFunctionStatus,
            kidneyFunctionStatus: patient.kidneyFunctionStatus,
            bloodTestsTableJSON: patient.bloodTestsTableJSON,
            createdAt: patient.createdAt,
            updatedAt: patient.updatedAt
        )
    }

    nonisolated private static func mapNote(_ note: ClinicalNote) -> BackupPayload.ClinicalNoteRecord {
        BackupPayload.ClinicalNoteRecord(
            id: note.id,
            patientID: note.patient?.id,
            content: note.content,
            encryptedContent: note.encryptedContent,
            wellbeingScore: note.wellbeingScore,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt
        )
    }

    nonisolated private static func mapMedication(_ medication: TherapyMedication) -> BackupPayload.TherapyMedicationRecord {
        BackupPayload.TherapyMedicationRecord(
            id: medication.id,
            patientID: medication.patient?.id,
            medicationName: medication.medicationName,
            dosage: medication.dosage,
            posology: medication.posology,
            isActive: medication.isActive,
            createdAt: medication.createdAt,
            updatedAt: medication.updatedAt
        )
    }
}

private extension JSONEncoder {
    static var chirone: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var chirone: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
