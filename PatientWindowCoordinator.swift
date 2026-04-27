import SwiftUI
import SwiftData
import AppKit
import ObjectiveC

final class PatientWindowCoordinator {
    static let shared = PatientWindowCoordinator()

    private var windows: [UUID: NSWindow] = [:]

    private init() {}

    func open(patient: Patient, modelContainer: ModelContainer) {
        if let existingWindow = windows[patient.id] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = PatientClinicalWindowView(patient: patient)
            .modelContainer(modelContainer)

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = patient.displayTitle
        window.setContentSize(NSSize(width: 980, height: 720))
        window.minSize = NSSize(width: 820, height: 600)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        let delegate = PatientWindowDelegate(patientID: patient.id) { [weak self] patientID in
            self?.windows.removeValue(forKey: patientID)
        }

        window.delegate = delegate
        objc_setAssociatedObject(window, "patientWindowDelegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        windows[patient.id] = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class PatientWindowDelegate: NSObject, NSWindowDelegate {
    let patientID: UUID
    let onClose: (UUID) -> Void

    init(patientID: UUID, onClose: @escaping (UUID) -> Void) {
        self.patientID = patientID
        self.onClose = onClose
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !PatientWindowUnsavedStateStore.shared.hasUnsavedChanges(for: patientID) {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Chiudere senza salvare?"
        alert.informativeText = "Sono presenti modifiche non salvate nella scheda clinica. Se chiudi ora, i dati non salvati andranno persi."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Chiudi senza salvare")
        alert.addButton(withTitle: "Annulla")

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        PatientWindowUnsavedStateStore.shared.clear(for: patientID)
        onClose(patientID)
    }
}
