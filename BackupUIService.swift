import Foundation
import SwiftData
import AppKit
import UniformTypeIdentifiers
import CryptoKit

enum AuditEvent: String {
    case patientWindowOpened = "patient_window_opened"
    case patientWindowClosed = "patient_window_closed"
    case reportExported = "report_exported"
    case patientDataExported = "patient_data_exported"
    case backupExported = "backup_exported"
    case backupRestored = "backup_restored"
    case appUnlocked = "app_unlocked"
    case appLockFailed = "app_lock_failed"
    case appLocked = "app_locked"

    var displayName: String {
        switch self {
        case .patientWindowOpened: return "Apertura cartella"
        case .patientWindowClosed: return "Chiusura cartella"
        case .reportExported: return "Export referto"
        case .patientDataExported: return "Export dati paziente"
        case .backupExported: return "Export backup"
        case .backupRestored: return "Restore backup"
        case .appUnlocked: return "App sbloccata"
        case .appLockFailed: return "Sblocco fallito"
        case .appLocked: return "App bloccata"
        }
    }
}

@MainActor
final class AuditTrailService {
    static let shared = AuditTrailService()

    private enum Settings {
        static let retentionDaysKey = "audit.retentionDays"
        static let maxRecordsKey = "audit.maxRecords"
        static let defaultRetentionDays = 365
        static let defaultMaxRecords = 10_000
        static let minRetentionDays = 30
        static let maxRetentionDays = 3650
        static let minMaxRecords = 500
        static let maxMaxRecords = 200_000
    }

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logFileURL: URL

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let baseDirectory: URL
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseDirectory = appSupport.appendingPathComponent("ChironeGestionale", isDirectory: true)
        } else {
            baseDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ChironeGestionale", isDirectory: true)
        }

        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        logFileURL = baseDirectory.appendingPathComponent("audit.log", isDirectory: false)
        enforceRetentionPolicy()
    }

    var retentionDays: Int {
        let stored = UserDefaults.standard.integer(forKey: Settings.retentionDaysKey)
        if stored == 0 {
            return Settings.defaultRetentionDays
        }
        return min(max(stored, Settings.minRetentionDays), Settings.maxRetentionDays)
    }

    var maxRecords: Int {
        let stored = UserDefaults.standard.integer(forKey: Settings.maxRecordsKey)
        if stored == 0 {
            return Settings.defaultMaxRecords
        }
        return min(max(stored, Settings.minMaxRecords), Settings.maxMaxRecords)
    }

    func updateRetentionPolicy(retentionDays: Int, maxRecords: Int) {
        let normalizedDays = min(max(retentionDays, Settings.minRetentionDays), Settings.maxRetentionDays)
        let normalizedMaxRecords = min(max(maxRecords, Settings.minMaxRecords), Settings.maxMaxRecords)
        UserDefaults.standard.set(normalizedDays, forKey: Settings.retentionDaysKey)
        UserDefaults.standard.set(normalizedMaxRecords, forKey: Settings.maxRecordsKey)
        enforceRetentionPolicy()
    }

    func log(_ event: AuditEvent, metadata: [String: String] = [:]) {
        let record = AuditRecord(timestamp: Date(), event: event.rawValue, metadata: metadata)

        guard let data = try? encoder.encode(record),
              var line = String(data: data, encoding: .utf8)
        else {
            return
        }

        line.append("\n")
        append(line)
    }

    func redactedIdentifier(for id: UUID) -> String {
        let digest = SHA256.hash(data: Data(id.uuidString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    func readRecords(since: Date? = nil, event: AuditEvent? = nil, limit: Int = 500) -> [AuditRecord] {
        guard let data = try? Data(contentsOf: logFileURL),
              let content = String(data: data, encoding: .utf8)
        else {
            return []
        }

        var parsed: [AuditRecord] = []
        for line in content.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let record = try? JSONDecoder().decode(AuditRecord.self, from: lineData)
            else {
                continue
            }

            if let since, record.timestamp < since { continue }
            if let event, record.event != event.rawValue { continue }
            parsed.append(record)
        }

        let sorted = parsed.sorted { $0.timestamp > $1.timestamp }
        return Array(sorted.prefix(max(1, limit)))
    }

    func purgeAuditLogNow() {
        enforceRetentionPolicy()
    }

    private func append(_ line: String) {
        guard let payload = line.data(using: .utf8) else { return }

        if !fileManager.fileExists(atPath: logFileURL.path) {
            fileManager.createFile(atPath: logFileURL.path, contents: payload)
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: logFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
            enforceRetentionPolicy()
        } catch {
            // Best-effort logging: errors are intentionally ignored.
        }
    }

    private func enforceRetentionPolicy() {
        guard let data = try? Data(contentsOf: logFileURL),
              let content = String(data: data, encoding: .utf8)
        else {
            return
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? .distantPast

        var validRecords: [AuditRecord] = []
        for line in content.split(separator: "\n") {
            guard let rowData = line.data(using: .utf8),
                  let record = try? decoder.decode(AuditRecord.self, from: rowData),
                  record.timestamp >= cutoff
            else {
                continue
            }
            validRecords.append(record)
        }

        if validRecords.count > maxRecords {
            validRecords = Array(validRecords.suffix(maxRecords))
        }

        // Rebuild JSON Lines file with retained records only.
        let lineEncoder = JSONEncoder()
        lineEncoder.dateEncodingStrategy = .iso8601
        var lines: [String] = []
        for record in validRecords {
            guard let data = try? lineEncoder.encode(record),
                  let text = String(data: data, encoding: .utf8)
            else {
                continue
            }
            lines.append(text)
        }

        let rebuilt = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        if rebuilt != content, let rebuiltData = rebuilt.data(using: .utf8) {
            try? rebuiltData.write(to: logFileURL, options: .atomic)
        }
    }
}

struct AuditRecord: Codable {
    let timestamp: Date
    let event: String
    let metadata: [String: String]
}

@MainActor
final class BackupUIService {
    private let backupFileExtension = "chdb"
    private let portabilityFileExtension = "json"

    private struct PatientPortabilityExport: Codable {
        struct PatientData: Codable {
            let id: UUID
            let fullName: String
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
            let medicalComorbidities: String
            let remotePsychiatricHistory: String
            let allergies: String
            let exemptions: String
            let heartFunctionStatus: String?
            let liverFunctionStatus: String?
            let kidneyFunctionStatus: String?
            let bloodTestsTableJSON: String?
            let createdAt: Date
            let updatedAt: Date
        }

        struct ClinicalNoteData: Codable {
            let id: UUID
            let content: String
            let wellbeingScore: Int
            let createdAt: Date
            let updatedAt: Date
        }

        struct TherapyItemData: Codable {
            let id: UUID
            let medicationName: String
            let dosage: String
            let posology: String
            let isActive: Bool
            let createdAt: Date
            let updatedAt: Date
        }

        struct Metadata: Codable {
            let exportedAt: Date
            let appVersion: String
            let schemaVersion: Int
        }

        let metadata: Metadata
        let patient: PatientData
        let clinicalNotes: [ClinicalNoteData]
        let therapyItems: [TherapyItemData]
    }

    func exportBackup(modelContainer: ModelContainer) {
        guard let password = promptPassword(title: "Esporta backup cifrato", message: "Inserisci una password per proteggere il backup.", requiresConfirmation: true) else {
            return
        }

        let panel = NSSavePanel()
        panel.title = "Salva backup"
        panel.nameFieldStringValue = defaultBackupFilename()
        if let backupType = UTType(filenameExtension: backupFileExtension, conformingTo: .data) {
            panel.allowedContentTypes = [backupType]
        }
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let context = ModelContext(modelContainer)
            let backupData = try EncryptedBackupService.shared.exportBackup(from: context, password: password)
            try backupData.write(to: url, options: .atomic)
            AuditTrailService.shared.log(.backupExported, metadata: ["result": "success"])
            showInfoAlert(title: "Backup completato", message: "Backup cifrato salvato con successo.")
        } catch {
            AuditTrailService.shared.log(.backupExported, metadata: ["result": "failed"])
            showErrorAlert(title: "Backup non riuscito", error: error)
        }
    }

    func restoreBackup(modelContainer: ModelContainer) {
        let panel = NSOpenPanel()
        panel.title = "Seleziona backup"
        if let backupType = UTType(filenameExtension: backupFileExtension, conformingTo: .data) {
            panel.allowedContentTypes = [backupType]
        }
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        guard confirmRestore() else {
            return
        }

        guard let password = promptPassword(title: "Ripristina backup", message: "Inserisci la password del backup.", requiresConfirmation: false) else {
            return
        }

        do {
            let backupData = try Data(contentsOf: url)
            let context = ModelContext(modelContainer)
            try EncryptedBackupService.shared.restoreBackup(
                into: context,
                password: password,
                backupData: backupData,
                replaceExisting: true
            )
            AuditTrailService.shared.log(.backupRestored, metadata: ["result": "success"])
            showInfoAlert(title: "Ripristino completato", message: "Dati clinici ripristinati correttamente.")
        } catch EncryptedBackupError.invalidPassword {
            AuditTrailService.shared.log(.backupRestored, metadata: ["result": "failed_invalid_password"])
            showInfoAlert(title: "Password errata", message: "La password del backup non è corretta.")
        } catch {
            AuditTrailService.shared.log(.backupRestored, metadata: ["result": "failed"])
            showErrorAlert(title: "Ripristino non riuscito", error: error)
        }
    }

    func exportPatientPortabilityData(patient: Patient) {
        let panel = NSSavePanel()
        panel.title = "Esporta dati paziente"
        panel.nameFieldStringValue = defaultPatientExportFilename(for: patient)
        if let jsonType = UTType(filenameExtension: portabilityFileExtension, conformingTo: .json) {
            panel.allowedContentTypes = [jsonType]
        }
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let exportPayload = makePortabilityExport(for: patient)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(exportPayload)
            try data.write(to: url, options: .atomic)
            AuditTrailService.shared.log(
                .patientDataExported,
                metadata: [
                    "patient": AuditTrailService.shared.redactedIdentifier(for: patient.id)
                ]
            )
            showInfoAlert(title: "Export completato", message: "Dati paziente esportati in formato strutturato JSON.")
        } catch {
            showErrorAlert(title: "Export non riuscito", error: error)
        }
    }

    private func defaultBackupFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        let user = sanitizedUsername()
        return "ChironeBackup-\(user)-\(formatter.string(from: .now)).\(backupFileExtension)"
    }

    private func defaultPatientExportFilename(for patient: Patient) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        let safeName = patient.fullName
            .replacingOccurrences(of: " ", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = safeName.isEmpty ? "Paziente" : safeName
        return "ChironePatientExport-\(fallback)-\(formatter.string(from: .now)).\(portabilityFileExtension)"
    }

    private func makePortabilityExport(for patient: Patient) -> PatientPortabilityExport {
        let notes = ClinicalNote.timelineSorted(patient.clinicalNotes)
            .map {
                PatientPortabilityExport.ClinicalNoteData(
                    id: $0.id,
                    content: $0.readableContent,
                    wellbeingScore: $0.wellbeingScore,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }

        let therapy = patient.therapyItems.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        .map {
            PatientPortabilityExport.TherapyItemData(
                id: $0.id,
                medicationName: $0.medicationName,
                dosage: $0.dosage,
                posology: $0.posology,
                isActive: $0.isActive,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }

        let patientData = PatientPortabilityExport.PatientData(
            id: patient.id,
            fullName: patient.fullName,
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
            primaryDiagnosis: patient.readablePrimaryDiagnosis,
            secondaryDiagnosis: patient.readableSecondaryDiagnosis,
            medicalComorbidities: patient.readableMedicalComorbidities,
            remotePsychiatricHistory: patient.readableRemotePsychiatricHistory,
            allergies: patient.readableAllergies,
            exemptions: patient.exemptions,
            heartFunctionStatus: patient.heartFunctionStatus,
            liverFunctionStatus: patient.liverFunctionStatus,
            kidneyFunctionStatus: patient.kidneyFunctionStatus,
            bloodTestsTableJSON: patient.bloodTestsTableJSON,
            createdAt: patient.createdAt,
            updatedAt: patient.updatedAt
        )

        return PatientPortabilityExport(
            metadata: .init(
                exportedAt: .now,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                schemaVersion: 1
            ),
            patient: patientData,
            clinicalNotes: notes,
            therapyItems: therapy
        )
    }

    private func sanitizedUsername() -> String {
        let raw = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let value = String(cleaned)
        return value.isEmpty ? "User" : value
    }

    private func confirmRestore() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Ripristinare il backup?"
        alert.informativeText = "I dati clinici attuali verranno sostituiti completamente."
        alert.addButton(withTitle: "Ripristina")
        alert.addButton(withTitle: "Annulla")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func promptPassword(title: String, message: String, requiresConfirmation: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Conferma")
        alert.addButton(withTitle: "Annulla")

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        passwordField.placeholderString = "Password"
        passwordField.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let passwordLabel = NSTextField(labelWithString: "Password")
        passwordLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(passwordLabel)
        stack.addArrangedSubview(passwordField)

        var confirmField: NSSecureTextField?
        if requiresConfirmation {
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            field.placeholderString = "Conferma password"
            field.translatesAutoresizingMaskIntoConstraints = false
            let confirmLabel = NSTextField(labelWithString: "Conferma password")
            confirmLabel.textColor = .secondaryLabelColor
            stack.addArrangedSubview(confirmLabel)
            stack.addArrangedSubview(field)
            confirmField = field
        }

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: requiresConfirmation ? 104 : 64))
        accessory.translatesAutoresizingMaskIntoConstraints = false
        accessory.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
            stack.topAnchor.constraint(equalTo: accessory.topAnchor),
            stack.bottomAnchor.constraint(equalTo: accessory.bottomAnchor),
            passwordField.heightAnchor.constraint(equalToConstant: 24),
            passwordField.widthAnchor.constraint(equalToConstant: 320)
        ])

        if let confirmField {
            NSLayoutConstraint.activate([
                confirmField.heightAnchor.constraint(equalToConstant: 24),
                confirmField.widthAnchor.constraint(equalToConstant: 320)
            ])
        }

        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let password = passwordField.stringValue
        guard !password.isEmpty else {
            showInfoAlert(title: "Password mancante", message: "Inserisci una password valida.")
            return nil
        }

        if let confirmField, confirmField.stringValue != password {
            showInfoAlert(title: "Password non coincidenti", message: "Le password inserite non coincidono.")
            return nil
        }

        return password
    }

    private func showInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showErrorAlert(title: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
