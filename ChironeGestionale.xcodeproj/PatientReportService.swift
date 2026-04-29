import Foundation
import AppKit
import PDFKit

enum PatientReportServiceError: Error {
    case documentCreationFailed
    case printOperationUnavailable
}

@MainActor
final class PatientReportService {
    static let shared = PatientReportService()

    private init() {}

    func printReport(for patient: Patient, latestNotesCount: Int) throws {
        let reportText = makeReportText(for: patient, latestNotesCount: latestNotesCount)
        let attributed = makeAttributedReport(text: reportText)
        let fitted = fittedAttributedReport(attributed)

        let pageSize = NSSize(width: 595, height: 842) // A4 at 72 dpi
        let view = ReportPageView(pageSize: pageSize, content: fitted)
        let pdfData = view.dataWithPDF(inside: view.bounds)

        guard let document = PDFDocument(data: pdfData) else {
            throw PatientReportServiceError.documentCreationFailed
        }

        guard let printOperation = document.printOperation(
            for: NSPrintInfo.shared,
            scalingMode: .pageScaleDownToFit,
            autoRotate: true
        ) else {
            throw PatientReportServiceError.printOperationUnavailable
        }

        printOperation.jobTitle = "Referto - \(patient.fullName)"
        printOperation.showsProgressPanel = true
        printOperation.showsPrintPanel = true
        printOperation.printPanel.options = [.showsCopies, .showsPaperSize, .showsOrientation, .showsScaling, .showsPreview]
        printOperation.run()
    }

    private func makeReportText(for patient: Patient, latestNotesCount: Int) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "it_IT")
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let birthDate = patient.dateOfBirth.map { dateFormatter.string(from: $0) } ?? "N/D"
        let age = patient.ageInYears.map { "\($0) anni" } ?? "N/D"

        let primaryDiagnosis = patient.readablePrimaryDiagnosis.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondaryDiagnosis = patient.readableSecondaryDiagnosis.trimmingCharacters(in: .whitespacesAndNewlines)

        let diagnosisSummary: String = {
            let lines = [
                primaryDiagnosis.isEmpty ? nil : "- Diagnosi principale: \(primaryDiagnosis)",
                secondaryDiagnosis.isEmpty ? nil : "- Diagnosi secondaria: \(secondaryDiagnosis)"
            ].compactMap { $0 }
            return lines.isEmpty ? "- Nessuna diagnosi inserita" : lines.joined(separator: "\n")
        }()

        let activeTherapy = patient.therapyItems
            .filter(\.isActive)
            .map { item in
                let name = item.medicationName.trimmingCharacters(in: .whitespacesAndNewlines)
                let dosage = item.dosage.trimmingCharacters(in: .whitespacesAndNewlines)
                let posology = item.posology.trimmingCharacters(in: .whitespacesAndNewlines)
                let head = [name, dosage].filter { !$0.isEmpty }.joined(separator: " ")
                if posology.isEmpty { return head }
                if head.isEmpty { return posology }
                return "\(head) - \(posology)"
            }
            .filter { !$0.isEmpty }

        let therapySummary = activeTherapy.isEmpty ? "- Nessuna terapia attiva registrata" : activeTherapy.map { "- \($0)" }.joined(separator: "\n")

        let notesLimit = max(1, min(8, latestNotesCount))
        let latestNotes = patient.clinicalNotes
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(notesLimit)
            .map { note in
                let timestamp = dateFormatter.string(from: note.createdAt)
                let content = normalizedSnippet(note.readableContent)
                return "- [\(timestamp)] \(content)"
            }

        let notesSummary = latestNotes.isEmpty ? "- Nessuna nota disponibile" : latestNotes.joined(separator: "\n")

        return """
        CHIRONE GESTIONALE - RELAZIONE CLINICA BREVE

        Anagrafica
        - Nome e cognome: \(patient.fullName)
        - Data di nascita: \(birthDate) (\(age))
        - Codice fiscale: \(patient.taxCode.isEmpty ? "N/D" : patient.taxCode)
        - Telefono: \(patient.phoneNumber.isEmpty ? "N/D" : patient.phoneNumber)

        Diagnosi
        \(diagnosisSummary)

        Terapia attuale
        \(therapySummary)

        Ultime note cliniche (\(notesLimit))
        \(notesSummary)

        Documento generato il \(dateFormatter.string(from: .now)).
        """
    }

    private func normalizedSnippet(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = trimmed.replacingOccurrences(of: "\n", with: " ")
        if compact.count <= 320 {
            return compact.isEmpty ? "(vuoto)" : compact
        }
        let end = compact.index(compact.startIndex, offsetBy: 320)
        return String(compact[..<end]) + "…"
    }

    private func makeAttributedReport(text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 7

        let font = NSFont.systemFont(ofSize: 12)
        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func fittedAttributedReport(_ original: NSAttributedString) -> NSAttributedString {
        let maxHeight: CGFloat = 842 - 96 // page minus margins
        var working = original.string

        while true {
            let attributed = makeAttributedReport(text: working)
            let rect = attributed.boundingRect(
                with: NSSize(width: 595 - 96, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )

            if rect.height <= maxHeight {
                return attributed
            }

            let cut = max(working.count - 180, 0)
            guard cut > 0 else { return attributed }
            let idx = working.index(working.startIndex, offsetBy: cut)
            working = String(working[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !working.hasSuffix("…") {
                working += "\n\n[Contenuto abbreviato per stampa su una pagina.]"
            }
        }
    }
}

private final class ReportPageView: NSView {
    private let content: NSAttributedString
    private let margin: CGFloat = 48

    init(pageSize: NSSize, content: NSAttributedString) {
        self.content = content
        super.init(frame: NSRect(origin: .zero, size: pageSize))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let contentRect = bounds.insetBy(dx: margin, dy: margin)
        content.draw(
            with: contentRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
    }
}
