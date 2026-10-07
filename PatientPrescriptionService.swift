import Foundation
import AppKit
import PDFKit

struct PrescriptionMedicationDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    var isIncluded: Bool
}

struct PatientPrescriptionDraft: Equatable, Sendable {
    let patientID: UUID
    var patientDisplayName: String
    var title: String
    var documentDate: Date
    var patientIdentification: String
    var medications: [PrescriptionMedicationDraft]
    var additionalDirections: String
    var includesAdditionalDirections: Bool
    var issues: [ReportValidationIssue]

    var includedMedications: [PrescriptionMedicationDraft] {
        medications.filter { $0.isIncluded && !$0.text.trimmedForPrescription.isEmpty }
    }
}

enum PatientPrescriptionServiceError: Error, Equatable {
    case noActiveTherapy
    case noSelectedMedications
    case emptyTitle
    case emptyDocument
    case paginationDidNotAdvance
    case incompletePagination
    case pageCreationFailed(Int)
    case documentSerializationFailed
    case printOperationUnavailable
}

extension PatientPrescriptionServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noActiveTherapy:
            return "Il paziente non ha farmaci attivi da proporre nella ricetta."
        case .noSelectedMedications:
            return "Seleziona almeno un farmaco da prescrivere."
        case .emptyTitle:
            return "Inserisci un titolo per il documento."
        case .emptyDocument:
            return "La ricetta non contiene testo da esportare."
        case .paginationDidNotAdvance:
            return "Impossibile proseguire nell'impaginazione della ricetta."
        case .incompletePagination:
            return "La ricetta non è stata impaginata integralmente."
        case .pageCreationFailed(let page):
            return "Impossibile generare la pagina \(page) della ricetta."
        case .documentSerializationFailed:
            return "Impossibile serializzare il documento PDF."
        case .printOperationUnavailable:
            return "Il sistema di stampa non è disponibile."
        }
    }
}

@MainActor
final class PatientPrescriptionService {
    static let shared = PatientPrescriptionService()

    private let pageSize = NSSize(width: 595.28, height: 841.89)
    private let pageMargin: CGFloat = 56.7
    private let footerHeight: CGFloat = 24
    private let headerSpacing: CGFloat = 12

    private init() {}

    func makeDraft(
        for patient: Patient,
        generatedAt: Date = .now
    ) throws -> PatientPrescriptionDraft {
        var issues: [ReportValidationIssue] = []
        let identification = makePatientIdentification(for: patient, issues: &issues)
        let actualName = [patient.firstName.trimmedForPrescription, patient.lastName.trimmedForPrescription]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let medications = activeMedicationDrafts(for: patient)

        guard !medications.isEmpty else {
            throw PatientPrescriptionServiceError.noActiveTherapy
        }

        return PatientPrescriptionDraft(
            patientID: patient.id,
            patientDisplayName: actualName.isEmpty ? "Paziente" : actualName,
            title: "Prescrizione medica",
            documentDate: generatedAt,
            patientIdentification: identification,
            medications: medications,
            additionalDirections: "",
            includesAdditionalDirections: false,
            issues: issues
        )
    }

