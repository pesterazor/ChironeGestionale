import Foundation
import SwiftData
import CryptoKit
import Security
import CommonCrypto

nonisolated enum EncryptedBackupError: Error, Equatable, LocalizedError {
    case invalidPassword
    case invalidEnvelope
    case unsupportedVersion
    case unsupportedSchemaVersion
    case randomGenerationFailed
    case kdfFailed(status: Int32)
    case encryptionFailed
    case decryptionFailed
    case invalidAssessmentData
    case invalidRecordData
    case unreadableClinicalData
    case localEncryptionFailed
    case duplicateExistingRecords

    var errorDescription: String? {
        switch self {
        case .invalidPassword: return "La password non è corretta oppure il backup non è integro."
        case .invalidEnvelope: return "Il file di backup è incompleto o contiene dati di controllo non validi."
        case .unsupportedVersion, .unsupportedSchemaVersion: return "Questo backup richiede una versione compatibile di Chirone."
        case .invalidAssessmentData: return "Il backup contiene risposte o collegamenti non validi nelle scale psicometriche."
        case .invalidRecordData: return "Il backup contiene record duplicati o collegamenti a pazienti mancanti."
        case .unreadableClinicalData: return "Alcuni dati clinici cifrati non sono leggibili. Il backup è stato interrotto per evitare la perdita di contenuti."
        case .localEncryptionFailed: return "Non è stato possibile proteggere i dati clinici su questo Mac. L’archivio precedente è stato conservato."
        case .duplicateExistingRecords: return "Il backup contiene record già presenti nell’archivio. Usa il ripristino con sostituzione per evitare duplicati."
        case .randomGenerationFailed, .kdfFailed, .encryptionFailed, .decryptionFailed:
            return "Non è stato possibile completare la cifratura o verificare l’integrità del backup."
        }
    }
}

