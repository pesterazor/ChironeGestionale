import Foundation
import SwiftData
import AppKit
import UniformTypeIdentifiers

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
            showInfoAlert(title: "Backup completato", message: "Backup cifrato salvato con successo.")
        } catch {
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
            showInfoAlert(title: "Ripristino completato", message: "Dati clinici ripristinati correttamente.")
        } catch EncryptedBackupError.invalidPassword {
            showInfoAlert(title: "Password errata", message: "La password del backup non è corretta.")
        } catch {
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