    func render(
        draft: PatientPrescriptionDraft,
        profile: ProfessionalReportProfile
    ) throws -> PDFDocument {
        guard !draft.title.trimmedForPrescription.isEmpty else {
            throw PatientPrescriptionServiceError.emptyTitle
        }
        guard !draft.includedMedications.isEmpty else {
            throw PatientPrescriptionServiceError.noSelectedMedications
        }

        let normalizedProfile = profile.normalized
        let content = makeAttributedPrescription(draft: draft, profile: normalizedProfile)
        guard content.length > 0 else {
            throw PatientPrescriptionServiceError.emptyDocument
        }

        let ranges = try paginatedCharacterRanges(
            for: content,
            firstPageHeaderHeight: firstPageHeaderHeight(for: normalizedProfile)
        )
        guard ranges.reduce(0, { $0 + $1.length }) == content.length,
              ranges.first?.location == 0,
              ranges.last.map(NSMaxRange) == content.length
        else {
            throw PatientPrescriptionServiceError.incompletePagination
        }

        let document = PDFDocument()
        for (index, range) in ranges.enumerated() {
            let pageView = PrescriptionDocumentPageView(
                pageSize: pageSize,
                content: content.attributedSubstring(from: range),
                profile: normalizedProfile,
                documentTitle: draft.title.trimmedForPrescription,
                patientName: draft.patientDisplayName.trimmedForPrescription,
                documentDate: dateText(draft.documentDate),
                currentPage: index + 1,
                totalPages: ranges.count,
                margin: pageMargin,
                footerHeight: footerHeight,
                headerHeight: headerHeight(pageIndex: index, profile: normalizedProfile),
                headerSpacing: headerSpacing
            )

            let pageData = pageView.dataWithPDF(inside: pageView.bounds)
            guard let pageDocument = PDFDocument(data: pageData),
                  pageDocument.pageCount == 1,
                  let page = pageDocument.page(at: 0)
            else {
                throw PatientPrescriptionServiceError.pageCreationFailed(index + 1)
            }
            document.insert(page, at: document.pageCount)
        }

        guard document.pageCount == ranges.count else {
            throw PatientPrescriptionServiceError.incompletePagination
        }

        var attributes: [PDFDocumentAttribute: Any] = [
            .titleAttribute: draft.title.trimmedForPrescription,
            .subjectAttribute: "Prescrizione medica",
            .creationDateAttribute: draft.documentDate
        ]
        if !normalizedProfile.fullName.isEmpty {
            attributes[.authorAttribute] = normalizedProfile.fullName
        }
        document.documentAttributes = attributes

        guard document.dataRepresentation() != nil else {
            throw PatientPrescriptionServiceError.documentSerializationFailed
        }
        return document
    }

    func makePrescriptionDocument(for patient: Patient) throws -> PDFDocument {
        let draft = try makeDraft(for: patient)
        return try render(draft: draft, profile: .current())
    }

    @discardableResult
    func print(document: PDFDocument, jobTitle: String) throws -> Bool {
        guard let printOperation = document.printOperation(
            for: NSPrintInfo.shared,
            scalingMode: .pageScaleDownToFit,
            autoRotate: true
        ) else {
            throw PatientPrescriptionServiceError.printOperationUnavailable
        }

        printOperation.jobTitle = jobTitle
        printOperation.showsProgressPanel = true
        printOperation.showsPrintPanel = true
        printOperation.printPanel.options = [.showsCopies, .showsPaperSize, .showsOrientation, .showsScaling, .showsPreview]
        return printOperation.run()
    }

    private func activeMedicationDrafts(for patient: Patient) -> [PrescriptionMedicationDraft] {
        patient.therapyItems
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .compactMap { medication in
                let nameAndDose = [
                    medication.medicationName.trimmedForPrescription,
                    medication.dosage.trimmedForPrescription
                ]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let posology = medication.posology.normalizedPrescriptionNewlines.trimmedForPrescription
                let text: String
                if nameAndDose.isEmpty {
                    text = posology
                } else if posology.isEmpty {
                    text = nameAndDose
                } else {
                    text = "\(nameAndDose) — \(posology)"
                }
                guard !text.isEmpty else { return nil }
                return PrescriptionMedicationDraft(id: medication.id, text: text, isIncluded: true)
            }
    }

    private func makePatientIdentification(
        for patient: Patient,
        issues: inout [ReportValidationIssue]
    ) -> String {
        var primaryLine: [String] = []
        var secondaryLine: [String] = []
        let name = [patient.firstName.trimmedForPrescription, patient.lastName.trimmedForPrescription]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if name.isEmpty {
            issues.append(.init(id: "prescription.patientName", message: "Nome e cognome del paziente non sono completi."))
        } else {
            primaryLine.append("Nome e cognome: \(name)")
        }

        if let dateOfBirth = patient.dateOfBirth {
            primaryLine.append("Data di nascita: \(dateText(dateOfBirth))")
        } else {
            issues.append(.init(id: "prescription.birthDate", message: "La data di nascita non è registrata."))
        }

        let place = patient.placeOfBirth.trimmedForPrescription
        let province = patient.birthProvince?.trimmedForPrescription ?? ""
        if place.isEmpty {
            issues.append(.init(id: "prescription.birthPlace", message: "Il luogo di nascita non è registrato."))
        } else {
            secondaryLine.append(province.isEmpty ? "Luogo di nascita: \(place)" : "Luogo di nascita: \(place) (\(province))")
        }

        let taxCode = patient.taxCode.trimmedForPrescription.uppercased()
        if taxCode.isEmpty {
            issues.append(.init(id: "prescription.taxCode", message: "Il codice fiscale non è registrato."))
        } else {
            secondaryLine.append("Codice fiscale: \(taxCode)")
        }
        return [primaryLine, secondaryLine]
            .filter { !$0.isEmpty }
            .map { $0.joined(separator: " · ") }
            .joined(separator: "\n")
    }

