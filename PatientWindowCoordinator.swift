import SwiftUI
import SwiftData
import AppKit
import ObjectiveC

extension Notification.Name {
    static let patientWindowCoordinatorActivePatientDidChange = Notification.Name("patientWindowCoordinatorActivePatientDidChange")
    static let commandPaletteAddTherapyMedicationRequested = Notification.Name("commandPaletteAddTherapyMedicationRequested")
    static let commandPaletteSaveTherapyRequested = Notification.Name("commandPaletteSaveTherapyRequested")
    static let commandPaletteSaveBloodTestsRequested = Notification.Name("commandPaletteSaveBloodTestsRequested")
    static let commandPaletteSaveClinicalNoteRequested = Notification.Name("commandPaletteSaveClinicalNoteRequested")
    static let quickClinicalCaptureRequested = Notification.Name("quickClinicalCaptureRequested")
}

final class PatientWindowCoordinator {
    static let shared = PatientWindowCoordinator()

    private enum Settings {
        static let openPatientIDsKey = "patientWindowCoordinator.openPatientIDs"
    }

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
                self?.persistOpenPatientIDs()
                if self?.activePatientID == patientID {
                    self?.setActivePatientID(nil)
                }
            }
        )

        window.delegate = delegate
        objc_setAssociatedObject(window, "patientWindowDelegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        windows[patient.id] = window
        patients[patient.id] = patient
        persistOpenPatientIDs()
        setActivePatientID(patient.id)
        AuditTrailService.shared.log(
            .patientWindowOpened,
            metadata: ["patient": AuditTrailService.shared.redactedIdentifier(for: patient.id)]
        )
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

    func restoreOpenWindows(modelContainer: ModelContainer) {
        let storedIDs = persistedOpenPatientIDs()
        guard !storedIDs.isEmpty else { return }

        let context = ModelContext(modelContainer)
        let fetchedPatients = (try? context.fetch(FetchDescriptor<Patient>())) ?? []
        let patientByID = Dictionary(uniqueKeysWithValues: fetchedPatients.map { ($0.id, $0) })

        var restoredCount = 0
        for patientID in storedIDs {
            guard windows[patientID] == nil, let patient = patientByID[patientID] else { continue }
            open(patient: patient, modelContainer: modelContainer)
            restoredCount += 1
        }

        if restoredCount > 0 {
            AuditTrailService.shared.log(
                .patientWindowsRestored,
                metadata: ["count": "\(restoredCount)"]
            )
        }
    }

    private func persistOpenPatientIDs() {
        let ids = windows.keys.map(\.uuidString).sorted()
        UserDefaults.standard.set(ids, forKey: Settings.openPatientIDsKey)
    }

    private func persistedOpenPatientIDs() -> [UUID] {
        let rawIDs = UserDefaults.standard.stringArray(forKey: Settings.openPatientIDsKey) ?? []
        return rawIDs.compactMap(UUID.init(uuidString:))
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
        AuditTrailService.shared.log(
            .patientWindowClosed,
            metadata: ["patient": AuditTrailService.shared.redactedIdentifier(for: patientID)]
        )
        onClose(patientID)
    }
}
