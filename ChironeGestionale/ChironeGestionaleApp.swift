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
    @Published private(set) var activePatientName: String?
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
        let activePatient = PatientWindowCoordinator.shared.activePatient()
        let newValue = activePatient != nil
        if canPrintReport != newValue {
            canPrintReport = newValue
        }
        let resolvedName = activePatient?.fullName
        if activePatientName != resolvedName {
            activePatientName = resolvedName
        }
    }
}

@MainActor
final class CommandPaletteState: ObservableObject {
    @Published var isPresented = false

    func present() {
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}

private struct PreferencesView: View {
    private struct CommandPaletteStats {
        let totalExecutions: Int
        let medianLatencyMs: Int?
        let topActions: [(action: String, count: Int)]
    }

    @AppStorage("security.reauthTimeoutMinutes") private var reauthTimeoutMinutes = 5
    @AppStorage("report.doctorFullName") private var doctorFullName = ""
    @AppStorage("report.doctorQualification") private var doctorQualification = ""
    @AppStorage("report.doctorRegistration") private var doctorRegistration = ""
    @AppStorage("report.doctorAddress") private var doctorAddress = ""
    @AppStorage("report.doctorPhoneEmail") private var doctorPhoneEmail = ""
    @AppStorage("report.notesInReport") private var reportNotesInReport = 3
    private let quickTimeouts = [1, 5, 10, 15, 30, 60]
    @State private var selectedAuditEventRaw = "all"
    @State private var auditFromDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var auditRecords: [AuditRecord] = []
    @State private var auditRetentionDays = AuditTrailService.shared.retentionDays
    @State private var auditMaxRecords = AuditTrailService.shared.maxRecords
    @State private var commandPaletteRecords: [AuditRecord] = []

    private var commandPaletteStats: CommandPaletteStats {
        let latencies: [Int] = commandPaletteRecords.compactMap { record in
            guard let raw = record.metadata["latency_ms"] else { return nil }
            return Int(raw)
        }
        .filter { $0 >= 0 }
        .sorted()

        let medianLatencyMs: Int? = {
            guard !latencies.isEmpty else { return nil }
            let mid = latencies.count / 2
            if latencies.count.isMultiple(of: 2) {
                return (latencies[mid - 1] + latencies[mid]) / 2
            }
            return latencies[mid]
        }()

        let grouped = Dictionary(grouping: commandPaletteRecords) { record -> String in
            record.metadata["action"] ?? "unknown"
        }
        let topActions = grouped
            .map { key, value in (action: key, count: value.count) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.action < rhs.action
            }
            .prefix(3)
            .map { $0 }

        return CommandPaletteStats(
            totalExecutions: commandPaletteRecords.count,
            medianLatencyMs: medianLatencyMs,
            topActions: topActions
        )
    }