    private func makeAttributedPrescription(
        draft: PatientPrescriptionDraft,
        profile: ProfessionalReportProfile
    ) -> NSAttributedString {
        let bodyFont = NSFont(name: "Times New Roman", size: 12) ?? NSFont.systemFont(ofSize: 12)
        let bodyBold = NSFont(name: "Times New Roman Bold", size: 12) ?? NSFont.boldSystemFont(ofSize: 12)
        let identificationFont = NSFont(name: "Times New Roman", size: 10.75) ?? NSFont.systemFont(ofSize: 10.75)
        let titleFont = NSFont(name: "Times New Roman Bold", size: 15) ?? NSFont.boldSystemFont(ofSize: 15)
        let result = NSMutableAttributedString()

        result.append(NSAttributedString(
            string: draft.title.trimmedForPrescription + "\n",
            attributes: [
                .font: titleFont,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraphStyle(alignment: .center, lineHeight: 1.15, spacingAfter: 8)
            ]
        ))
        result.append(NSAttributedString(
            string: "Data: \(dateText(draft.documentDate))\n",
            attributes: [
                .font: bodyFont,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraphStyle(alignment: .right, lineHeight: 1.1, spacingAfter: 12)
            ]
        ))

        let identification = draft.patientIdentification.normalizedPrescriptionNewlines.trimmedForPrescription
        if !identification.isEmpty {
            appendHeading("Dati del paziente", to: result, font: bodyBold, spacingBefore: 4, spacingAfter: 3)
            result.append(NSAttributedString(
                string: identification + "\n",
                attributes: [
                    .font: identificationFont,
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: paragraphStyle(alignment: .left, lineHeight: 1.05, spacingAfter: 10)
                ]
            ))
        }

        appendHeading("Si prescrive", to: result, font: bodyBold)
        let listStyle = paragraphStyle(alignment: .left, lineHeight: 1.35, spacingAfter: 10)
        for medication in draft.includedMedications {
            result.append(NSAttributedString(
                string: "• \(medication.text.normalizedPrescriptionNewlines.trimmedForPrescription)\n",
                attributes: [
                    .font: bodyFont,
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: listStyle
                ]
            ))
        }

        let directions = draft.additionalDirections.normalizedPrescriptionNewlines.trimmedForPrescription
        if draft.includesAdditionalDirections && !directions.isEmpty {
            appendHeading("Indicazioni aggiuntive", to: result, font: bodyBold)
            result.append(NSAttributedString(
                string: directions + "\n",
                attributes: [
                    .font: bodyFont,
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: paragraphStyle(alignment: .left, lineHeight: 1.3, spacingAfter: 12)
                ]
            ))
        }

        let signatureStart = result.length
        let doctorName = profile.fullName.trimmedForPrescription
        let signatureText = doctorName.isEmpty
            ? "Firma e timbro del medico\n"
            : "Firma e timbro del medico\n\n\n\(doctorName)\n"
        result.append(NSAttributedString(
            string: "\n" + signatureText,
            attributes: [
                .font: bodyFont,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraphStyle(alignment: .right, lineHeight: 1.2, spacingBefore: 18, spacingAfter: 2)
            ]
        ))
        let contextStart = signatureContextStart(in: result.string as NSString, before: signatureStart)
        result.addAttribute(
            .prescriptionKeepTogether,
            value: true,
            range: NSRange(location: contextStart, length: result.length - contextStart)
        )

        return result
    }

    private func signatureContextStart(in text: NSString, before signatureStart: Int) -> Int {
        guard signatureStart > 0 else { return 0 }
        var contentEnd = signatureStart
        while contentEnd > 0 {
            let characterRange = text.rangeOfComposedCharacterSequence(at: contentEnd - 1)
            let character = text.substring(with: characterRange)
            if character.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil { break }
            contentEnd = characterRange.location
        }

        let searchStart = max(0, contentEnd - 280)
        let newline = text.range(
            of: "\n",
            options: .backwards,
            range: NSRange(location: searchStart, length: contentEnd - searchStart)
        )
        let candidate = newline.location == NSNotFound ? searchStart : NSMaxRange(newline)
        guard candidate < text.length else { return candidate }
        return text.rangeOfComposedCharacterSequence(at: candidate).location
    }

