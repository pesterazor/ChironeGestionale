import Foundation
import SwiftData
import AppKit
import UniformTypeIdentifiers
import CryptoKit

enum AuditEvent: String {
    case patientWindowOpened = "patient_window_opened"
    case patientWindowClosed = "patient_window_closed"
    case reportExported = "report_exported"
    case reportPrinted = "report_printed"
    case prescriptionExported = "prescription_exported"
    case prescriptionPrinted = "prescription_printed"
    case patientDataExported = "patient_data_exported"
    case backupExported = "backup_exported"
    case backupRestored = "backup_restored"
    case appUnlocked = "app_unlocked"
    case appLockFailed = "app_lock_failed"
    case appLocked = "app_locked"
    case commandPaletteActionExecuted = "command_palette_action_executed"
    case patientWindowsRestored = "patient_windows_restored"

    var displayName: String {
        switch self {
        case .patientWindowOpened: return "Apertura cartella"
        case .patientWindowClosed: return "Chiusura cartella"
        case .reportExported: return "Export referto"
        case .reportPrinted: return "Stampa referto"
        case .prescriptionExported: return "Export ricetta"
        case .prescriptionPrinted: return "Stampa ricetta"
        case .patientDataExported: return "Export dati paziente"
        case .backupExported: return "Export backup"
        case .backupRestored: return "Restore backup"
        case .appUnlocked: return "App sbloccata"
        case .appLockFailed: return "Sblocco fallito"
        case .appLocked: return "App bloccata"
        case .commandPaletteActionExecuted: return "Command palette eseguita"
        case .patientWindowsRestored: return "Sessione finestre ripristinata"
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
        static let retentionEnforcementInterval: TimeInterval = 300
    }

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logFileURL: URL
    private var pendingRecords: [AuditRecord] = []
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var lastRetentionEnforcementAt: Date?

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let baseDirectory: URL
        #if DEBUG
        let testDirectory = NSClassFromString("XCTestCase") != nil
            ? fileManager.temporaryDirectory.appendingPathComponent("ChironeAuditTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            : nil
        #else
        let testDirectory: URL? = nil
        #endif
        if let testDirectory {
            baseDirectory = testDirectory
        } else if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseDirectory = appSupport.appendingPathComponent("ChironeGestionale", isDirectory: true)
        } else {
            baseDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ChironeGestionale", isDirectory: true)
        }

        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        logFileURL = baseDirectory.appendingPathComponent("audit.log", isDirectory: false)
        registerLifecycleObservers()
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
        flushPendingWrites()
        enforceRetentionPolicy()
    }

    func log(_ event: AuditEvent, metadata: [String: String] = [:]) {
        let record = AuditRecord(timestamp: Date(), event: event.rawValue, metadata: metadata)
        pendingRecords.append(record)
    }

