import SwiftUI
import SwiftData
import AppKit
import ObjectiveC
import Combine

extension Notification.Name {
    static let patientWindowCoordinatorActivePatientDidChange = Notification.Name("patientWindowCoordinatorActivePatientDidChange")
    static let commandPaletteAddTherapyMedicationRequested = Notification.Name("commandPaletteAddTherapyMedicationRequested")
    static let commandPaletteSaveTherapyRequested = Notification.Name("commandPaletteSaveTherapyRequested")
    static let commandPaletteSaveBloodTestsRequested = Notification.Name("commandPaletteSaveBloodTestsRequested")
    static let commandPaletteSaveClinicalNoteRequested = Notification.Name("commandPaletteSaveClinicalNoteRequested")
    static let quickClinicalCaptureRequested = Notification.Name("quickClinicalCaptureRequested")
}

@MainActor
final class PatientWindowCoordinator {
    static let shared = PatientWindowCoordinator()

    private enum Settings {
        static let openPatientIDsKey = "patientWindowCoordinator.openPatientIDs"
    }

    private var windows: [UUID: NSWindow] = [:]
    private var patients: [UUID: Patient] = [:]
    private var activePatientID: UUID?
    private var lockObservation: AnyCancellable?

    private init() {
        lockObservation = AppLockViewModel.shared.$isUnlocked.sink { [weak self] unlocked in
            guard let self else { return }
            let permitsAccess = unlocked || AppLockViewModel.isUITestUnlockEnabled
            for (id, window) in self.windows {
                window.title = permitsAccess ? (self.patients[id]?.clinicalWindowTitle ?? "Cartella clinica") : "Chirone Gestionale — bloccata"
            }
        }
    }

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

        let contentView = AppLockGateView {
            PatientClinicalWindowView(patient: patient)
        }
        .modelContainer(modelContainer)

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppLockViewModel.shared.permitsClinicalAccess ? patient.clinicalWindowTitle : "Chirone Gestionale — bloccata"
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
        guard AppLockViewModel.shared.permitsClinicalAccess else { return nil }
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

    var openPatientWindowCount: Int { windows.count }

    var patientIDsWithUnsavedChanges: [UUID] {
        windows.keys.filter { PatientWindowUnsavedStateStore.shared.hasUnsavedChanges(for: $0) }
    }

    // Called only after the patient-deletion confirmation has been accepted.
    func closePatientWindow(patientID: UUID) {
        guard let window = windows.removeValue(forKey: patientID) else { return }
        patients.removeValue(forKey: patientID)
        PatientWindowUnsavedStateStore.shared.clear(for: patientID)
        AuditTrailService.shared.log(
            .patientWindowClosed,
            metadata: ["patient": AuditTrailService.shared.redactedIdentifier(for: patientID)]
        )
        window.delegate = nil
        window.close()
        persistOpenPatientIDs()
        if activePatientID == patientID { setActivePatientID(nil) }
    }

    // Forced close usato dal flusso di restore: l'utente ha già confermato
    // esplicitamente la sostituzione dei dati, quindi salta il
    // `windowShouldClose` alert per modifiche non salvate.
    func closeAllPatientWindows() {
        let openWindows = windows
        windows.removeAll()
        patients.removeAll()
        for (patientID, window) in openWindows {
            PatientWindowUnsavedStateStore.shared.clear(for: patientID)
            AuditTrailService.shared.log(
                .patientWindowClosed,
                metadata: ["patient": AuditTrailService.shared.redactedIdentifier(for: patientID)]
            )
            window.delegate = nil
            window.close()
        }
        persistOpenPatientIDs()
        setActivePatientID(nil)
    }

    func restoreOpenWindows(modelContainer: ModelContainer) {
        let storedIDs = persistedOpenPatientIDs()
        guard !storedIDs.isEmpty else { return }

        // Restored views use the container's main context; their models must too.
        let context = modelContainer.mainContext
        var restoredCount = 0
        for patientID in storedIDs {
            guard windows[patientID] == nil else { continue }
            var descriptor = FetchDescriptor<Patient>(predicate: #Predicate { $0.id == patientID })
            descriptor.fetchLimit = 1
            guard let patient = try? context.fetch(descriptor).first else { continue }
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
    // NSWindowDelegate callbacks always arrive on the main thread,
    // so closures are @MainActor to match the coordinator's isolation.
    let onBecomeKey: @MainActor (UUID) -> Void
    let onResignKey: @MainActor (UUID) -> Void
    let onClose: @MainActor (UUID) -> Void

    init(
        patientID: UUID,
        onBecomeKey: @escaping @MainActor (UUID) -> Void,
        onResignKey: @escaping @MainActor (UUID) -> Void,
        onClose: @escaping @MainActor (UUID) -> Void
    ) {
        self.patientID = patientID
        self.onBecomeKey = onBecomeKey
        self.onResignKey = onResignKey
        self.onClose = onClose
    }

    func windowDidBecomeKey(_ notification: Notification) {
        MainActor.assumeIsolated { onBecomeKey(patientID) }
    }

    func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated { onResignKey(patientID) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            guard PatientWindowUnsavedStateStore.shared.hasUnsavedChanges(for: patientID) else {
                return true
            }

            let alert = NSAlert()
            alert.messageText = "Chiudere senza salvare?"
            alert.informativeText = "Sono presenti modifiche non salvate nella scheda clinica. Se chiudi ora, i dati non salvati andranno persi."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Continua a modificare")
            alert.addButton(withTitle: "Chiudi senza salvare")
            alert.buttons[1].hasDestructiveAction = true

            let response = alert.runModal()
            return response == .alertSecondButtonReturn
        }
    }

    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            PatientWindowUnsavedStateStore.shared.clear(for: patientID)
            AuditTrailService.shared.log(
                .patientWindowClosed,
                metadata: ["patient": AuditTrailService.shared.redactedIdentifier(for: patientID)]
            )
            onClose(patientID)
        }
    }
}