    private func appendHeading(
        _ text: String,
        to result: NSMutableAttributedString,
        font: NSFont,
        spacingBefore: CGFloat = 8,
        spacingAfter: CGFloat = 6
    ) {
        result.append(NSAttributedString(
            string: text + "\n",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraphStyle(
                    alignment: .left,
                    lineHeight: 1.2,
                    spacingBefore: spacingBefore,
                    spacingAfter: spacingAfter
                ),
                .prescriptionHeading: true
            ]
        ))
    }

    private func paragraphStyle(
        alignment: NSTextAlignment,
        lineHeight: CGFloat,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineHeightMultiple = lineHeight
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        return style
    }

    private func firstPageHeaderHeight(for profile: ProfessionalReportProfile) -> CGFloat {
        profile.headerLines.isEmpty ? 0 : 66
    }

    private func headerHeight(pageIndex: Int, profile: ProfessionalReportProfile) -> CGFloat {
        pageIndex == 0 ? firstPageHeaderHeight(for: profile) : 28
    }

    private func contentSize(pageIndex: Int, firstPageHeaderHeight: CGFloat) -> NSSize {
        let headerHeight = pageIndex == 0 ? firstPageHeaderHeight : 28
        let spacing = headerHeight > 0 ? headerSpacing : 0
        return NSSize(
            width: pageSize.width - (pageMargin * 2),
            height: pageSize.height - (pageMargin * 2) - footerHeight - headerHeight - spacing
        )
    }

    private func paginatedCharacterRanges(
        for content: NSAttributedString,
        firstPageHeaderHeight: CGFloat
    ) throws -> [NSRange] {
        var ranges: [NSRange] = []
        var location = 0
        let keepTogetherRanges = attributedRanges(for: .prescriptionKeepTogether, in: content)

        while location < content.length {
            let size = contentSize(pageIndex: ranges.count, firstPageHeaderHeight: firstPageHeaderHeight)
            var range = fittingCharacterRange(in: content, startingAt: location, size: size)
            guard range.length > 0 else {
                throw PatientPrescriptionServiceError.paginationDidNotAdvance
            }
            range = adjustedRange(range, in: content, keepTogetherRanges: keepTogetherRanges)
            guard range.length > 0, range.location == location else {
                throw PatientPrescriptionServiceError.paginationDidNotAdvance
            }
            ranges.append(range)
            location = NSMaxRange(range)
        }

        guard !ranges.isEmpty, location == content.length else {
            throw PatientPrescriptionServiceError.incompletePagination
        }
        return ranges
    }

    private func fittingCharacterRange(
        in content: NSAttributedString,
        startingAt location: Int,
        size: NSSize
    ) -> NSRange {
        let remainingRange = NSRange(location: location, length: content.length - location)
        let storage = NSTextStorage(attributedString: content.attributedSubstring(from: remainingRange))
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: size)
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        let glyphRange = layoutManager.glyphRange(for: container)
        let relativeRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        return NSRange(location: location, length: relativeRange.length)
    }

    private func adjustedRange(
        _ proposed: NSRange,
        in content: NSAttributedString,
        keepTogetherRanges: [NSRange]
    ) -> NSRange {
        var adjusted = proposed
        let proposedEnd = NSMaxRange(proposed)

        if let keepRange = keepTogetherRanges.first(where: {
            $0.location >= proposed.location && $0.location < proposedEnd && NSMaxRange($0) > proposedEnd
        }), keepRange.location > proposed.location {
            adjusted.length = keepRange.location - proposed.location
        }

        var lastHeadingRange: NSRange?
        content.enumerateAttribute(.prescriptionHeading, in: adjusted) { value, range, _ in
            if value != nil { lastHeadingRange = range }
        }
        if let heading = lastHeadingRange {
            let afterHeadingLocation = NSMaxRange(heading)
            let adjustedEnd = NSMaxRange(adjusted)
            if afterHeadingLocation <= adjustedEnd {
                let afterRange = NSRange(location: afterHeadingLocation, length: adjustedEnd - afterHeadingLocation)
                let afterText = (content.string as NSString).substring(with: afterRange).trimmedForPrescription
                if afterText.isEmpty && heading.location > adjusted.location {
                    adjusted.length = heading.location - adjusted.location
                }
            }
        }
        return adjusted.length > 0 ? adjusted : proposed
    }

    private func attributedRanges(
        for key: NSAttributedString.Key,
        in content: NSAttributedString
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        content.enumerateAttribute(key, in: NSRange(location: 0, length: content.length)) { value, range, _ in
            if value != nil { ranges.append(range) }
        }
        return ranges
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }
}