    func redactedIdentifier(for id: UUID) -> String {
        let digest = SHA256.hash(data: Data(id.uuidString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    func readRecords(since: Date? = nil, event: AuditEvent? = nil, limit: Int = 500) -> [AuditRecord] {
        flushPendingWrites()

        guard let data = try? Data(contentsOf: logFileURL),
              let content = String(data: data, encoding: .utf8)
        else {
            return []
        }

        let maxResults = max(1, limit)
        let lines = content.split(separator: "\n")
        var parsed: [AuditRecord] = []
        parsed.reserveCapacity(min(maxResults, lines.count))

        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let record = try? decoder.decode(AuditRecord.self, from: lineData)
            else {
                continue
            }

            if let since, record.timestamp < since { continue }
            if let event, record.event != event.rawValue { continue }
            parsed.append(record)
            if parsed.count >= maxResults {
                break
            }
        }

        return parsed
    }

    func purgeAuditLogNow() {
        flushPendingWrites()
        enforceRetentionPolicy()
    }

    private func flushPendingWrites() {
        guard !pendingRecords.isEmpty else { return }
        let snapshot = pendingRecords
        pendingRecords.removeAll(keepingCapacity: true)

        var lines: [String] = []
        lines.reserveCapacity(snapshot.count)
        for record in snapshot {
            guard let data = try? encoder.encode(record),
                  let text = String(data: data, encoding: .utf8)
            else {
                continue
            }
            lines.append(text)
        }
        guard !lines.isEmpty else { return }
        let payload = (lines.joined(separator: "\n") + "\n").data(using: .utf8)
        guard let payload else { return }

        if !fileManager.fileExists(atPath: logFileURL.path) {
            fileManager.createFile(atPath: logFileURL.path, contents: payload)
            maybeEnforceRetentionPolicy()
            return
        }
        do {
            let handle = try FileHandle(forWritingTo: logFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
            maybeEnforceRetentionPolicy()
        } catch {
            // Best-effort logging: errors are intentionally ignored.
        }
    }

    private func registerLifecycleObservers() {
        let terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.flushPendingWrites()
            }
        }
        lifecycleObservers.append(terminateObserver)

        let sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.flushPendingWrites()
            }
        }
        lifecycleObservers.append(sleepObserver)
    }

    private func maybeEnforceRetentionPolicy() {
        let now = Date()
        if let lastRetentionEnforcementAt,
           now.timeIntervalSince(lastRetentionEnforcementAt) < Settings.retentionEnforcementInterval {
            return
        }
        lastRetentionEnforcementAt = now
        enforceRetentionPolicy()
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
    // Commands can recreate their service; serialize operations across instances.
    private static var isBackupOperationRunning = false
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
            let medicalHistory: String
            let medicalComorbidities: String
            let remotePsychiatricHistory: String
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
        let phq9Assessments: [BackupPayload.PHQ9AssessmentRecord]
        let gad7Assessments: [BackupPayload.GAD7AssessmentRecord]
        let mdqAssessments: [BackupPayload.MDQAssessmentRecord]
        let beckAssessments: [BackupPayload.BeckAssessmentRecord]
        let madrsAssessments: [BackupPayload.MADRSAssessmentRecord]
    }

    func exportBackup(modelContainer: ModelContainer) {
        guard AppLockViewModel.shared.permitsClinicalAccess, !Self.isBackupOperationRunning else { return }
        Self.isBackupOperationRunning = true
        Task {
            defer { Self.isBackupOperationRunning = false }
            guard AppLockViewModel.shared.permitsClinicalAccess,
                  confirmExportWithUnsavedChanges(patientID: nil),
                  AppLockViewModel.shared.permitsClinicalAccess,
                  let password = promptPassword(title: "Esporta backup cifrato", message: "Inserisci una password per proteggere il backup.", requiresConfirmation: true),
                  AppLockViewModel.shared.permitsClinicalAccess else { return }

            let panel = NSSavePanel()
            panel.title = "Salva backup"
            panel.nameFieldStringValue = defaultBackupFilename()
            if let backupType = UTType(filenameExtension: backupFileExtension, conformingTo: .data) {
                panel.allowedContentTypes = [backupType]
            }
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url,
                  AppLockViewModel.shared.permitsClinicalAccess else { return }

            let progressPanel = makeProgressPanel(message: "Backup in corso…")
            defer { progressPanel.close() }
            do {
                let service = EncryptedBackupService.shared
                let payload = try service.makePayload(from: modelContainer.mainContext)
                // SwiftData stays on its actor; PBKDF2, AES-GCM and disk I/O do not.
                try await Task.detached(priority: .userInitiated) {
                    let scopedAccess = url.startAccessingSecurityScopedResource()
                    defer { if scopedAccess { url.stopAccessingSecurityScopedResource() } }
                    let backupData = try service.encryptPayload(payload, password: password)
                    try backupData.write(to: url, options: .atomic)
                }.value
                progressPanel.close()
                AuditTrailService.shared.log(.backupExported, metadata: ["result": "success"])
                guard AppLockViewModel.shared.permitsClinicalAccess else { return }
                showInfoAlert(title: "Backup completato", message: "Backup cifrato salvato con successo.")
            } catch {
                progressPanel.close()
                AuditTrailService.shared.log(.backupExported, metadata: ["result": "failed"])
                guard AppLockViewModel.shared.permitsClinicalAccess else { return }
                showErrorAlert(title: "Backup non riuscito", error: error)
            }
        }
    }

    func restoreBackup(modelContainer: ModelContainer) {
        guard AppLockViewModel.shared.permitsClinicalAccess, !Self.isBackupOperationRunning else { return }
        Self.isBackupOperationRunning = true
        Task {
            defer { Self.isBackupOperationRunning = false }
            guard AppLockViewModel.shared.permitsClinicalAccess else { return }
            let panel = NSOpenPanel()
            panel.title = "Seleziona backup"
            if let backupType = UTType(filenameExtension: backupFileExtension, conformingTo: .data) {
                panel.allowedContentTypes = [backupType]
            }
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false

            guard panel.runModal() == .OK, let url = panel.url,
                  AppLockViewModel.shared.permitsClinicalAccess,
                  let password = promptPassword(title: "Ripristina backup", message: "Inserisci la password del backup.", requiresConfirmation: false),
                  AppLockViewModel.shared.permitsClinicalAccess else { return }

            let progressPanel = makeProgressPanel(message: "Verifica del backup in corso…")
            defer { progressPanel.close() }
            do {
                let service = EncryptedBackupService.shared
                let prepared = try await Task.detached(priority: .userInitiated) {
                    let scopedAccess = url.startAccessingSecurityScopedResource()
                    defer { if scopedAccess { url.stopAccessingSecurityScopedResource() } }
                    let backupData = try Data(contentsOf: url)
                    return try service.decryptBackup(password: password, backupData: backupData)
                }.value
                guard AppLockViewModel.shared.permitsClinicalAccess else { return }
                try service.validatePayload(prepared.payload)
                progressPanel.close()

                // Password and archive validation precede any discarded draft or closed window.
                let coordinator = PatientWindowCoordinator.shared
                guard confirmRestore(
                    openWindowsCount: coordinator.openPatientWindowCount,
                    unsavedWindowsCount: coordinator.patientIDsWithUnsavedChanges.count
                ), AppLockViewModel.shared.permitsClinicalAccess else { return }
                guard ReportPreviewWindowCoordinator.shared.confirmClosingIfNeeded(),
                      AppLockViewModel.shared.permitsClinicalAccess,
                      PrescriptionPreviewWindowCoordinator.shared.confirmClosingIfNeeded(),
                      AppLockViewModel.shared.permitsClinicalAccess else { return }
                coordinator.closeAllPatientWindows()
                ReportPreviewWindowCoordinator.shared.closeIfPresent()
                PrescriptionPreviewWindowCoordinator.shared.closeIfPresent()
                try service.restorePreparedBackup(prepared, into: modelContainer.mainContext)
                AuditTrailService.shared.log(.backupRestored, metadata: ["result": "success"])
                showInfoAlert(title: "Ripristino completato", message: "Dati clinici ripristinati correttamente.")
            } catch EncryptedBackupError.invalidPassword {
                progressPanel.close()
                AuditTrailService.shared.log(.backupRestored, metadata: ["result": "failed_invalid_password"])
                guard AppLockViewModel.shared.permitsClinicalAccess else { return }
                showInfoAlert(title: "Backup non verificato", message: "La password non è corretta oppure il file di backup non è integro. Le cartelle aperte e i dati attuali sono stati conservati.")
            } catch {
                progressPanel.close()
                AuditTrailService.shared.log(.backupRestored, metadata: ["result": "failed"])
                guard AppLockViewModel.shared.permitsClinicalAccess else { return }
                showErrorAlert(title: "Ripristino non riuscito", error: error)
            }
        }
    }

    private func makeProgressPanel(message: String) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 64),
            styleMask: [.utilityWindow, .titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Chirone Gestionale"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .regular
        indicator.startAnimation(nil)
        indicator.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: message)
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [indicator, label])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let contentView = panel.contentView {
            contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                indicator.widthAnchor.constraint(equalToConstant: 16),
                indicator.heightAnchor.constraint(equalToConstant: 16)
            ])
        }

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        return panel
    }

    func exportPatientPortabilityData(patient: Patient) {
        guard AppLockViewModel.shared.permitsClinicalAccess, !Self.isBackupOperationRunning else { return }
        Self.isBackupOperationRunning = true
        defer { Self.isBackupOperationRunning = false }
        guard confirmExportWithUnsavedChanges(patientID: patient.id),
              AppLockViewModel.shared.permitsClinicalAccess else { return }

        let panel = NSSavePanel()
        panel.title = "Esporta dati paziente"
        panel.message = "Il file JSON contiene dati clinici in chiaro, senza password."
        panel.nameFieldStringValue = defaultPatientExportFilename(for: patient)
        if let jsonType = UTType(filenameExtension: portabilityFileExtension, conformingTo: .json) {
            panel.allowedContentTypes = [jsonType]
        }
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url,
              AppLockViewModel.shared.permitsClinicalAccess else { return }
        let scopedAccess = url.startAccessingSecurityScopedResource()
        defer { if scopedAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try makePatientPortabilityData(for: patient)
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

    func makePatientPortabilityData(for patient: Patient) throws -> Data {
        let exportPayload = try makePortabilityExport(for: patient)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exportPayload)
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

    private func makePortabilityExport(for patient: Patient) throws -> PatientPortabilityExport {
        // Share the backup's complete mappings and strict decryption/validation.
        let payload = try EncryptedBackupService.shared.makePayload(for: patient)
        guard let record = payload.patients.first else { throw EncryptedBackupError.invalidRecordData }
        let notes = payload.clinicalNotes.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }.map {
            PatientPortabilityExport.ClinicalNoteData(
                id: $0.id,
                content: $0.content,
                wellbeingScore: $0.wellbeingScore,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let therapy = payload.therapyItems.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }.map {
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
            id: record.id,
            fullName: patient.fullName,
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
            secondaryDiagnosis: record.secondaryDiagnosis,
            medicalHistory: record.medicalHistory,
            medicalComorbidities: record.medicalComorbidities ?? "",
            remotePsychiatricHistory: record.remotePsychiatricHistory ?? "",
            allergies: record.allergies,
            exemptions: record.exemptions,
            currentTherapySummary: record.currentTherapySummary,
            heartFunctionStatus: record.heartFunctionStatus,
            liverFunctionStatus: record.liverFunctionStatus,
            kidneyFunctionStatus: record.kidneyFunctionStatus,
            bloodTestsTableJSON: record.bloodTestsTableJSON,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
        return PatientPortabilityExport(
            metadata: .init(
                exportedAt: payload.exportedAt,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                schemaVersion: 2
            ),
            patient: patientData,
            clinicalNotes: notes,
            therapyItems: therapy,
            phq9Assessments: payload.phq9Assessments,
            gad7Assessments: payload.gad7Assessments,
            mdqAssessments: payload.mdqAssessments,
            beckAssessments: payload.beckAssessments ?? [],
            madrsAssessments: payload.madrsAssessments ?? []
        )
    }

    private func confirmExportWithUnsavedChanges(patientID: UUID?) -> Bool {
        // Commit active field editors before inspecting the draft indicators.
        for window in NSApp.windows { window.makeFirstResponder(nil) }
        let hasUnsavedChanges: Bool
        if let patientID {
            hasUnsavedChanges = PatientWindowUnsavedStateStore.shared.hasUnsavedChanges(for: patientID)
        } else {
            hasUnsavedChanges = !PatientWindowCoordinator.shared.patientIDsWithUnsavedChanges.isEmpty
        }
        // Assessment/new-patient sheets can contain drafts that are not models yet.
        let hasOpenSheet = NSApp.windows.contains { $0.sheetParent != nil }
        guard hasUnsavedChanges || hasOpenSheet else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Esportare i dati già salvati?"
        alert.informativeText = "Sono presenti modifiche non salvate o schede ancora aperte. Le bozze non confermate nelle schede non verranno incluse nell’esportazione. Puoi tornare alle schede per salvarle prima di continuare."
        alert.addButton(withTitle: "Torna alle schede")
        alert.addButton(withTitle: "Esporta dati salvati")
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func sanitizedUsername() -> String {
        let raw = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let value = String(cleaned)
        return value.isEmpty ? "User" : value
    }

    private func confirmRestore(openWindowsCount: Int, unsavedWindowsCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Ripristinare il backup?"

        var info = "I dati clinici attuali verranno sostituiti completamente."
        if openWindowsCount > 0 {
            let label = openWindowsCount == 1 ? "1 cartella clinica aperta verrà chiusa" : "\(openWindowsCount) cartelle cliniche aperte verranno chiuse"
            info += "\n\n\(label) automaticamente prima del ripristino."
        }
        if unsavedWindowsCount > 0 {
            let label = unsavedWindowsCount == 1 ? "1 cartella ha modifiche non salvate" : "\(unsavedWindowsCount) cartelle hanno modifiche non salvate"
            info += "\n⚠️ \(label): le modifiche andranno perse."
        }
        alert.informativeText = info

        alert.addButton(withTitle: "Annulla")
        alert.addButton(withTitle: "Ripristina")
        alert.buttons[1].hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
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
