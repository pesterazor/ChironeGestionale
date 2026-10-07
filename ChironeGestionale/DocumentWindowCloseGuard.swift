import AppKit

@MainActor
final class DocumentWindowCloseGuard: NSObject, NSWindowDelegate {
    var hasUnexportedChanges = false
    var onClose: (() -> Void)?

    func permitsClosing(confirmDiscard: () -> Bool) -> Bool {
        !hasUnexportedChanges || confirmDiscard()
    }

    func confirmClosing() -> Bool {
        permitsClosing {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Chiudere la bozza modificata?"
            alert.informativeText = "Le modifiche non esportate non verranno conservate."
            alert.addButton(withTitle: "Mantieni aperta")
            alert.addButton(withTitle: "Chiudi senza salvare")
            return alert.runModal() == .alertSecondButtonReturn
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { confirmClosing() }

    func windowWillClose(_ notification: Notification) {
        hasUnexportedChanges = false
        onClose?()
    }
}
