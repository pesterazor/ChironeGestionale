import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

private struct ReportPDFPreviewView: NSViewRepresentable {
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

private struct ReportComposerContentView: View {
    @State private var draft: ClinicalReportDraft
    @State private var baselineDraft: ClinicalReportDraft
    @State private var previewDocument: PDFDocument?
    @State private var previewedDraft: ClinicalReportDraft?
    @State private var renderingError: String?
    @State private var lastExportedDraft: ClinicalReportDraft?

    let profile: ProfessionalReportProfile
    let reloadDraft: () -> ClinicalReportDraft
    let onClose: () -> Void
    let onUnexportedChanges: (Bool) -> Void
    let onSave: (PDFDocument, String) -> Bool
    let onPrint: (PDFDocument, String) -> Bool

    init(
        draft: ClinicalReportDraft,
        profile: ProfessionalReportProfile,
        reloadDraft: @escaping () -> ClinicalReportDraft,
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
                Text("Composizione relazione clinica")
                    .font(.headline)
                    .accessibilityIdentifier("report_preview_title")
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
                            TextField("Relazione clinica", text: $draft.title)
                                .accessibilityIdentifier("report_composer_title_field")
                        }
                        GridRow {
                            Text("Data")
                            DatePicker("", selection: $draft.documentDate, displayedComponents: .date)
                                .labelsHidden()
                                .accessibilityIdentifier("report_composer_date_picker")
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
                    .accessibilityIdentifier("report_composer_warnings")
                }

