import Foundation
import SwiftData
import AppKit
import UniformTypeIdentifiers
import CryptoKit

enum AuditEvent: String {
    case patientWindowOpened = "patient_window_opened"
    case patientWindowClosed = "patient_window_closed"
    case reportExported = "report_exported"
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

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let logFileURL: URL

    private init() {
        encoder.dateEncodingStrategy = .iso8601

        let baseDirectory: URL
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseDirectory = appSupport.appendingPathComponent("ChironeGestionale", isDirectory: true)
        } else {
            baseDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ChironeGestionale", isDirectory: true)
        }

        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        logFileURL = baseDirectory.appendingPathComponent("audit.log", isDirectory: false)
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
        } catch {
            // Best-effort logging: errors are intentionally ignored.
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

    private func defaultBackupFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        let user = sanitizedUsername()
        return "ChironeBackup-\(user)-\(formatter.string(from: .now)).\(backupFileExtension)"
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