nonisolated struct EncryptedBackupEnvelope: Codable, Sendable {
    struct CipherInfo: Codable, Sendable {
        let algorithm: String
        let nonceBase64: String
        let aadBase64: String
    }

    struct KDFInfo: Codable, Sendable {
        let algorithm: String
        let saltBase64: String
        let iterations: Int
        let keyLength: Int
    }

    struct Metadata: Codable, Equatable, Sendable {
        struct RecordCounts: Codable, Equatable, Sendable {
            let patients: Int
            let clinicalNotes: Int
            let therapyItems: Int
            let phq9Assessments: Int
            let gad7Assessments: Int
            let mdqAssessments: Int
            let beckAssessments: Int?
            let madrsAssessments: Int?
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

// Schema v2: i campi clinici sensibili viaggiano in CHIARO dentro il payload
// (già protetto da AES-GCM con KEK derivata via PBKDF2 dalla password utente).
// Al restore vengono ricifrati con la chiave Keychain locale del Mac di destinazione,
// così il backup è portabile tra macchine diverse.
nonisolated struct BackupPayload: Codable, Sendable {
    struct PatientRecord: Codable, Sendable {
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
        let secondaryDiagnosis: String
        let medicalHistory: String
        let medicalComorbidities: String?
        let remotePsychiatricHistory: String?
        let allergies: String
        let exemptions: String
        let currentTherapySummary: String
        let heartFunctionStatus: String?
        let liverFunctionStatus: String?
        let kidneyFunctionStatus: String?
        let bloodTestsTableJSON: String?
        let createdAt: Date
        let updatedAt: Date
    }

    struct ClinicalNoteRecord: Codable, Sendable {
        let id: UUID
        let patientID: UUID?
        let content: String
        let wellbeingScore: Int
        let createdAt: Date
        let updatedAt: Date
    }

    struct TherapyMedicationRecord: Codable, Sendable {
        let id: UUID
        let patientID: UUID?
        let medicationName: String
        let dosage: String
        let posology: String
        let isActive: Bool
        let createdAt: Date
        let updatedAt: Date
    }

    struct PHQ9AssessmentRecord: Codable, Sendable {
        let id: UUID
        let patientID: UUID?
        let date: Date
        let scores: [Int]
        let createdAt: Date
    }

    struct GAD7AssessmentRecord: Codable, Sendable {
        let id: UUID
        let patientID: UUID?
        let date: Date
        let scores: [Int]
        let createdAt: Date
    }

    struct MDQAssessmentRecord: Codable, Sendable {
        let id: UUID
        let patientID: UUID?
        let date: Date
        let part1Answers: [Int]
        let part2Answer: Bool
        let part3RawValue: Int
        let createdAt: Date
    }

    struct BeckAssessmentRecord: Codable, Sendable {
        let id: UUID
        let patientID: UUID?
        let scaleRawValue: String
        let date: Date
        let answerIndices: [Int]
        let createdAt: Date
    }

    struct MADRSAssessmentRecord: Codable, Sendable {
        let id: UUID
        let patientID: UUID?
        let date: Date
        let scores: [Int]
        let raterName: String
        let createdAt: Date
    }

    let exportedAt: Date
    let patients: [PatientRecord]
    let clinicalNotes: [ClinicalNoteRecord]
    let therapyItems: [TherapyMedicationRecord]
    let phq9Assessments: [PHQ9AssessmentRecord]
    let gad7Assessments: [GAD7AssessmentRecord]
    let mdqAssessments: [MDQAssessmentRecord]
    let beckAssessments: [BeckAssessmentRecord]?
    let madrsAssessments: [MADRSAssessmentRecord]?
}

// Le scale non presenti nei backup precedenti corrispondono a elenchi vuoti.
// Beck e MADRS restano opzionali per distinguere i vecchi schemi da backup incompleti.
extension BackupPayload {
    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        exportedAt = try values.decode(Date.self, forKey: .exportedAt)
        patients = try values.decode([PatientRecord].self, forKey: .patients)
        clinicalNotes = try values.decode([ClinicalNoteRecord].self, forKey: .clinicalNotes)
        therapyItems = try values.decode([TherapyMedicationRecord].self, forKey: .therapyItems)
        phq9Assessments = try values.decodeIfPresent([PHQ9AssessmentRecord].self, forKey: .phq9Assessments) ?? []
        gad7Assessments = try values.decodeIfPresent([GAD7AssessmentRecord].self, forKey: .gad7Assessments) ?? []
        mdqAssessments = try values.decodeIfPresent([MDQAssessmentRecord].self, forKey: .mdqAssessments) ?? []
        beckAssessments = try values.decodeIfPresent([BeckAssessmentRecord].self, forKey: .beckAssessments)
        madrsAssessments = try values.decodeIfPresent([MADRSAssessmentRecord].self, forKey: .madrsAssessments)
    }
}

extension EncryptedBackupEnvelope.Metadata.RecordCounts {
    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        patients = try values.decode(Int.self, forKey: .patients)
        clinicalNotes = try values.decode(Int.self, forKey: .clinicalNotes)
        therapyItems = try values.decode(Int.self, forKey: .therapyItems)
        phq9Assessments = try values.decodeIfPresent(Int.self, forKey: .phq9Assessments) ?? 0
        gad7Assessments = try values.decodeIfPresent(Int.self, forKey: .gad7Assessments) ?? 0
        mdqAssessments = try values.decodeIfPresent(Int.self, forKey: .mdqAssessments) ?? 0
        beckAssessments = try values.decodeIfPresent(Int.self, forKey: .beckAssessments)
        madrsAssessments = try values.decodeIfPresent(Int.self, forKey: .madrsAssessments)
    }
}

final class EncryptedBackupService {
    static let shared = EncryptedBackupService()

    nonisolated private let format = "chirone-backup"
    nonisolated private let version = 1
    nonisolated private let schemaVersion = 5
    nonisolated private let kdfIterations = 600_000
    nonisolated private let keyLength = 32

    private init() {}

    func exportBackup(from modelContext: ModelContext, password: String) throws -> Data {
        let payload = try makePayload(from: modelContext)
        return try encryptPayload(payload, password: password)
    }

    // Capture SwiftData values on their context's actor; only value types cross to crypto work.
    func makePayload(from modelContext: ModelContext) throws -> BackupPayload {
        let patients = try modelContext.fetch(FetchDescriptor<Patient>())
        let notes = try modelContext.fetch(FetchDescriptor<ClinicalNote>())
        let meds = try modelContext.fetch(FetchDescriptor<TherapyMedication>())
        let phq9 = try modelContext.fetch(FetchDescriptor<PHQ9Assessment>())
        let gad7 = try modelContext.fetch(FetchDescriptor<GAD7Assessment>())
        let mdq = try modelContext.fetch(FetchDescriptor<MDQAssessment>())
        let beck = try modelContext.fetch(FetchDescriptor<BeckAssessment>())
        let madrs = try modelContext.fetch(FetchDescriptor<MADRSAssessment>())
        guard beck.allSatisfy({ $0.totalScore != nil }), madrs.allSatisfy({ $0.totalScore != nil }) else {
            throw EncryptedBackupError.invalidAssessmentData
        }

        let payload = BackupPayload(
            exportedAt: .now,
            patients: try patients.map { try Self.mapPatient($0) },
            clinicalNotes: try notes.map { try Self.mapNote($0) },
            therapyItems: meds.map { Self.mapMedication($0) },
            phq9Assessments: phq9.map { Self.mapPHQ9($0) },
            gad7Assessments: gad7.map { Self.mapGAD7($0) },
            mdqAssessments: mdq.map { Self.mapMDQ($0) },
            beckAssessments: beck.map { Self.mapBeck($0) },
            madrsAssessments: madrs.map { Self.mapMADRS($0) }
        )

        try validatePayload(payload)
        return payload
    }

    // The patient export uses the same complete, strictly decoded clinical snapshot.
    func makePayload(for patient: Patient) throws -> BackupPayload {
        let payload = BackupPayload(
            exportedAt: .now,
            patients: [try Self.mapPatient(patient)],
            clinicalNotes: try patient.clinicalNotes.map { try Self.mapNote($0) },
            therapyItems: patient.therapyItems.map { Self.mapMedication($0) },
            phq9Assessments: patient.phq9Assessments.map { Self.mapPHQ9($0) },
            gad7Assessments: patient.gad7Assessments.map { Self.mapGAD7($0) },
            mdqAssessments: patient.mdqAssessments.map { Self.mapMDQ($0) },
            beckAssessments: patient.beckAssessments.map { Self.mapBeck($0) },
            madrsAssessments: patient.madrsAssessments.map { Self.mapMADRS($0) }
        )
        try validatePayload(payload)
        return payload
    }

    nonisolated func encryptPayload(_ payload: BackupPayload, password: String) throws -> Data {
        let passwordData = Data(password.utf8)
        guard !passwordData.isEmpty else { throw EncryptedBackupError.invalidPassword }
        let payloadData = try BackupPayloadCoding.encode(payload)

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
            recordCounts: .init(
                patients: payload.patients.count,
                clinicalNotes: payload.clinicalNotes.count,
                therapyItems: payload.therapyItems.count,
                phq9Assessments: payload.phq9Assessments.count,
                gad7Assessments: payload.gad7Assessments.count,
                mdqAssessments: payload.mdqAssessments.count,
                beckAssessments: (payload.beckAssessments ?? []).count,
                madrsAssessments: (payload.madrsAssessments ?? []).count
            )
        )

        let createdAt = Date()
        let aad = try JSONEncoder.chirone.encode(AAD(
            format: format, version: version, createdAt: createdAt,
            kdfAlgorithm: "PBKDF2-HMAC-SHA256", kdfIterations: kdfIterations,
            schemaVersion: schemaVersion, metadata: metadata,
            cipherAlgorithm: "AES-GCM-256", saltBase64: salt.base64EncodedString(),
            keyLength: keyLength, nonceBase64: dataNonceData.base64EncodedString(),
            wrappedNonceBase64: wrappedNonceData.base64EncodedString()
        ))

        let payloadSealed = try AES.GCM.seal(payloadData, using: dataEncryptionKey, nonce: dataNonce, authenticating: aad)
        guard let payloadCombined = payloadSealed.combined else {
            throw EncryptedBackupError.encryptionFailed
        }

        let dekRaw = dataEncryptionKey.withUnsafeBytes { Data($0) }
        let wrappedSealed = try AES.GCM.seal(dekRaw, using: keyEncryptionKey, nonce: wrappedNonce, authenticating: aad)
        guard let wrappedCombined = wrappedSealed.combined else {
            throw EncryptedBackupError.encryptionFailed
        }

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
        let prepared = try decryptBackup(password: password, backupData: backupData)
        try restorePreparedBackup(prepared, into: modelContext, replaceExisting: replaceExisting)
    }

    nonisolated struct PreparedBackup: Sendable {
        let payload: BackupPayload
    }

    // No SwiftData or UI work here: safe to call from a detached task.
    nonisolated func decryptBackup(password: String, backupData: Data) throws -> PreparedBackup {
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
        guard (2...schemaVersion).contains(envelope.metadata.schemaVersion) else {
            throw EncryptedBackupError.unsupportedSchemaVersion
        }

        guard envelope.cipher.algorithm == "AES-GCM-256",
              envelope.kdf.algorithm == "PBKDF2-HMAC-SHA256",
              envelope.kdf.keyLength == keyLength,
              (100_000...2_000_000).contains(envelope.kdf.iterations),
              let nonce = Data(base64Encoded: envelope.cipher.nonceBase64), nonce.count == 12,
              let wrappedNonce = Data(base64Encoded: envelope.wrappedDEKNonceBase64), wrappedNonce.count == 12,
              let salt = Data(base64Encoded: envelope.kdf.saltBase64), salt.count == 16,
            let wrappedDEK = Data(base64Encoded: envelope.wrappedDEKBase64),
            let payloadData = Data(base64Encoded: envelope.payloadBase64),
            let aad = Data(base64Encoded: envelope.cipher.aadBase64)
        else {
            throw EncryptedBackupError.invalidEnvelope
        }

        guard wrappedDEK.count == 60, payloadData.count >= 28 else {
            throw EncryptedBackupError.invalidEnvelope
        }
        let authenticated = try JSONDecoder.chirone.decode(AAD.self, from: aad)
        guard authenticated.format == envelope.format,
              authenticated.version == envelope.version,
              authenticated.kdfAlgorithm == envelope.kdf.algorithm,
              authenticated.kdfIterations == envelope.kdf.iterations,
              authenticated.schemaVersion == envelope.metadata.schemaVersion else {
            throw EncryptedBackupError.invalidEnvelope
        }
        // Original v1 writers used separate Date() calls and did not authenticate full metadata.
        // Keep those archives readable; new archives bind all external metadata to the GCM tag.
        if let authenticatedMetadata = authenticated.metadata {
            guard authenticatedMetadata == envelope.metadata,
                  authenticated.createdAt == envelope.createdAt,
                  authenticated.cipherAlgorithm == envelope.cipher.algorithm,
                  authenticated.saltBase64 == envelope.kdf.saltBase64,
                  authenticated.keyLength == envelope.kdf.keyLength,
                  authenticated.nonceBase64 == envelope.cipher.nonceBase64,
                  authenticated.wrappedNonceBase64 == envelope.wrappedDEKNonceBase64 else {
                throw EncryptedBackupError.invalidEnvelope
            }
        }
        let wrappedBox = try AES.GCM.SealedBox(combined: wrappedDEK)
        let payloadBox = try AES.GCM.SealedBox(combined: payloadData)
        guard Data(wrappedBox.nonce) == wrappedNonce, Data(payloadBox.nonce) == nonce else {
            throw EncryptedBackupError.invalidEnvelope
        }

        let kekRaw = try deriveKey(
            password: passwordData,
            salt: salt,
            iterations: envelope.kdf.iterations,
            keyLength: envelope.kdf.keyLength
        )
        let kek = SymmetricKey(data: kekRaw)

        let dekRaw: Data
        do {
            dekRaw = try AES.GCM.open(wrappedBox, using: kek, authenticating: aad)
        } catch {
            throw EncryptedBackupError.invalidPassword
        }

        guard dekRaw.count == keyLength else { throw EncryptedBackupError.invalidEnvelope }
        let dek = SymmetricKey(data: dekRaw)
        let decryptedPayload: Data
        do {
            decryptedPayload = try AES.GCM.open(payloadBox, using: dek, authenticating: aad)
        } catch {
            throw EncryptedBackupError.decryptionFailed
        }

        let payload = try BackupPayloadCoding.decode(decryptedPayload)
        let beckRecords = payload.beckAssessments ?? []
        let madrsRecords = payload.madrsAssessments ?? []
        if envelope.metadata.schemaVersion >= 3 {
            guard payload.beckAssessments != nil, envelope.metadata.recordCounts.beckAssessments != nil else {
                throw EncryptedBackupError.invalidEnvelope
            }
        }
        if envelope.metadata.schemaVersion >= 4 {
            guard payload.madrsAssessments != nil, envelope.metadata.recordCounts.madrsAssessments != nil else {
                throw EncryptedBackupError.invalidEnvelope
            }
        }
        guard envelope.metadata.recordCounts.patients == payload.patients.count,
              envelope.metadata.recordCounts.clinicalNotes == payload.clinicalNotes.count,
              envelope.metadata.recordCounts.therapyItems == payload.therapyItems.count,
              envelope.metadata.recordCounts.phq9Assessments == payload.phq9Assessments.count,
              envelope.metadata.recordCounts.gad7Assessments == payload.gad7Assessments.count,
              envelope.metadata.recordCounts.mdqAssessments == payload.mdqAssessments.count,
              (envelope.metadata.recordCounts.beckAssessments ?? 0) == beckRecords.count,
              (envelope.metadata.recordCounts.madrsAssessments ?? 0) == madrsRecords.count else {
            throw EncryptedBackupError.invalidEnvelope
        }

        return PreparedBackup(payload: payload)
    }

    func restorePreparedBackup(
        _ prepared: PreparedBackup,
        into modelContext: ModelContext,
        replaceExisting: Bool = true,
        saveChanges: (() throws -> Void)? = nil
    ) throws {
        let payload = prepared.payload
        try validatePayload(payload)
        let beckRecords = payload.beckAssessments ?? []
        let madrsRecords = payload.madrsAssessments ?? []
        if !replaceExisting {
            try rejectExistingDuplicates(payload, in: modelContext)
        }
        // Preserve unrelated pending edits before entering the replacement transaction.
        if modelContext.hasChanges { try modelContext.save() }
        let wasAutosaveEnabled = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer { modelContext.autosaveEnabled = wasAutosaveEnabled }
        do {
            if replaceExisting {
                try clearAllData(in: modelContext)
            }

            var patientByID: [UUID: Patient] = [:]

            for record in payload.patients {
                // Plaintext fields land on the Patient first; the protect* methods
                // then ricifrano with the local Keychain key of THIS Mac, so the
                // backup is portable across machines.
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
                    medicalHistory: record.medicalHistory,
                    exemptions: record.exemptions,
                    currentTherapySummary: record.currentTherapySummary,
                    heartFunctionStatus: record.heartFunctionStatus,
                    liverFunctionStatus: record.liverFunctionStatus,
                    kidneyFunctionStatus: record.kidneyFunctionStatus,
                    bloodTestsTableJSON: record.bloodTestsTableJSON,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
                patient.protectPrimaryDiagnosis(record.primaryDiagnosis)
                patient.protectSecondaryDiagnosis(record.secondaryDiagnosis)
                patient.protectMedicalComorbidities(record.medicalComorbidities ?? "")
                patient.protectRemotePsychiatricHistory(record.remotePsychiatricHistory ?? "")
                patient.protectAllergies(record.allergies)
                let protectedFields = [
                    (record.primaryDiagnosis, patient.encryptedPrimaryDiagnosis),
                    (record.secondaryDiagnosis, patient.encryptedSecondaryDiagnosis),
                    (record.medicalComorbidities ?? "", patient.encryptedMedicalComorbidities),
                    (record.remotePsychiatricHistory ?? "", patient.encryptedRemotePsychiatricHistory),
                    (record.allergies, patient.encryptedAllergies)
                ]
                guard protectedFields.allSatisfy({ $0.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.1 != nil }) else {
                    throw EncryptedBackupError.localEncryptionFailed
                }
                modelContext.insert(patient)
                patientByID[patient.id] = patient
            }

            for record in payload.clinicalNotes {
                let note = ClinicalNote(
                    id: record.id,
                    content: "",
                    encryptedContent: nil,
                    wellbeingScore: record.wellbeingScore,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    patient: record.patientID.flatMap { patientByID[$0] }
                )
                // Restore the original text verbatim, including legacy whitespace.
                // The editing helper intentionally trims newly entered notes.
                note.encryptedContent = record.content.isEmpty ? nil : SecureDataCipher.shared.encrypt(record.content)
                guard record.content.isEmpty || note.encryptedContent != nil else {
                    throw EncryptedBackupError.localEncryptionFailed
                }
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

            for record in payload.phq9Assessments {
                let assessment = PHQ9Assessment(
                    date: record.date,
                    scores: record.scores,
                    patient: record.patientID.flatMap { patientByID[$0] }
                )
                assessment.id = record.id
                assessment.createdAt = record.createdAt
                modelContext.insert(assessment)
                if let patientID = record.patientID, let patient = patientByID[patientID] {
                    patient.phq9Assessments.append(assessment)
                }
            }

            for record in payload.gad7Assessments {
                let assessment = GAD7Assessment(
                    date: record.date,
                    scores: record.scores,
                    patient: record.patientID.flatMap { patientByID[$0] }
                )
                assessment.id = record.id
                assessment.createdAt = record.createdAt
                modelContext.insert(assessment)
                if let patientID = record.patientID, let patient = patientByID[patientID] {
                    patient.gad7Assessments.append(assessment)
                }
            }

            for record in payload.mdqAssessments {
                let assessment = MDQAssessment(
                    date: record.date,
                    part1Answers: record.part1Answers,
                    part2Answer: record.part2Answer,
                    part3RawValue: record.part3RawValue,
                    patient: record.patientID.flatMap { patientByID[$0] }
                )
                assessment.id = record.id
                assessment.createdAt = record.createdAt
                modelContext.insert(assessment)
                if let patientID = record.patientID, let patient = patientByID[patientID] {
                    patient.mdqAssessments.append(assessment)
                }
            }

            for record in beckRecords {
                guard let scale = BeckScale(rawValue: record.scaleRawValue) else {
                    throw EncryptedBackupError.invalidAssessmentData
                }
                let assessment = BeckAssessment(
                    scale: scale,
                    date: record.date,
                    answerIndices: record.answerIndices,
                    patient: record.patientID.flatMap { patientByID[$0] }
                )
                assessment.id = record.id
                assessment.createdAt = record.createdAt
                modelContext.insert(assessment)
                if let patientID = record.patientID, let patient = patientByID[patientID] {
                    patient.beckAssessments.append(assessment)
                }
            }

            for record in madrsRecords {
                let assessment = MADRSAssessment(
                    date: record.date,
                    scores: record.scores,
                    raterName: record.raterName,
                    patient: record.patientID.flatMap { patientByID[$0] }
                )
                assessment.id = record.id
                assessment.createdAt = record.createdAt
                modelContext.insert(assessment)
                if let patientID = record.patientID, let patient = patientByID[patientID] {
                    patient.madrsAssessments.append(assessment)
                }
            }

            if let saveChanges { try saveChanges() } else { try modelContext.save() }
        } catch {
            // Deletes and inserts have never been committed separately.
            modelContext.rollback()
            throw error
        }
    }

    func validatePayload(_ payload: BackupPayload) throws {
        let patientIDs = Set(payload.patients.map(\.id))
        func unique(_ ids: [UUID]) -> Bool { Set(ids).count == ids.count }
        func knownPatient(_ id: UUID?) -> Bool { id.map { patientIDs.contains($0) } ?? true }
        func finite(_ dates: Date...) -> Bool { dates.allSatisfy { $0.timeIntervalSinceReferenceDate.isFinite } }
        guard unique(payload.patients.map(\.id)),
              unique(payload.clinicalNotes.map(\.id)),
              unique(payload.therapyItems.map(\.id)),
              payload.patients.allSatisfy({ finite($0.createdAt, $0.updatedAt) }),
              payload.clinicalNotes.allSatisfy({ knownPatient($0.patientID) && finite($0.createdAt, $0.updatedAt) }),
              payload.therapyItems.allSatisfy({ knownPatient($0.patientID) && finite($0.createdAt, $0.updatedAt) }) else {
            throw EncryptedBackupError.invalidRecordData
        }
        guard unique(payload.phq9Assessments.map(\.id)),
              unique(payload.gad7Assessments.map(\.id)),
              unique(payload.mdqAssessments.map(\.id)),
              unique((payload.beckAssessments ?? []).map(\.id)),
              unique((payload.madrsAssessments ?? []).map(\.id)),
              payload.phq9Assessments.allSatisfy({
                  $0.scores.count == 9 && $0.scores.allSatisfy { (0...3).contains($0) } &&
                      knownPatient($0.patientID) && finite($0.date, $0.createdAt)
              }),
              payload.gad7Assessments.allSatisfy({
                  $0.scores.count == 7 && $0.scores.allSatisfy { (0...3).contains($0) } &&
                      knownPatient($0.patientID) && finite($0.date, $0.createdAt)
              }),
              payload.mdqAssessments.allSatisfy({
                  $0.part1Answers.count == 13 && $0.part1Answers.allSatisfy { (0...1).contains($0) } &&
                      (0...3).contains($0.part3RawValue) && knownPatient($0.patientID) && finite($0.date, $0.createdAt)
              }),
              (payload.beckAssessments ?? []).allSatisfy({
                  BeckScale(rawValue: $0.scaleRawValue)?.totalScore(forAnswers: $0.answerIndices) != nil &&
                      knownPatient($0.patientID) && finite($0.date, $0.createdAt)
              }),
              (payload.madrsAssessments ?? []).allSatisfy({
                  MADRS.totalScore(for: $0.scores) != nil && knownPatient($0.patientID) && finite($0.date, $0.createdAt)
              }) else {
            throw EncryptedBackupError.invalidAssessmentData
        }
    }

    private func rejectExistingDuplicates(_ payload: BackupPayload, in context: ModelContext) throws {
        func overlaps(_ incoming: [UUID], _ existing: [UUID]) -> Bool {
            !Set(incoming).isDisjoint(with: existing)
        }
        guard !overlaps(payload.patients.map(\.id), try context.fetch(FetchDescriptor<Patient>()).map(\.id)),
              !overlaps(payload.clinicalNotes.map(\.id), try context.fetch(FetchDescriptor<ClinicalNote>()).map(\.id)),
              !overlaps(payload.therapyItems.map(\.id), try context.fetch(FetchDescriptor<TherapyMedication>()).map(\.id)),
              !overlaps(payload.phq9Assessments.map(\.id), try context.fetch(FetchDescriptor<PHQ9Assessment>()).map(\.id)),
              !overlaps(payload.gad7Assessments.map(\.id), try context.fetch(FetchDescriptor<GAD7Assessment>()).map(\.id)),
              !overlaps(payload.mdqAssessments.map(\.id), try context.fetch(FetchDescriptor<MDQAssessment>()).map(\.id)),
              !overlaps((payload.beckAssessments ?? []).map(\.id), try context.fetch(FetchDescriptor<BeckAssessment>()).map(\.id)),
              !overlaps((payload.madrsAssessments ?? []).map(\.id), try context.fetch(FetchDescriptor<MADRSAssessment>()).map(\.id)) else {
            throw EncryptedBackupError.duplicateExistingRecords
        }
    }

    private static func exportClinicalText(_ encrypted: String?, fallback: String) throws -> String {
        guard let encrypted, !encrypted.isEmpty else { return fallback }
        guard let decrypted = SecureDataCipher.shared.decrypt(encrypted) else {
            throw EncryptedBackupError.unreadableClinicalData
        }
        return decrypted
    }

    private func clearAllData(in modelContext: ModelContext) throws {
        let allPatients = try modelContext.fetch(FetchDescriptor<Patient>())
        let allNotes = try modelContext.fetch(FetchDescriptor<ClinicalNote>())
        let allTherapy = try modelContext.fetch(FetchDescriptor<TherapyMedication>())
        let allPHQ9 = try modelContext.fetch(FetchDescriptor<PHQ9Assessment>())
        let allGAD7 = try modelContext.fetch(FetchDescriptor<GAD7Assessment>())
        let allMDQ = try modelContext.fetch(FetchDescriptor<MDQAssessment>())
        let allBeck = try modelContext.fetch(FetchDescriptor<BeckAssessment>())
        let allMADRS = try modelContext.fetch(FetchDescriptor<MADRSAssessment>())

        for note in allNotes {
            modelContext.delete(note)
        }
        for therapy in allTherapy {
            modelContext.delete(therapy)
        }
        for assessment in allPHQ9 {
            modelContext.delete(assessment)
        }
        for assessment in allGAD7 {
            modelContext.delete(assessment)
        }
        for assessment in allMDQ {
            modelContext.delete(assessment)
        }
        for assessment in allBeck {
            modelContext.delete(assessment)
        }
        for assessment in allMADRS {
            modelContext.delete(assessment)
        }
        for patient in allPatients {
            modelContext.delete(patient)
        }

    }

    nonisolated private func deriveKey(password: Data, salt: Data, iterations: Int, keyLength: Int) throws -> Data {
        guard keyLength == 32, (100_000...2_000_000).contains(iterations), salt.count == 16 else {
            throw EncryptedBackupError.invalidEnvelope
        }
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

    nonisolated private func randomData(count: Int) throws -> Data {
        var data = Data(repeating: 0, count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }

        guard status == errSecSuccess else {
            throw EncryptedBackupError.randomGenerationFailed
        }

        return data
    }

    nonisolated private struct AAD: Codable {
        let format: String
        let version: Int
        let createdAt: Date
        let kdfAlgorithm: String
        let kdfIterations: Int
        let schemaVersion: Int
        let metadata: EncryptedBackupEnvelope.Metadata?
        let cipherAlgorithm: String?
        let saltBase64: String?
        let keyLength: Int?
        let nonceBase64: String?
        let wrappedNonceBase64: String?
    }

    private static func mapPatient(_ patient: Patient) throws -> BackupPayload.PatientRecord {
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
            primaryDiagnosis: try exportClinicalText(patient.encryptedPrimaryDiagnosis, fallback: patient.primaryDiagnosis),
            secondaryDiagnosis: try exportClinicalText(patient.encryptedSecondaryDiagnosis, fallback: patient.secondaryDiagnosis),
            medicalHistory: patient.medicalHistory,
            medicalComorbidities: Self.nilIfEmpty(try exportClinicalText(patient.encryptedMedicalComorbidities, fallback: patient.medicalComorbidities ?? "")),
            remotePsychiatricHistory: Self.nilIfEmpty(try exportClinicalText(patient.encryptedRemotePsychiatricHistory, fallback: patient.remotePsychiatricHistory ?? "")),
            allergies: try exportClinicalText(patient.encryptedAllergies, fallback: patient.allergies),
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

    private static func mapNote(_ note: ClinicalNote) throws -> BackupPayload.ClinicalNoteRecord {
        BackupPayload.ClinicalNoteRecord(
            id: note.id,
            patientID: note.patient?.id,
            content: try exportClinicalText(note.encryptedContent, fallback: note.content),
            wellbeingScore: note.wellbeingScore,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt
        )
    }

    private static func mapMedication(_ medication: TherapyMedication) -> BackupPayload.TherapyMedicationRecord {
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

    private static func mapPHQ9(_ assessment: PHQ9Assessment) -> BackupPayload.PHQ9AssessmentRecord {
        BackupPayload.PHQ9AssessmentRecord(
            id: assessment.id,
            patientID: assessment.patient?.id,
            date: assessment.date,
            scores: assessment.scores,
            createdAt: assessment.createdAt
        )
    }

    private static func mapGAD7(_ assessment: GAD7Assessment) -> BackupPayload.GAD7AssessmentRecord {
        BackupPayload.GAD7AssessmentRecord(
            id: assessment.id,
            patientID: assessment.patient?.id,
            date: assessment.date,
            scores: assessment.scores,
            createdAt: assessment.createdAt
        )
    }

    private static func mapMDQ(_ assessment: MDQAssessment) -> BackupPayload.MDQAssessmentRecord {
        BackupPayload.MDQAssessmentRecord(
            id: assessment.id,
            patientID: assessment.patient?.id,
            date: assessment.date,
            part1Answers: assessment.part1Answers,
            part2Answer: assessment.part2Answer,
            part3RawValue: assessment.part3RawValue,
            createdAt: assessment.createdAt
        )
    }

    private static func mapBeck(_ assessment: BeckAssessment) -> BackupPayload.BeckAssessmentRecord {
        BackupPayload.BeckAssessmentRecord(
            id: assessment.id,
            patientID: assessment.patient?.id,
            scaleRawValue: assessment.scaleRawValue,
            date: assessment.date,
            answerIndices: assessment.answerIndices,
            createdAt: assessment.createdAt
        )
    }

    private static func mapMADRS(_ assessment: MADRSAssessment) -> BackupPayload.MADRSAssessmentRecord {
        BackupPayload.MADRSAssessmentRecord(
            id: assessment.id,
            patientID: assessment.patient?.id,
            date: assessment.date,
            scores: assessment.scores,
            raterName: assessment.raterName,
            createdAt: assessment.createdAt
        )
    }

    nonisolated private static func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }
}

// Schema 5 preserves Date's full Double precision. ISO-8601 without fractional
// seconds changed same-second assessment ordering after a backup round trip.
// Envelope/AAD and unrelated JSON exports retain their existing ISO-8601 format.
nonisolated enum BackupPayloadCoding {
    static func encode(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    static func decode(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            if let timestamp = try? value.decode(Double.self), timestamp.isFinite {
                return Date(timeIntervalSinceReferenceDate: timestamp)
            }
            let legacyDate = try value.decode(String.self)
            let formatter = ISO8601DateFormatter()
            guard let date = formatter.date(from: legacyDate) else {
                throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid backup date")
            }
            return date
        }
        return try decoder.decode(BackupPayload.self, from: data)
    }
}

extension JSONEncoder {
    nonisolated static var chirone: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    nonisolated static var chirone: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