                ForEach($draft.sections) { $section in
                    reportSectionEditor(section: $section)
                }
            }
            .padding(14)
        }
    }

    private func reportSectionEditor(section: Binding<ClinicalReportSection>) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("Includi", isOn: section.isIncluded)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("report_composer_toggle_\(section.wrappedValue.kind.rawValue)")
                    TextField("Titolo sezione", text: section.title)
                        .font(.headline)
                        .textFieldStyle(.plain)
                    Spacer()
                    Text(sourceLabel(section.wrappedValue.source))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                ZStack(alignment: .topLeading) {
                    if section.wrappedValue.text.isEmpty {
                        Text("Inserisci il testo della sezione")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: section.text)
                        .font(.body)
                        .frame(minHeight: 92)
                        .scrollContentBackground(.hidden)
                        .accessibilityIdentifier("report_composer_editor_\(section.wrappedValue.kind.rawValue)")
                }
                .padding(4)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 7))
                .opacity(section.wrappedValue.isIncluded ? 1 : 0.68)
            }
            .padding(8)
        } label: {
            Text(section.wrappedValue.title)
                .font(.subheadline.weight(.semibold))
        }
    }

    private var previewPane: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let previewDocument {
                ReportPDFPreviewView(document: previewDocument)
                    .accessibilityIdentifier("report_composer_pdf_preview")
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
                            .accessibilityIdentifier("report_composer_preview_stale")
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Ricarica dalla cartella") { requestReload() }
                .accessibilityIdentifier("report_composer_reload_button")
            Button("Aggiorna anteprima") { refreshPreviewNow() }
                .accessibilityIdentifier("report_composer_update_preview_button")

            Spacer()

            Button("Chiudi") { requestClose() }
                .accessibilityIdentifier("report_preview_close_button")
            Button("Salva PDF") { saveCurrentDraft() }
                .accessibilityIdentifier("report_preview_save_button")
                .disabled(previewDocument == nil)
            Button("Stampa") { printCurrentDraft() }
                .accessibilityIdentifier("report_preview_print_button")
                .buttonStyle(.borderedProminent)
                .disabled(previewDocument == nil)
        }
        .padding(16)
    }

    private func sourceLabel(_ source: ClinicalReportSection.Source) -> String {
        switch source {
        case .demographics: return "Anagrafica"
        case .clinicalRecord: return "Cartella clinica"
        case .clinicalNotes: return "Note cliniche"
        case .therapy: return "Terapia"
        case .bloodTests: return "Esami"
        case .psychometricScales: return "Scale"
        case .clinician: return "Testo del clinico"
        }
    }

    private func refreshPreviewNow() {
        do {
            previewDocument = try PatientReportService.shared.render(draft: draft, profile: profile)
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
            let document = try PatientReportService.shared.render(draft: draft, profile: profile)
            previewDocument = document
            previewedDraft = draft
            renderingError = nil
            return document
        } catch {
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
            alert.messageText = "Ricaricare i dati dalla cartella?"
            alert.informativeText = "Le modifiche apportate alla bozza verranno sostituite."
            alert.addButton(withTitle: "Ricarica")
            alert.addButton(withTitle: "Annulla")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let reloaded = reloadDraft()
        draft = reloaded
        baselineDraft = reloaded
        lastExportedDraft = nil
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
final class ReportPreviewWindowCoordinator {
    static let shared = ReportPreviewWindowCoordinator()

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
        draft: ClinicalReportDraft,
        profile: ProfessionalReportProfile,
        reloadDraft: @escaping () -> ClinicalReportDraft
    ) {
        guard AppLockViewModel.shared.permitsClinicalAccess else { return }
        if window != nil, !closeGuard.confirmClosing() { return }
        closeGuard.hasUnexportedChanges = false
        let patientID = draft.patientID
        let contentView = ReportComposerContentView(
            draft: draft,
            profile: profile,
            reloadDraft: reloadDraft,
            onClose: { [weak self] in self?.closeIfPresent() },
            onUnexportedChanges: { [weak self] changed in self?.closeGuard.hasUnexportedChanges = changed },
            onSave: { [weak self] document, title in
                self?.saveReport(document: document, title: title, patientID: patientID) ?? false
            },
            onPrint: { [weak self] document, title in
                self?.printReport(document: document, title: title, patientID: patientID) ?? false
            }
        )

        let hostingController = NSHostingController(rootView: AppLockGateView { contentView })
        let composerWindow = window ?? NSWindow(contentViewController: hostingController)
        composerWindow.contentViewController = hostingController
        composerWindow.delegate = closeGuard
        closeGuard.onClose = { [weak self] in self?.window = nil }
        composerWindow.title = "Composizione relazione clinica"
        composerWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        composerWindow.setContentSize(NSSize(width: 1120, height: 780))
        composerWindow.minSize = NSSize(width: 900, height: 620)
        composerWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = composerWindow
    }

    private func saveReport(document: PDFDocument, title: String, patientID: UUID) -> Bool {
        guard AppLockViewModel.shared.permitsClinicalAccess else { return false }
        guard let data = document.dataRepresentation() else {
            showInfoAlert(title: "Salvataggio non riuscito", message: "Impossibile serializzare il PDF della relazione.")
            return false
        }

        let panel = NSSavePanel()
        panel.title = "Salva relazione clinica"
        panel.nameFieldStringValue = defaultReportFilename(title: title)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowsOtherFileTypes = false
        panel.allowedContentTypes = [.pdf]

        guard panel.runModal() == .OK, let url = panel.url,
              AppLockViewModel.shared.permitsClinicalAccess else { return false }
        do {
            try data.write(to: url, options: .atomic)
            AuditTrailService.shared.log(
                .reportExported,
                metadata: ["patient": AuditTrailService.shared.redactedIdentifier(for: patientID)]
            )
            showInfoAlert(title: "Relazione salvata", message: "Il PDF è stato salvato correttamente.")
            return true
        } catch {
            showInfoAlert(title: "Salvataggio non riuscito", message: error.localizedDescription)
            return false
        }
    }

    private func printReport(document: PDFDocument, title: String, patientID: UUID) -> Bool {
        guard AppLockViewModel.shared.permitsClinicalAccess else { return false }
        do {
            let printed = try PatientReportService.shared.print(document: document, jobTitle: title)
            if printed {
                AuditTrailService.shared.log(
                    .reportPrinted,
                    metadata: ["patient": AuditTrailService.shared.redactedIdentifier(for: patientID)]
                )
            }
            return printed
        } catch {
            showInfoAlert(title: "Stampa non riuscita", message: error.localizedDescription)
            return false
        }
    }

    private func defaultReportFilename(title: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let normalizedTitle = sanitizedFilenameComponent(title)
        return "Relazione-\(normalizedTitle)-\(formatter.string(from: .now)).pdf"
    }

    private func sanitizedFilenameComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_") )
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
