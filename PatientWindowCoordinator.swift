import SwiftUI
import SwiftData
import AppKit
import ObjectiveC

extension Notification.Name {
    static let patientWindowCoordinatorActivePatientDidChange = Notification.Name("patientWindowCoordinatorActivePatientDidChange")
}

final class PatientWindowCoordinator {
    static let shared = PatientWindowCoordinator()

    private var windows: [UUID: NSWindow] = [:]
    private var patients: [UUID: Patient] = [:]
    private var activePatientID: UUID?

    private init() {}

    private func setActivePatientID(_ newID: UUID?) {
        guard activePatientID != newID else { return }
        activePatientID = newID
        NotificationCenter.default.post(name: .patientWindowCoordinatorActivePatientDidChange, object: self)
    }

    func open(patient: Patient, modelContainer: ModelContainer) {
        if let existingWindow = windows[patient.id] {
            existingWindow.makeKeyAndOrderFront(nil)
            setActivePatientID(patient.id)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = PatientClinicalWindowView(patient: patient)
            .modelContainer(modelContainer)

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = patient.clinicalWindowTitle
        window.setContentSize(NSSize(width: 980, height: 720))
        window.minSize = NSSize(width: 820, height: 600)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        let delegate = PatientWindowDelegate(
            patientID: patient.id,
            onBecomeKey: { [weak self] patientID in
                self?.setActivePatientID(patientID)
            },
            onResignKey: { [weak self] patientID in
                guard self?.activePatientID == patientID else { return }
                self?.setActivePatientID(nil)
            },
            onClose: { [weak self] patientID in
                self?.windows.removeValue(forKey: patientID)
                self?.patients.removeValue(forKey: patientID)
                if self?.activePatientID == patientID {
                    self?.setActivePatientID(nil)
                }
            }
        )

        window.delegate = delegate
        objc_setAssociatedObject(window, "patientWindowDelegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        windows[patient.id] = window
        patients[patient.id] = patient
        setActivePatientID(patient.id)
        NSApp.activate(ignoringOtherApps: true)
    }

    func activePatient() -> Patient? {
        if activePatientID == nil,
           let keyWindow = NSApp.keyWindow,
           let match = windows.first(where: { $0.value === keyWindow }) {
            setActivePatientID(match.key)
        }
        if let activePatientID, let active = patients[activePatientID] {
            return active
        }

        guard let keyWindow = NSApp.keyWindow else { return nil }
        guard let match = windows.first(where: { $0.value === keyWindow }) else { return nil }
        return patients[match.key]
    }
}

private final class PatientWindowDelegate: NSObject, NSWindowDelegate {
    let patientID: UUID
    let onBecomeKey: (UUID) -> Void
    let onResignKey: (UUID) -> Void
    let onClose: (UUID) -> Void

    init(
        patientID: UUID,
        onBecomeKey: @escaping (UUID) -> Void,
        onResignKey: @escaping (UUID) -> Void,
        onClose: @escaping (UUID) -> Void
    ) {
        self.patientID = patientID
        self.onBecomeKey = onBecomeKey
        self.onResignKey = onResignKey
        self.onClose = onClose
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onBecomeKey(patientID)
    }

    func windowDidResignKey(_ notification: Notification) {
        onResignKey(patientID)
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