    var body: some View {
        let stats = commandPaletteStats
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Preferenze")
                    .font(.title2.weight(.semibold))

                GroupBox("Intestazione referti") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Nome e cognome medico", text: $doctorFullName, prompt: Text("Dr.ssa/Dr. Nome Cognome"))
                        TextField("Qualifica", text: $doctorQualification, prompt: Text("Medico Chirurgo - Specialista in Psichiatria"))
                        TextField("Iscrizione all'albo", text: $doctorRegistration, prompt: Text("Ordine dei Medici di… n. …"))
                        TextField("Indirizzo studio", text: $doctorAddress, prompt: Text("Via..., CAP Città (Prov.)"))
                        TextField("Contatti", text: $doctorPhoneEmail, prompt: Text("Telefono - Email/PEC"))

                        HStack {
                            Text("Numero massimo note recenti (se incluse)")
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

                GroupBox("Audit trail") {
                    VStack(alignment: .leading, spacing: 10) {
                    GroupBox("Productivity KPI (Command Palette - ultimi 30 giorni)") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Esecuzioni totali")
                                Spacer()
                                Text("\(stats.totalExecutions)")
                                    .font(.headline)
                                    .monospacedDigit()
                            }

                            HStack {
                                Text("Latenza mediana open→execute")
                                Spacer()
                                Text(stats.medianLatencyMs.map { "\($0) ms" } ?? "N/D")
                                    .font(.headline)
                                    .monospacedDigit()
                            }

                            Divider()

                            Text("Top azioni")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if stats.topActions.isEmpty {
                                Text("Nessuna azione registrata nel periodo.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(stats.topActions.enumerated()), id: \.offset) { index, item in
                                    HStack(spacing: 8) {
                                        Text("\(index + 1).")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        Text(formatActionName(item.action))
                                            .font(.caption)
                                        Spacer()
                                        Text("\(item.count)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(10)
                    }

                    HStack(spacing: 10) {
                        Picker("Evento", selection: $selectedAuditEventRaw) {
                            Text("Tutti").tag("all")
                            ForEach([
                                AuditEvent.patientWindowOpened,
                                AuditEvent.patientWindowClosed,
                                AuditEvent.reportExported,
                                AuditEvent.reportPrinted,
                                AuditEvent.prescriptionExported,
                                AuditEvent.prescriptionPrinted,
                                AuditEvent.patientDataExported,
                                AuditEvent.backupExported,
                                AuditEvent.backupRestored,
                                AuditEvent.appUnlocked,
                                AuditEvent.appLockFailed,
                                AuditEvent.appLocked,
                                AuditEvent.commandPaletteActionExecuted,
                                AuditEvent.patientWindowsRestored
                            ], id: \.rawValue) { event in
                                Text(event.displayName).tag(event.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)

                        DatePicker("Da", selection: $auditFromDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)

                        Button("Aggiorna") {
                            reloadAuditRecords()
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Stepper(value: $auditRetentionDays, in: 30...3650, step: 30) {
                            Text("Retention: \(auditRetentionDays) giorni")
                                .font(.caption)
                        }
                        .frame(width: 220, alignment: .leading)

                        Stepper(value: $auditMaxRecords, in: 500...200_000, step: 500) {
                            Text("Cap log: \(auditMaxRecords)")
                                .font(.caption)
                        }
                        .frame(width: 220, alignment: .leading)

                        Button("Applica policy") {
                            AuditTrailService.shared.updateRetentionPolicy(
                                retentionDays: auditRetentionDays,
                                maxRecords: auditMaxRecords
                            )
                            reloadAuditRecords()
                        }
                        .buttonStyle(.bordered)

                        Button("Purge ora") {
                            AuditTrailService.shared.purgeAuditLogNow()
                            reloadAuditRecords()
                        }
                        .buttonStyle(.bordered)
                    }

                    if auditRecords.isEmpty {
                        Text("Nessun evento audit nel filtro selezionato.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(auditRecords.enumerated()), id: \.offset) { _, record in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(record.timestamp.formatted(date: .abbreviated, time: .standard))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 180, alignment: .leading)

                                        Text(auditLabel(for: record.event))
                                            .font(.caption)
                                            .frame(width: 150, alignment: .leading)

                                        Text(metadataSummary(for: record.metadata))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .frame(minHeight: 140, maxHeight: 220)
                    }
                    }
                    .padding(10)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 720, minHeight: 520, alignment: .topLeading)
        .onAppear {
            auditRetentionDays = AuditTrailService.shared.retentionDays
            auditMaxRecords = AuditTrailService.shared.maxRecords
            reloadAuditRecords()
        }
        .onChange(of: selectedAuditEventRaw) { _, _ in
            reloadAuditRecords()
        }
        .onChange(of: auditFromDate) { _, _ in
            reloadAuditRecords()
        }
    }

    private func timeoutLabel(minutes: Int) -> String {
        if minutes == 1 {
            return "1 minuto"
        }
        return "\(minutes) minuti"
    }

    private func reloadAuditRecords() {
        let selectedEvent: AuditEvent? = selectedAuditEventRaw == "all" ? nil : AuditEvent(rawValue: selectedAuditEventRaw)
        auditRecords = AuditTrailService.shared.readRecords(since: auditFromDate, event: selectedEvent, limit: 500)
        let commandPaletteSince = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        commandPaletteRecords = AuditTrailService.shared.readRecords(
            since: commandPaletteSince,
            event: .commandPaletteActionExecuted,
            limit: 10_000
        )
    }

    private func auditLabel(for rawEvent: String) -> String {
        AuditEvent(rawValue: rawEvent)?.displayName ?? rawEvent
    }

    private func metadataSummary(for metadata: [String: String]) -> String {
        if metadata.isEmpty {
            return "-"
        }
        return metadata.keys.sorted().map { key in
            "\(key)=\(metadata[key] ?? "")"
        }.joined(separator: " · ")
    }

    private func formatActionName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

@MainActor
final class ModelStoreState: ObservableObject {
    @Published private(set) var container: ModelContainer?
    @Published private(set) var errorDescription: String?
    private let makeContainer: @MainActor () throws -> ModelContainer

    init(makeContainer: @escaping @MainActor () throws -> ModelContainer = ModelStoreState.makeDefaultContainer) {
        self.makeContainer = makeContainer
        retry()
    }

    func retry() {
        do {
            container = try makeContainer()
            errorDescription = nil
        } catch {
            container = nil
            errorDescription = error.localizedDescription
        }
    }

    static func makeDefaultContainer() throws -> ModelContainer {
        let schema = Schema([
            Patient.self, ClinicalNote.self, TherapyMedication.self,
            PHQ9Assessment.self, GAD7Assessment.self, MDQAssessment.self,
            BeckAssessment.self, MADRSAssessment.self
        ])
        #if DEBUG
        let inMemory = NSClassFromString("XCTestCase") != nil ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.arguments.contains("-UITEST_IN_MEMORY_STORE")
        #else
        let inMemory = false
        #endif
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private struct StoreUnavailableView: View {
    @ObservedObject var store: ModelStoreState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Impossibile aprire l’archivio", systemImage: "externaldrive.badge.exclamationmark")
                .font(.title2.weight(.semibold))
            Text("L’archivio non è disponibile. Le schede cliniche resteranno chiuse finché l’apertura non riesce. Puoi riprovare o chiudere Chirone.")
            if let error = store.errorDescription {
                DisclosureGroup("Dettagli dell’errore") {
                    Text(error).font(.caption).textSelection(.enabled)
                }
            }
            HStack {
                Button("Chiudi Chirone") { NSApp.terminate(nil) }
                Spacer()
                Button("Riprova") { store.retry() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 560)
        .frame(minHeight: 280)
    }
}

@main
struct ChironeGestionaleApp: App {
    @NSApplicationDelegateAdaptor(ChironeApplicationDelegate.self) private var applicationDelegate
    private let backupUIService = BackupUIService()
    @AppStorage("report.notesInReport") private var reportNotesInReport = 3
    @StateObject private var printCommandState = PrintCommandState()
    @StateObject private var commandPaletteState = CommandPaletteState()
    @StateObject private var store = ModelStoreState()
    @ObservedObject private var lockViewModel = AppLockViewModel.shared

    init() {
        // Build autocomplete indices off the main thread so the first
        // Therapy section open is instant instead of parsing 535 KB of JSON.
        Task.detached(priority: .utility) { _ = ActiveIngredientAutocomplete.shared }
    }

    var body: some Scene {
        WindowGroup {
            if let container = store.container {
                AppLockGateView {
                    ContentView()
                }
                .environmentObject(commandPaletteState)
                .modelContainer(container)
            } else {
                StoreUnavailableView(store: store)
            }
        }
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Apri Command Palette…") {
                    commandPaletteState.present()
                }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(store.container == nil || !lockViewModel.permitsClinicalAccess)

                Button("Quick Capture Clinico…") {
                    requestQuickClinicalCapture()
                }
                .keyboardShortcut(.space, modifiers: [.command, .option])
                .disabled(!printCommandState.canPrintReport || !lockViewModel.permitsClinicalAccess)
            }

            CommandGroup(before: .printItem) {
                Button {
                    exportActivePatientReport()
                } label: {
                    Label(exportReportCommandTitle, systemImage: "doc.richtext")
                }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(!printCommandState.canPrintReport || !lockViewModel.permitsClinicalAccess)

                Button {
                    exportActivePatientPrescription()
                } label: {
                    Label(exportPrescriptionCommandTitle, systemImage: "pills")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!printCommandState.canPrintReport || !lockViewModel.permitsClinicalAccess)
            }

            CommandMenu("Backup") {
                Button("Esporta backup cifrato…") {
                    guard lockViewModel.permitsClinicalAccess, let container = store.container else { return }
                    backupUIService.exportBackup(modelContainer: container)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(store.container == nil || !lockViewModel.permitsClinicalAccess)

                Button("Ripristina backup cifrato…") {
                    guard lockViewModel.permitsClinicalAccess, let container = store.container else { return }
                    backupUIService.restoreBackup(modelContainer: container)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.container == nil || !lockViewModel.permitsClinicalAccess)

                Divider()

                Button("Esporta dati paziente (JSON)…") {
                    exportActivePatientPortabilityData()
                }
                .help(exportPatientDataHelpText)
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!printCommandState.canPrintReport || !lockViewModel.permitsClinicalAccess)
            }
        }

        Settings {
            AppLockGateView { PreferencesView() }
        }
    }

    private var exportReportCommandTitle: String {
        guard lockViewModel.permitsClinicalAccess, let patientName = printCommandState.activePatientName, !patientName.isEmpty else {
            return "Esporta referto…"
        }
        return "Esporta referto di \(patientName)…"
    }

    private var exportPrescriptionCommandTitle: String {
        guard lockViewModel.permitsClinicalAccess, let patientName = printCommandState.activePatientName, !patientName.isEmpty else {
            return "Componi prescrizione medica…"
        }
        return "Componi prescrizione medica per \(patientName)…"
    }

    private var exportPatientDataHelpText: String {
        guard lockViewModel.permitsClinicalAccess, let patientName = printCommandState.activePatientName, !patientName.isEmpty else {
            return "Apri o attiva una cartella clinica paziente per abilitare l'export."
        }
        return "Esporta i dati strutturati del paziente attivo: \(patientName)."
    }

    private func exportActivePatientReport() {
        guard lockViewModel.permitsClinicalAccess else { return }
        guard let patient = PatientWindowCoordinator.shared.activePatient() else {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Nessuna scheda clinica attiva"
            alert.informativeText = "Apri o attiva una scheda clinica paziente prima di esportare il referto."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        let options = ReportOptions(recentNotesCount: reportNotesInReport)
        let draft = PatientReportService.shared.makeDraft(for: patient, options: options)
        ReportPreviewWindowCoordinator.shared.present(
            draft: draft,
            profile: .current(),
            reloadDraft: {
                PatientReportService.shared.makeDraft(for: patient, options: options)
            }
        )
    }

    private func exportActivePatientPrescription() {
        guard lockViewModel.permitsClinicalAccess else { return }
        guard let patient = PatientWindowCoordinator.shared.activePatient() else {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Nessuna scheda clinica attiva"
            alert.informativeText = "Apri o attiva una scheda clinica paziente prima di generare la ricetta."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        do {
            let draft = try PatientPrescriptionService.shared.makeDraft(for: patient)
            PrescriptionPreviewWindowCoordinator.shared.present(
                draft: draft,
                profile: .current(),
                reloadDraft: {
                    try PatientPrescriptionService.shared.makeDraft(for: patient)
                }
            )
        } catch PatientPrescriptionServiceError.noActiveTherapy {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Nessuna terapia attiva"
            alert.informativeText = "Il paziente non ha una terapia farmacologica attiva da prescrivere."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Errore generazione ricetta"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func exportActivePatientPortabilityData() {
        guard lockViewModel.permitsClinicalAccess else { return }
        guard let patient = PatientWindowCoordinator.shared.activePatient() else {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Nessuna scheda clinica attiva"
            alert.informativeText = "Apri o attiva una scheda clinica paziente prima di esportare i dati strutturati."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        backupUIService.exportPatientPortabilityData(patient: patient)
    }

    private func requestQuickClinicalCapture() {
        guard lockViewModel.permitsClinicalAccess else { return }
        guard let patient = PatientWindowCoordinator.shared.activePatient() else {
            NSSound.beep()
            return
        }

        NotificationCenter.default.post(
            name: .quickClinicalCaptureRequested,
            object: self,
            userInfo: ["patientID": patient.id.uuidString]
        )
    }
}
