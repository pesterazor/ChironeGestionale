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

    func makeReportDocument(for patient: Patient, latestNotesCount: Int) throws -> PDFDocument {
        let generatedAt = Date()
        let bodyText = makeReportText(for: patient, latestNotesCount: latestNotesCount)
        let attributed = makeAttributedReport(patient: patient, bodyText: bodyText, generatedAt: generatedAt)
        let pdfData = renderPaginatedPDF(from: attributed)

        guard let document = PDFDocument(data: pdfData) else {
            throw PatientReportServiceError.documentCreationFailed
        }
        return document
    }

    func printReport(for patient: Patient, latestNotesCount: Int) throws {
        let document = try makeReportDocument(for: patient, latestNotesCount: latestNotesCount)
        try print(document: document, jobTitle: "Referto - \(patient.fullName)")
    }

    func print(document: PDFDocument, jobTitle: String) throws {
        guard let printOperation = document.printOperation(
            for: NSPrintInfo.shared,
            scalingMode: .pageScaleDownToFit,
            autoRotate: true
        ) else {
            throw PatientReportServiceError.printOperationUnavailable
        }

        printOperation.jobTitle = jobTitle
        printOperation.showsProgressPanel = true
        printOperation.showsPrintPanel = true
        printOperation.printPanel.options = [.showsCopies, .showsPaperSize, .showsOrientation, .showsScaling, .showsPreview]
        printOperation.run()
    }

    private func renderPaginatedPDF(from content: NSAttributedString) -> Data {
        let pageSize = NSSize(width: 595, height: 842)
        let horizontalMargin: CGFloat = 56
        let topMargin: CGFloat = 62
        let bottomMargin: CGFloat = 56
        let footerHeight: CGFloat = 28
        let contentSize = NSSize(
            width: pageSize.width - (horizontalMargin * 2),
            height: pageSize.height - topMargin - bottomMargin - footerHeight
        )

        let ranges = paginatedCharacterRanges(for: content, contentSize: contentSize)
        let document = PDFDocument()

        for (index, charRange) in ranges.enumerated() {
            let pageContent = content.attributedSubstring(from: charRange)
            let pageView = ReportPageView(
                pageSize: pageSize,
                content: pageContent,
                currentPage: index + 1,
                totalPages: ranges.count,
                horizontalMargin: horizontalMargin,
                topMargin: topMargin,
                bottomMargin: bottomMargin,
                footerHeight: footerHeight
            )

            let pageData = pageView.dataWithPDF(inside: pageView.bounds)
            guard let singlePageDocument = PDFDocument(data: pageData),
                  let page = singlePageDocument.page(at: 0)
            else {
                continue
            }
            document.insert(page, at: document.pageCount)
        }

        return document.dataRepresentation() ?? Data()
    }

    private func paginatedCharacterRanges(for content: NSAttributedString, contentSize: NSSize) -> [NSRange] {
        let textStorage = NSTextStorage(attributedString: content)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        var ranges: [NSRange] = []
        var glyphIndex = 0

        while glyphIndex < layoutManager.numberOfGlyphs || ranges.isEmpty {
            let container = NSTextContainer(size: contentSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)

            let glyphRange = layoutManager.glyphRange(for: container)
            let nextGlyphIndex = NSMaxRange(glyphRange)
            if nextGlyphIndex <= glyphIndex {
                break
            }

            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            ranges.append(charRange)
            glyphIndex = nextGlyphIndex

            if glyphIndex >= layoutManager.numberOfGlyphs {
                break
            }
        }

        if ranges.isEmpty {
            ranges = [NSRange(location: 0, length: content.length)]
        }

        return ranges
    }

    private func makeReportText(for patient: Patient, latestNotesCount: Int) -> String {
        _ = latestNotesCount

        let shortDateFormatter = DateFormatter()
        shortDateFormatter.locale = Locale(identifier: "it_IT")
        shortDateFormatter.dateFormat = "dd/MM/yyyy"
        shortDateFormatter.timeStyle = .none


        let primaryDiagnosis = patient.readablePrimaryDiagnosis.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondaryDiagnosis = patient.readableSecondaryDiagnosis.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteHistory = patient.readableRemotePsychiatricHistory.trimmingCharacters(in: .whitespacesAndNewlines)

        let firstClinicalDate = patient.clinicalNotes.map(\.createdAt).min() ?? patient.createdAt
        let patientDescriptor = salutation(for: patient)
        let bornDescriptor = bornDescriptor(for: patient)
        let patientAgeText = patient.ageInYears.map { "\($0)" } ?? "età non determinabile"
        let patientNoun = patientNounDescriptor(for: patient)
        let followedDescriptor = followedDescriptor(for: patient)
        let followUpDuration = followUpDurationDescription(from: firstClinicalDate)

        let birthDateText: String = {
            guard let dob = patient.dateOfBirth else { return "data non disponibile" }
            return reportDateText(from: dob)
        }()
        let placeOfBirth = patient.placeOfBirth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "luogo non disponibile"
            : patient.placeOfBirth.trimmingCharacters(in: .whitespacesAndNewlines)

        let diagnosisNarrative: String = {
            if !primaryDiagnosis.isEmpty && !secondaryDiagnosis.isEmpty {
                return "\(primaryDiagnosis) e \(secondaryDiagnosis)"
            }
            if !primaryDiagnosis.isEmpty {
                return primaryDiagnosis
            }
            return "quadro clinico in fase di definizione diagnostica"
        }()

        let remoteHistoryNarrative = remoteHistoryBulletList(from: remoteHistory)
        let comorbidityNarrative = makeComorbidityNarrative(for: patient)
        let activeTherapy = activeTherapyLines(for: patient)
        let latestClinicalNarrative = makeLatestClinicalNarrative(for: patient, formatter: shortDateFormatter)
        let latestBloodUpdate = makeRecentBloodUpdateLine(for: patient)
        let quadroClinicoNarrative: String = {
            guard let latestBloodUpdate, !latestBloodUpdate.isEmpty else {
                return latestClinicalNarrative
            }
            return latestClinicalNarrative + "\n\n" + latestBloodUpdate
        }()
        let therapySectionNarrative = makeTherapySectionNarrative(for: patient, activeTherapyLines: activeTherapy)

        return """
        \(patientDescriptor) \(patient.fullName), \(bornDescriptor) il \(birthDateText) a \(placeOfBirth), è \(patientNoun) di \(patientAgeText) anni \(followedDescriptor) dal sottoscritto da \(followUpDuration) per \(diagnosisNarrative).

        Anamnesi psichiatrica remota
        \(remoteHistoryNarrative)

        Comorbidità mediche generali ed allergie
        \(comorbidityNarrative)

        Quadro clinico attuale
        \(quadroClinicoNarrative)

        Terapia psicofarmacologica
        \(therapySectionNarrative)
        """
    }

    private func makeLatestClinicalNarrative(for patient: Patient, formatter: DateFormatter) -> String {
        _ = formatter

        let notes = patient.clinicalNotes.sorted { $0.createdAt > $1.createdAt }
        guard let latestClinical = notes.first(where: {
            !isTherapyUpdate($0.readableContent) && !normalizedFullText($0.readableContent).isEmpty
        }) ?? notes.first(where: { !normalizedFullText($0.readableContent).isEmpty }) ?? notes.first else {
            return "All'ultima valutazione non sono disponibili note cliniche registrate in cartella."
        }

        let dateOnly = reportDateText(from: latestClinical.createdAt)
        let content = normalizedFullText(latestClinical.readableContent)
        guard !content.isEmpty else {
            return "All'ultima valutazione (\(dateOnly)) non sono state annotate osservazioni cliniche descrittive."
        }
        return "All'ultima valutazione (\(dateOnly)): \(content)"
    }

    private func makeTherapySectionNarrative(for patient: Patient, activeTherapyLines: [String]) -> String {
        let opening = therapyOpeningLine(for: patient)
        if activeTherapyLines.isEmpty {
            return "\(opening) non assume una terapia psicofarmacologica attiva registrata."
        }

        var lines: [String] = ["\(opening) assume:"]
        lines.append(contentsOf: activeTherapyLines.map { "- \($0)" })
        return lines.joined(separator: "\n")
    }

    private func isTherapyUpdate(_ text: String) -> Bool {
        let normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
            .lowercased()
        let keywords = ["terapia", "farmaco", "farmaci", "dose", "dosaggio", "posologia", "litio", "valpro", "carbamazep", "lamotrig"]
        return keywords.contains { normalized.contains($0) }
    }

    private func makeCurrentTherapyFallbackForUpdates(for patient: Patient) -> String? {
        let lines = activeTherapyLines(for: patient)
        guard !lines.isEmpty else { return nil }
        return "Terapia attiva: \(lines.joined(separator: "; "))."
    }

    private func makeRecentBloodUpdateLine(for patient: Patient) -> String? {
        let payload = BloodTestsSectionViewModel.decodePayload(from: patient.bloodTestsTableJSON)
        guard !payload.columns.isEmpty else { return nil }

        let orderedColumns = payload.columns.sorted { lhs, rhs in
            let left = BloodTestsSectionViewModel.parsedDate(from: lhs.dateText) ?? .distantPast
            let right = BloodTestsSectionViewModel.parsedDate(from: rhs.dateText) ?? .distantPast
            if left != right { return left > right }
            return lhs.dateText > rhs.dateText
        }

        guard let latest = orderedColumns.first else { return nil }
        let values = extractBloodValues(
            from: payload,
            columnID: latest.id,
            preferredTests: focusedBloodTests(for: activeTherapyLines(for: patient)),
            fallbackLimit: 3
        )

        if values.isEmpty {
            return "Esami ematochimici: controllo del \(latest.dateText)."
        }
        return "Esami ematochimici (\(latest.dateText)): \(values.joined(separator: "; "))."
    }

    private func makeComorbidityNarrative(for patient: Patient) -> String {
        let comorbidityItems = clinicalListItems(from: patient.readableMedicalComorbidities)
        let allergies = commaSeparatedClinicalList(from: patient.readableAllergies)

        var lines: [String] = []

        if comorbidityItems.isEmpty {
            lines.append("Comorbidità mediche: non documentate.")
        } else {
            lines.append("Comorbidità mediche:")
            lines.append(contentsOf: comorbidityItems.map { "- \($0)" })
        }

        if allergies.isEmpty {
            lines.append("Allergie: non documentate.")
        } else {
            lines.append("Allergie: \(allergies).")
        }

        return lines.joined(separator: "\n")
    }

    private func clinicalListItems(from source: String) -> [String] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let separators = CharacterSet(charactersIn: "\n;,•")
        return normalized
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) : $0 }
            .filter { !$0.isEmpty }
    }

    private func commaSeparatedClinicalList(from source: String) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let separators = CharacterSet(charactersIn: "\n;,•")
        let parts = normalized
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) : $0 }
            .filter { !$0.isEmpty }

        return parts.joined(separator: ", ")
    }

    private func remoteHistoryBulletList(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "L'anamnesi psicopatologica remota non evidenzia elementi di rilievo ulteriori rispetto a quanto già documentato."
        }

        let normalized = trimmed.replacingOccurrences(of: "\r\n", with: "\n")
        let separators = CharacterSet(charactersIn: "\n;•")
        var chunks = normalized.components(separatedBy: separators)
        if chunks.count <= 1 {
            chunks = normalized.components(separatedBy: ". ")
        }

        let items = chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { item in
                item.hasPrefix("- ") ? String(item.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) : item
            }

        guard items.count > 1 else {
            return normalizedSnippet(trimmed) + "."
        }

        return items.map { "- " + normalizedSnippet($0) }.joined(separator: "\n")
    }

    private func salutation(for patient: Patient) -> String {
        let normalized = (patient.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "femmina" || normalized == "f" {
            return "La Sig.ra"
        }
        if normalized == "maschio" || normalized == "m" {
            return "Il Sig."
        }
        return "La/Il Sig./Sig.ra"
    }

    private func bornDescriptor(for patient: Patient) -> String {
        let normalized = (patient.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "femmina" || normalized == "f" {
            return "nata"
        }
        if normalized == "maschio" || normalized == "m" {
            return "nato"
        }
        return "nato/a"
    }

    private func patientNounDescriptor(for patient: Patient) -> String {
        let normalized = (patient.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "femmina" || normalized == "f" {
            return "una paziente"
        }
        if normalized == "maschio" || normalized == "m" {
            return "un paziente"
        }
        return "un/una paziente"
    }

    private func followedDescriptor(for patient: Patient) -> String {
        let normalized = (patient.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "femmina" || normalized == "f" {
            return "seguita"
        }
        if normalized == "maschio" || normalized == "m" {
            return "seguito"
        }
        return "seguito/a"
    }

    private func therapyOpeningLine(for patient: Patient) -> String {
        let normalized = (patient.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "femmina" || normalized == "f" {
            return "La paziente al momento"
        }
        if normalized == "maschio" || normalized == "m" {
            return "Il paziente al momento"
        }
        return "Il/La paziente al momento"
    }

    private func followUpDurationDescription(from firstClinicalDate: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: firstClinicalDate, to: now)

        if let years = components.year, years > 0 {
            return years == 1 ? "1 anno" : "\(years) anni"
        }
        if let months = components.month, months > 0 {
            return months == 1 ? "1 mese" : "\(months) mesi"
        }

        let days = max(components.day ?? 0, 0)
        return days == 1 ? "1 giorno" : "\(days) giorni"
    }

    private func activeTherapyLines(for patient: Patient) -> [String] {
        patient.therapyItems
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
    }

    private func makeCurrentTherapyNarrative(for patient: Patient) -> String {
        let lines = activeTherapyLines(for: patient)
        if lines.isEmpty {
            return "Al momento non risulta una terapia farmacologica attiva registrata."
        }
        return "La terapia in atto comprende: \(lines.joined(separator: "; "))."
    }

    private func makeBloodTestsNarrative(for patient: Patient, activeTherapyLines: [String]) -> String {
        let payload = BloodTestsSectionViewModel.decodePayload(from: patient.bloodTestsTableJSON)
        guard !payload.columns.isEmpty else {
            return "Non risultano esami ematochimici registrati in cartella."
        }

        let orderedColumns = payload.columns.sorted { lhs, rhs in
            let leftDate = BloodTestsSectionViewModel.parsedDate(from: lhs.dateText) ?? .distantPast
            let rightDate = BloodTestsSectionViewModel.parsedDate(from: rhs.dateText) ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return lhs.dateText > rhs.dateText
        }

        guard let latestColumn = orderedColumns.first else {
            return "Non risultano esami ematochimici registrati in cartella."
        }

        let focusTests = focusedBloodTests(for: activeTherapyLines)
        let focusValues = extractBloodValues(
            from: payload,
            columnID: latestColumn.id,
            preferredTests: focusTests,
            fallbackLimit: 5
        )

        if focusValues.isEmpty {
            return "È disponibile un controllo ematochimico alla data \(latestColumn.dateText), senza valori testuali utili alla sintesi."
        }

        return "All'ultimo controllo ematochimico del \(latestColumn.dateText) si rilevano: \(focusValues.joined(separator: "; "))."
    }

    private func focusedBloodTests(for activeTherapyLines: [String]) -> [String] {
        let normalizedTherapy = activeTherapyLines
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
            .lowercased()

        var tests: [String] = []

        if normalizedTherapy.contains("litio") {
            tests += ["Litiemia (Li)", "Creatinina (Crea)", "eGFR", "TSH", "Sodio (Na)"]
        }
        if normalizedTherapy.contains("valpro") {
            tests += ["Valproatemia (Ac. valproico)", "AST (GOT)", "ALT (GPT)", "Gamma GT (GGT)", "Ammonio", "Piastrine (PLT)"]
        }
        if normalizedTherapy.contains("carbamazep") {
            tests += ["Carbamazepinemia (Car)", "Sodio (Na)", "AST (GOT)", "ALT (GPT)", "Gamma GT (GGT)", "Leucociti (WBC)"]
        }
        if normalizedTherapy.contains("lamotrig") {
            tests += ["AST (GOT)", "ALT (GPT)", "Gamma GT (GGT)", "Leucociti (WBC)"]
        }

        return Array(NSOrderedSet(array: tests)) as? [String] ?? tests
    }

    private func extractBloodValues(
        from payload: BloodTestsTablePayload,
        columnID: UUID,
        preferredTests: [String],
        fallbackLimit: Int
    ) -> [String] {
        let columnKey = columnID.uuidString

        func value(for testName: String) -> String? {
            let canonical = BloodTestsDefaults.canonicalName(testName)
            let normalizedCanonical = BloodTestsDefaults.normalizedName(canonical)

            guard let row = payload.rows.first(where: {
                BloodTestsDefaults.normalizedName(BloodTestsDefaults.canonicalName($0.testName)) == normalizedCanonical
            }) else {
                return nil
            }

            guard let rawValue = row.values[columnKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
                return nil
            }
            return "\(row.testName): \(rawValue)"
        }

        var collected = preferredTests.compactMap { value(for: $0) }
        if !collected.isEmpty {
            return collected
        }

        for row in payload.rows {
            guard let rawValue = row.values[columnKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
                continue
            }
            collected.append("\(row.testName): \(rawValue)")
            if collected.count >= fallbackLimit {
                break
            }
        }

        return collected
    }

    private func normalizedFullText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = trimmed.replacingOccurrences(of: "\n", with: " ")
        return compact
    }

    private func normalizedSnippet(_ text: String) -> String {
        let compact = normalizedFullText(text)
        if compact.count <= 320 {
            return compact
        }
        let end = compact.index(compact.startIndex, offsetBy: 320)
        return String(compact[..<end]) + "…"
    }

    private func makeAttributedReport(patient: Patient, bodyText: String, generatedAt: Date) -> NSAttributedString {
        let baseFont = NSFont(name: "Times New Roman", size: 12) ?? NSFont.systemFont(ofSize: 12)
        let boldBase = NSFont(name: "Times New Roman Bold", size: 12) ?? NSFont.boldSystemFont(ofSize: 12)
        let titleFont = NSFont(name: "Times New Roman Bold", size: 13) ?? NSFont.boldSystemFont(ofSize: 13)

        let headerParagraph = NSMutableParagraphStyle()
        headerParagraph.alignment = .left
        headerParagraph.lineHeightMultiple = 1.0
        headerParagraph.paragraphSpacing = 2

        let dateParagraph = NSMutableParagraphStyle()
        dateParagraph.alignment = .right
        dateParagraph.lineHeightMultiple = 1.5
        dateParagraph.paragraphSpacing = 24

        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.alignment = .left
        titleParagraph.lineHeightMultiple = 1.5
        titleParagraph.paragraphSpacing = 26

        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.alignment = .left
        bodyParagraph.lineHeightMultiple = 1.5
        bodyParagraph.paragraphSpacing = 10

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: boldBase,
            .foregroundColor: NSColor.black,
            .paragraphStyle: headerParagraph
        ]
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: dateParagraph
        ]
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: titleParagraph
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: bodyParagraph
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: boldBase,
            .foregroundColor: NSColor.black,
            .paragraphStyle: bodyParagraph
        ]

        let result = NSMutableAttributedString()

        let headerLines = reportHeaderLines()
        if headerLines.isEmpty {
            result.append(NSAttributedString(string: "Chirone Gestionale\n", attributes: headerAttrs))
        } else {
            result.append(NSAttributedString(string: headerLines.joined(separator: "\n") + "\n", attributes: headerAttrs))
        }
        result.append(NSAttributedString(string: "\n", attributes: headerAttrs))

        let generatedDateText = reportDateText(from: generatedAt)
        result.append(NSAttributedString(string: generatedDateText + "\n", attributes: dateAttrs))

        let title = reportTitle(for: patient)
        result.append(NSAttributedString(string: title + "\n", attributes: titleAttrs))

        let subtitleSet: Set<String> = [
            "Anamnesi psichiatrica remota",
            "Comorbidità mediche generali ed allergie",
            "Quadro clinico attuale",
            "Terapia psicofarmacologica"
        ]

        for line in bodyText.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let attrs = subtitleSet.contains(trimmed) ? subtitleAttrs : bodyAttrs
            result.append(NSAttributedString(string: line + "\n", attributes: attrs))
        }

        return result
    }

    private func reportDateText(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "dd/MM/yyyy"

        let text = formatter.string(from: date).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }

        let fallback = date.formatted(.dateTime.day().month(.twoDigits).year()).trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty {
            return fallback
        }

        // Final safety fallback: never leave dates blank in report text.
        return "data non disponibile"
    }

    private func reportHeaderLines() -> [String] {
        let defaults = UserDefaults.standard
        let keys = [
            "report.doctorFullName",
            "report.doctorQualification",
            "report.doctorAddress",
            "report.doctorPhoneEmail"
        ]
        return keys
            .compactMap { defaults.string(forKey: $0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func reportTitle(for patient: Patient) -> String {
        let surname = patient.lastName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let name = patient.firstName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let person = [surname, name].filter { !$0.isEmpty }.joined(separator: " ")
        let resolvedPerson = person.isEmpty ? patient.fullName.uppercased() : person
        return "RELAZIONE CLINICA \(resolvedPerson)"
    }
}

private final class ReportPageView: NSView {
    private let content: NSAttributedString
    private let currentPage: Int
    private let totalPages: Int
    private let horizontalMargin: CGFloat
    private let topMargin: CGFloat
    private let bottomMargin: CGFloat
    private let footerHeight: CGFloat

    init(
        pageSize: NSSize,
        content: NSAttributedString,
        currentPage: Int,
        totalPages: Int,
        horizontalMargin: CGFloat,
        topMargin: CGFloat,
        bottomMargin: CGFloat,
        footerHeight: CGFloat
    ) {
        self.content = content
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.horizontalMargin = horizontalMargin
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin
        self.footerHeight = footerHeight
        super.init(frame: NSRect(origin: .zero, size: pageSize))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let contentRect = NSRect(
            x: horizontalMargin,
            y: topMargin,
            width: bounds.width - (horizontalMargin * 2),
            height: bounds.height - topMargin - bottomMargin - footerHeight
        )

        content.draw(
            with: contentRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let footerParagraph = NSMutableParagraphStyle()
        footerParagraph.alignment = .center

        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Times New Roman", size: 10) ?? NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.black,
            .paragraphStyle: footerParagraph
        ]

        let footerText = NSAttributedString(string: "\(currentPage)/\(totalPages)", attributes: footerAttrs)
        let footerRect = NSRect(x: 0, y: 20, width: bounds.width, height: 16)
        footerText.draw(in: footerRect)
    }
}
