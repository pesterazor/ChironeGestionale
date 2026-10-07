import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

private struct PrescriptionPDFPreviewView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .windowBackgroundColor
        view.document = document
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // Draft edits must not reset the scroll/zoom position of the unchanged preview.
        if nsView.document !== document { nsView.document = document }
    }
}

private struct PrescriptionComposerContentView: View {
    @State private var draft: PatientPrescriptionDraft
    @State private var baselineDraft: PatientPrescriptionDraft
    @State private var previewDocument: PDFDocument?
    @State private var previewedDraft: PatientPrescriptionDraft?
    @State private var renderingError: String?
    @State private var lastExportedDraft: PatientPrescriptionDraft?

    let profile: ProfessionalReportProfile
    let reloadDraft: () throws -> PatientPrescriptionDraft
    let onClose: () -> Void
    let onUnexportedChanges: (Bool) -> Void
    let onSave: (PDFDocument, String) -> Bool
    let onPrint: (PDFDocument, String) -> Bool

    init(
        draft: PatientPrescriptionDraft,
        profile: ProfessionalReportProfile,
        reloadDraft: @escaping () throws -> PatientPrescriptionDraft,
        onClose: @escaping () -> Void,
        onUnexportedChanges: @escaping (Bool) -> Void,
        onSave: @escaping (PDFDocument, String) -> Bool,
        onPrint: @escaping (PDFDocument, String) -> Bool
    ) {
        _draft = State(initialValue: draft)
        _baselineDraft = State(initialValue: draft)
        self.profile = profile
        self.reloadDraft = reloadDraft
        self.onClose = onClose
        self.onUnexportedChanges = onUnexportedChanges
        self.onSave = onSave
        self.onPrint = onPrint
    }

    private var allIssues: [ReportValidationIssue] {
        draft.issues + profile.validationIssues
    }

    private var hasUnexportedChanges: Bool {
        draft != baselineDraft && lastExportedDraft != draft
    }

    private var previewIsOutdated: Bool {
        previewedDraft != nil && previewedDraft != draft
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                editorPane
                    .frame(minWidth: 410, idealWidth: 470)
                previewPane
                    .frame(minWidth: 430, idealWidth: 560)
            }

