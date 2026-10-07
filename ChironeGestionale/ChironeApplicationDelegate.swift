import AppKit

@MainActor
final class ChironeApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for window in sender.windows { window.makeFirstResponder(nil) }
        let hasClinicalDrafts = !PatientWindowCoordinator.shared.patientIDsWithUnsavedChanges.isEmpty
        let hasDocumentDrafts = ReportPreviewWindowCoordinator.shared.hasUnexportedChanges ||
            PrescriptionPreviewWindowCoordinator.shared.hasUnexportedChanges
        let hasOpenSheet = sender.windows.contains { $0.sheetParent != nil }
        guard hasClinicalDrafts || hasDocumentDrafts || hasOpenSheet else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uscire da Chirone?"
        alert.informativeText = "Sono presenti bozze modificate o schede ancora aperte. Le modifiche non salvate o esportate potrebbero andare perse."
        alert.addButton(withTitle: "Continua a lavorare")
        alert.addButton(withTitle: "Esci senza salvare")
        alert.buttons[1].hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