private final class PrescriptionDocumentPageView: NSView {
    private let content: NSAttributedString
    private let profile: ProfessionalReportProfile
    private let documentTitle: String
    private let patientName: String
    private let documentDate: String
    private let currentPage: Int
    private let totalPages: Int
    private let margin: CGFloat
    private let footerHeight: CGFloat
    private let headerHeight: CGFloat
    private let headerSpacing: CGFloat

    override var isFlipped: Bool { true }

    init(
        pageSize: NSSize,
        content: NSAttributedString,
        profile: ProfessionalReportProfile,
        documentTitle: String,
        patientName: String,
        documentDate: String,
        currentPage: Int,
        totalPages: Int,
        margin: CGFloat,
        footerHeight: CGFloat,
        headerHeight: CGFloat,
        headerSpacing: CGFloat
    ) {
        self.content = content
        self.profile = profile
        self.documentTitle = documentTitle
        self.patientName = patientName
        self.documentDate = documentDate
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.margin = margin
        self.footerHeight = footerHeight
        self.headerHeight = headerHeight
        self.headerSpacing = headerSpacing
        super.init(frame: NSRect(origin: .zero, size: pageSize))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        drawHeader()

        let spacing = headerHeight > 0 ? headerSpacing : 0
        let contentY = margin + headerHeight + spacing
        let contentRect = NSRect(
            x: margin,
            y: contentY,
            width: bounds.width - (margin * 2),
            height: bounds.height - contentY - margin - footerHeight
        )
        content.draw(with: contentRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        drawFooter()
    }

    private func drawHeader() {
        guard headerHeight > 0 else { return }
        let regular = NSFont(name: "Times New Roman", size: 9.5) ?? NSFont.systemFont(ofSize: 9.5)
        let bold = NSFont(name: "Times New Roman Bold", size: 11) ?? NSFont.boldSystemFont(ofSize: 11)
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineHeightMultiple = 1.05

        let text: NSMutableAttributedString
        if currentPage == 1 {
            text = NSMutableAttributedString(
                string: profile.headerLines.joined(separator: "\n"),
                attributes: [.font: regular, .foregroundColor: NSColor.black, .paragraphStyle: style]
            )
            if !profile.fullName.isEmpty {
                text.addAttribute(.font, value: bold, range: (text.string as NSString).range(of: profile.fullName))
            }
        } else {
            text = NSMutableAttributedString(
                string: "\(documentTitle) — \(patientName)\n\(documentDate)",
                attributes: [.font: regular, .foregroundColor: NSColor.black, .paragraphStyle: style]
            )
            text.addAttribute(.font, value: bold, range: (text.string as NSString).range(of: documentTitle))
        }
        text.draw(in: NSRect(x: margin, y: margin, width: bounds.width - (margin * 2), height: headerHeight - 5))

        NSColor(calibratedWhite: 0.68, alpha: 1).setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: margin, y: margin + headerHeight))
        line.line(to: NSPoint(x: bounds.width - margin, y: margin + headerHeight))
        line.lineWidth = 0.5
        line.stroke()
    }

    private func drawFooter() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let text = NSAttributedString(
            string: "Pagina \(currentPage) di \(totalPages)",
            attributes: [
                .font: NSFont(name: "Times New Roman", size: 9) ?? NSFont.systemFont(ofSize: 9),
                .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1),
                .paragraphStyle: style
            ]
        )
        text.draw(in: NSRect(
            x: margin,
            y: bounds.height - margin - footerHeight + 8,
            width: bounds.width - (margin * 2),
            height: 14
        ))
    }
}

private extension NSAttributedString.Key {
    static let prescriptionHeading = NSAttributedString.Key("it.chirone.prescription.heading")
    static let prescriptionKeepTogether = NSAttributedString.Key("it.chirone.prescription.keepTogether")
}

private extension String {
    var trimmedForPrescription: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedPrescriptionNewlines: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