            Divider()
            actionBar
        }
        .frame(minWidth: 980, minHeight: 700)
        .task { refreshPreviewNow() }
        .onChange(of: hasUnexportedChanges, initial: true) { _, changed in
            onUnexportedChanges(changed)
        }
        .onChange(of: draft) { _, _ in
            lastExportedDraft = nil
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Composizione prescrizione medica")
                    .font(.headline)
                    .accessibilityIdentifier("prescription_preview_title")
                Text(draft.patientDisplayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Bozza locale non archiviata")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var editorPane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                GroupBox("Documento") {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                        GridRow {
                            Text("Titolo")
                            TextField("Prescrizione medica", text: $draft.title)
                                .accessibilityIdentifier("prescription_composer_title_field")
                        }
                        GridRow {
                            Text("Data")
                            DatePicker("", selection: $draft.documentDate, displayedComponents: .date)
                                .labelsHidden()
                                .accessibilityIdentifier("prescription_composer_date_picker")
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                }

                if !allIssues.isEmpty {
                    GroupBox("Dati da verificare") {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(allIssues) { issue in
                                Label(issue.message, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(8)
                    }
                    .accessibilityIdentifier("prescription_composer_warnings")
                }

                GroupBox("Dati del paziente") {
                    prescriptionTextEditor(
                        text: $draft.patientIdentification,
                        placeholder: "Inserisci i dati identificativi del paziente",
                        accessibilityIdentifier: "prescription_composer_patient_editor",
                        minimumHeight: 110
                    )
                    .padding(8)
                }

                GroupBox("Farmaci prescritti") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($draft.medications) { $medication in
                            HStack(alignment: .top, spacing: 8) {
                                Toggle("Includi", isOn: $medication.isIncluded)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .accessibilityIdentifier("prescription_composer_toggle_\(medication.id.uuidString)")

                                prescriptionTextEditor(
                                    text: $medication.text,
                                    placeholder: "Farmaco, dosaggio e posologia",
                                    accessibilityIdentifier: "prescription_composer_medication_\(medication.id.uuidString)",
                                    minimumHeight: 72
                                )
                                .opacity(medication.isIncluded ? 1 : 0.68)

                                Button(role: .destructive) {
                                    removeMedication(id: medication.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Rimuovi dalla bozza")
                                .accessibilityIdentifier("prescription_composer_remove_\(medication.id.uuidString)")
                            }
                        }

                        Button {
                            addMedication()
                        } label: {
                            Label("Aggiungi farmaco alla bozza", systemImage: "plus")
                        }
                        .accessibilityIdentifier("prescription_composer_add_medication_button")
                    }
                    .padding(8)
                }

                GroupBox {
                    prescriptionTextEditor(
                        text: $draft.additionalDirections,
                        placeholder: "Inserisci eventuali indicazioni aggiuntive",
                        accessibilityIdentifier: "prescription_composer_directions_editor",
                        minimumHeight: 92
                    )
                    .padding(8)
                    .opacity(draft.includesAdditionalDirections ? 1 : 0.68)
                } label: {
                    HStack {
                        Toggle("Includi", isOn: $draft.includesAdditionalDirections)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("prescription_composer_directions_toggle")
                        Text("Indicazioni aggiuntive")
                    }
                }
            }
            .padding(14)
        }
    }

    private func prescriptionTextEditor(
        text: Binding<String>,
        placeholder: String,
        accessibilityIdentifier: String,
        minimumHeight: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: minimumHeight)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(4)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 7))
    }

    private var previewPane: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let previewDocument {
                PrescriptionPDFPreviewView(document: previewDocument)
                    .accessibilityIdentifier("prescription_composer_pdf_preview")
            } else if let renderingError {
                ContentUnavailableView(
                    "Anteprima non disponibile",
                    systemImage: "exclamationmark.triangle",
                    description: Text(renderingError)
                )
            } else {
                ProgressView("Generazione anteprima…")
            }

            if previewIsOutdated {
                VStack {
                    HStack {
                        Spacer()
                        Label("Anteprima da aggiornare", systemImage: "arrow.clockwise.circle")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                            .accessibilityIdentifier("prescription_composer_preview_stale")
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Ricarica terapia") { requestReload() }
                .accessibilityIdentifier("prescription_composer_reload_button")
            Button("Aggiorna anteprima") { refreshPreviewNow() }
                .accessibilityIdentifier("prescription_composer_update_preview_button")

            Spacer()

            Button("Chiudi") { requestClose() }
                .accessibilityIdentifier("prescription_preview_close_button")
            Button("Salva PDF") { saveCurrentDraft() }
                .accessibilityIdentifier("prescription_preview_save_button")
                .disabled(previewDocument == nil)
            Button("Stampa") { printCurrentDraft() }
                .accessibilityIdentifier("prescription_preview_print_button")
                .buttonStyle(.borderedProminent)
                .disabled(previewDocument == nil)
        }
        .padding(16)
    }

    private func addMedication() {
        draft.medications.append(PrescriptionMedicationDraft(id: UUID(), text: "", isIncluded: true))
    }

    private func removeMedication(id: UUID) {
        draft.medications.removeAll { $0.id == id }
    }

    private func refreshPreviewNow() {
        do {
            previewDocument = try PatientPrescriptionService.shared.render(draft: draft, profile: profile)
            previewedDraft = draft
            renderingError = nil
        } catch {
            previewDocument = nil
            previewedDraft = nil
            renderingError = error.localizedDescription
        }
    }

    private func latestDocument() -> PDFDocument? {
        if previewedDraft == draft, let previewDocument { return previewDocument }
        do {
            let document = try PatientPrescriptionService.shared.render(draft: draft, profile: profile)
            previewDocument = document
            previewedDraft = draft
            renderingError = nil
            return document
        } catch {
            previewDocument = nil
            previewedDraft = nil
            renderingError = error.localizedDescription
            return nil
        }
    }

    private func saveCurrentDraft() {
        guard let document = latestDocument() else { return }
        if onSave(document, draft.title) {
            lastExportedDraft = draft
        }
    }

    private func printCurrentDraft() {
        guard let document = latestDocument() else { return }
        if onPrint(document, draft.title) {
            lastExportedDraft = draft
        }
    }

    private func requestReload() {
        if draft != baselineDraft {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Ricaricare la terapia dalla cartella?"
            alert.informativeText = "Le modifiche apportate alla bozza della ricetta verranno sostituite."
            alert.addButton(withTitle: "Ricarica")
            alert.addButton(withTitle: "Annulla")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            let reloaded = try reloadDraft()
            draft = reloaded
            baselineDraft = reloaded
            lastExportedDraft = nil
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Impossibile ricaricare la terapia"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func requestClose() {
        if hasUnexportedChanges {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Chiudere la bozza?"
            alert.informativeText = "Le modifiche non esportate non verranno conservate."
            alert.addButton(withTitle: "Chiudi")
            alert.addButton(withTitle: "Annulla")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        onClose()
    }
}

@MainActor
final class PrescriptionPreviewWindowCoordinator {
    static let shared = PrescriptionPreviewWindowCoordinator()

    private var window: NSWindow?
    private let closeGuard = DocumentWindowCloseGuard()

    private init() {}

    var hasUnexportedChanges: Bool { window != nil && closeGuard.hasUnexportedChanges }

    func confirmClosingIfNeeded() -> Bool {
        window == nil || closeGuard.confirmClosing()
    }

    func closeIfPresent() {
        window?.close()
        window = nil
        closeGuard.hasUnexportedChanges = false
    }

    func present(
        draft: PatientPrescriptionDraft,
        profile: ProfessionalReportProfile,
        reloadDraft: @escaping () throws -> PatientPrescriptionDraft
    ) {
        guard AppLockViewModel.shared.permitsClinicalAccess else { return }
        if window != nil, !closeGuard.confirmClosing() { return }
        closeGuard.hasUnexportedChanges = false
        let patientID = draft.patientID
        let patientName = draft.patientDisplayName
        let contentView = PrescriptionComposerContentView(
            draft: draft,
            profile: profile,
            reloadDraft: reloadDraft,
            onClose: { [weak self] in self?.closeIfPresent() },
            onUnexportedChanges: { [weak self] changed in self?.closeGuard.hasUnexportedChanges = changed },
            onSave: { [weak self] document, title in
                self?.savePrescription(
                    document: document,
                    title: title,
                    patientName: patientName,
                    patientID: patientID
                ) ?? false
            },
            onPrint: { [weak self] document, title in
                self?.printPrescription(document: document, title: title, patientID: patientID) ?? false
            }
        )

        let hostingController = NSHostingController(rootView: AppLockGateView { contentView })
        let composerWindow = window ?? NSWindow(contentViewController: hostingController)
        composerWindow.contentViewController = hostingController
        composerWindow.delegate = closeGuard
        closeGuard.onClose = { [weak self] in self?.window = nil }
        composerWindow.title = "Composizione prescrizione medica"
        composerWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        composerWindow.setContentSize(NSSize(width: 1120, height: 780))
        composerWindow.minSize = NSSize(width: 900, height: 620)
        composerWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = composerWindow
    }

    private func savePrescription(
        document: PDFDocument,
        title: String,
        patientName: String,
        patientID: UUID
    ) -> Bool {
        guard AppLockViewModel.shared.permitsClinicalAccess else { return false }
        guard let data = document.dataRepresentation() else {
            showInfoAlert(title: "Salvataggio non riuscito", message: "Impossibile serializzare il PDF della ricetta.")
            return false
        }

        let panel = NSSavePanel()
        panel.title = "Salva prescrizione medica"
        panel.nameFieldStringValue = defaultPrescriptionFilename(patientName: patientName)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowsOtherFileTypes = false
        panel.allowedContentTypes = [.pdf]

        guard panel.runModal() == .OK, let url = panel.url,
              AppLockViewModel.shared.permitsClinicalAccess else { return false }
        do {
            try data.write(to: url, options: .atomic)
            AuditTrailService.shared.log(
                .prescriptionExported,
                metadata: ["patient": AuditTrailService.shared.redactedIdentifier(for: patientID)]
            )
            showInfoAlert(title: "Prescrizione salvata", message: "Il PDF è stato salvato correttamente.")
            return true
        } catch {
            showInfoAlert(title: "Salvataggio non riuscito", message: error.localizedDescription)
            return false
        }
    }

    private func printPrescription(document: PDFDocument, title: String, patientID: UUID) -> Bool {
        guard AppLockViewModel.shared.permitsClinicalAccess else { return false }
        do {
            let printed = try PatientPrescriptionService.shared.print(document: document, jobTitle: title)
            if printed {
                AuditTrailService.shared.log(
                    .prescriptionPrinted,
                    metadata: ["patient": AuditTrailService.shared.redactedIdentifier(for: patientID)]
                )
            }
            return printed
        } catch {
            showInfoAlert(title: "Stampa non riuscita", message: error.localizedDescription)
            return false
        }
    }

    private func defaultPrescriptionFilename(patientName: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return "Prescrizione-\(sanitizedFilenameComponent(patientName))-\(formatter.string(from: .now)).pdf"
    }

    private func sanitizedFilenameComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let collapsed = String(mapped).replacingOccurrences(of: "__", with: "_")
        let result = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return result.isEmpty ? "Paziente" : result
    }

    private func showInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
