//
//  ChironeGestionaleApp.swift
//  ChironeGestionale
//
//  Created by Peste on 21/04/2026.
//

import SwiftUI
import SwiftData
import AppKit
import Combine

@MainActor
private final class PrintCommandState: ObservableObject {
    @Published private(set) var canPrintReport = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let notifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification,
            .patientWindowCoordinatorActivePatientDidChange,
            NSMenu.didBeginTrackingNotification
        ]

        for name in notifications {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] _ in
                    self?.refresh()
                }
                .store(in: &cancellables)
        }

        refresh()
    }

    func refresh() {
        let newValue = PatientWindowCoordinator.shared.activePatient() != nil
        if canPrintReport != newValue {
            canPrintReport = newValue
        }
    }
}

private struct PreferencesView: View {
    @AppStorage("security.reauthTimeoutMinutes") private var reauthTimeoutMinutes = 5
    @AppStorage("report.doctorFullName") private var doctorFullName = ""
    @AppStorage("report.doctorQualification") private var doctorQualification = ""
    @AppStorage("report.doctorAddress") private var doctorAddress = ""
    @AppStorage("report.doctorPhoneEmail") private var doctorPhoneEmail = ""
    @AppStorage("report.notesInReport") private var reportNotesInReport = 3
    private let quickTimeouts = [1, 5, 10, 15, 30, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Preferenze")
                .font(.title2.weight(.semibold))

            GroupBox("Intestazione referti") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Nome e cognome medico", text: $doctorFullName, prompt: Text("Dr.ssa/Dr. Nome Cognome"))
                    TextField("Qualifica", text: $doctorQualification, prompt: Text("Medico Chirurgo - Specialista in Psichiatria"))
                    TextField("Indirizzo studio", text: $doctorAddress, prompt: Text("Via..., CAP Città (Prov.)"))
                    TextField("Contatti", text: $doctorPhoneEmail, prompt: Text("Telefono - Email/PEC"))

                    HStack {
                        Text("Numero note nel referto")
                        Spacer()
                        Stepper(value: $reportNotesInReport, in: 2...5) {
                            Text("\(reportNotesInReport)")
                                .monospacedDigit()
                                .frame(minWidth: 36, alignment: .trailing)
                        }
                        .labelsHidden()
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(10)
            }

            GroupBox("Sicurezza") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Nuova autenticazione")
                            .font(.headline)
                        Spacer()
                        Text(timeoutLabel(minutes: reauthTimeoutMinutes))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }

                    HStack {
                        Text("Timeout")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Stepper(value: $reauthTimeoutMinutes, in: 1...240) {
                            Text("\(reauthTimeoutMinutes) min")
                                .monospacedDigit()
                                .frame(minWidth: 80, alignment: .trailing)
                        }
                    }

                    HStack(spacing: 8) {
                        ForEach(quickTimeouts, id: \.self) { value in
                            Button("\(value)m") {
                                reauthTimeoutMinutes = value
                            }
                            .buttonStyle(.bordered)
                            .tint(reauthTimeoutMinutes == value ? .accentColor : nil)
                        }
                    }

                    Text("Quando l'app torna attiva dopo questo intervallo, viene richiesto di nuovo Touch ID o la password di sistema.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 280, alignment: .topLeading)
    }

    private func timeoutLabel(minutes: Int) -> String {
        if minutes == 1 {
            return "1 minuto"
        }
        return "\(minutes) minuti"
    }
}

@main
struct ChironeGestionaleApp: App {
    private let backupUIService = BackupUIService()
    @AppStorage("report.notesInReport") private var reportNotesInReport = 3
    @StateObject private var printCommandState = PrintCommandState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Patient.self,
            ClinicalNote.self,
            TherapyMedication.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Fallback per store incompatibile durante sviluppo: evita crash all'avvio.
            // Da sostituire con migrazioni versionate nello sprint di hardening.
            do {
                let inMemoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
            } catch {
                fatalError("Could not create ModelContainer (persistent/inMemory): \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppLockGateView {
                ContentView()
            }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(before: .printItem) {
                Button {
                    exportActivePatientReport()
                } label: {
                    Label("Esporta referto…", systemImage: "doc.richtext")
                }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(!printCommandState.canPrintReport)
            }

            CommandMenu("Backup") {
                Button("Esporta backup cifrato…") {
                    backupUIService.exportBackup(modelContainer: sharedModelContainer)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Ripristina backup cifrato…") {
                    backupUIService.restoreBackup(modelContainer: sharedModelContainer)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            PreferencesView()
        }
    }

    private func exportActivePatientReport() {
        guard let patient = PatientWindowCoordinator.shared.activePatient() else {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Nessuna scheda clinica attiva"
            alert.informativeText = "Apri o attiva una scheda clinica paziente prima di esportare il referto."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        do {
            let document = try PatientReportService.shared.makeReportDocument(
                for: patient,
                latestNotesCount: reportNotesInReport
            )
            ReportPreviewWindowCoordinator.shared.present(
                document: document,
                title: patient.fullName
            )
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Errore esportazione referto"
            alert.informativeText = "Impossibile generare l'anteprima del referto clinico."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
