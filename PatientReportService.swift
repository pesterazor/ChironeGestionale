import Foundation
import AppKit
import PDFKit

struct ReportValidationIssue: Identifiable, Equatable, Sendable {
    let id: String
    let message: String
}

struct ProfessionalReportProfile: Equatable, Sendable {
    var fullName: String
    var qualification: String
    var registration: String
    var address: String
    var contacts: String

    static func current(defaults: UserDefaults = .standard) -> ProfessionalReportProfile {
        ProfessionalReportProfile(
            fullName: defaults.string(forKey: "report.doctorFullName") ?? "",
            qualification: defaults.string(forKey: "report.doctorQualification") ?? "",
            registration: defaults.string(forKey: "report.doctorRegistration") ?? "",
            address: defaults.string(forKey: "report.doctorAddress") ?? "",
            contacts: defaults.string(forKey: "report.doctorPhoneEmail") ?? ""
        ).normalized
    }

    var normalized: ProfessionalReportProfile {
        ProfessionalReportProfile(
            fullName: fullName.trimmedForReport,
            qualification: qualification.trimmedForReport,
            registration: registration.trimmedForReport,
            address: address.trimmedForReport,
            contacts: contacts.trimmedForReport
        )
    }

    var headerLines: [String] {
        [fullName, qualification, registration, address, contacts]
            .map(\.trimmedForReport)
            .filter { !$0.isEmpty }
    }

    var validationIssues: [ReportValidationIssue] {
        var issues: [ReportValidationIssue] = []
        if fullName.trimmedForReport.isEmpty {
            issues.append(.init(
                id: "profile.name",
                message: "Il nome del professionista non è configurato: intestazione e firma resteranno prive del nominativo."
            ))
        }
        if qualification.trimmedForReport.isEmpty {
            issues.append(.init(
                id: "profile.qualification",
                message: "La qualifica professionale non è configurata."
            ))
        }
        if registration.trimmedForReport.isEmpty {
            issues.append(.init(
                id: "profile.registration",
                message: "Gli estremi di iscrizione all'albo non sono configurati."
            ))
        }
        return issues
    }
}

struct ReportOptions: Equatable, Sendable {
    var recentNotesCount: Int
    var includeRecentNotes: Bool
    var includePsychometricScales: Bool

    nonisolated init(
        recentNotesCount: Int = 3,
        includeRecentNotes: Bool = false,
        includePsychometricScales: Bool = false
    ) {
        self.recentNotesCount = min(max(recentNotesCount, 1), 8)
        self.includeRecentNotes = includeRecentNotes
        self.includePsychometricScales = includePsychometricScales
    }
}

struct ClinicalReportSection: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case demographics
        case diagnoses
        case remoteHistory
        case comorbiditiesAndAllergies
        case currentClinicalStatus
        case currentTherapy
        case bloodTests
        case recentNotes
        case psychometricScales
        case conclusions
    }

    enum Source: String, Sendable {
        case demographics
        case clinicalRecord
        case clinicalNotes
        case therapy
        case bloodTests
        case psychometricScales
        case clinician
    }

    var id: Kind { kind }
    let kind: Kind
    var title: String
    var text: String
    var isIncluded: Bool
    let source: Source
}

struct ClinicalReportDraft: Equatable, Sendable {
    let patientID: UUID
    var patientDisplayName: String
    var title: String
    var documentDate: Date
    var sections: [ClinicalReportSection]
    var issues: [ReportValidationIssue]

    var includedSections: [ClinicalReportSection] {
        sections.filter { $0.isIncluded && !$0.text.trimmedForReport.isEmpty }
    }
}

enum PatientReportServiceError: Error, Equatable {
    case emptyDocument
    case paginationDidNotAdvance
    case incompletePagination
    case pageCreationFailed(Int)
    case documentSerializationFailed
    case printOperationUnavailable
}

extension PatientReportServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyDocument:
            return "La relazione non contiene sezioni da esportare."
        case .paginationDidNotAdvance:
            return "Impossibile proseguire nell'impaginazione del documento."
        case .incompletePagination:
            return "Il documento non è stato impaginato integralmente."
        case .pageCreationFailed(let page):
            return "Impossibile generare la pagina \(page) del documento."
        case .documentSerializationFailed:
            return "Impossibile serializzare il documento PDF."
        case .printOperationUnavailable:
            return "Il sistema di stampa non è disponibile."
        }
    }
}

@MainActor
final class PatientReportService {
    static let shared = PatientReportService()

    private let pageSize = NSSize(width: 595.28, height: 841.89)
    private let pageMargin: CGFloat = 56.7
    private let footerHeight: CGFloat = 24
    private let headerSpacing: CGFloat = 12

    private init() {}

    func makeDraft(
        for patient: Patient,
        options: ReportOptions = ReportOptions(),
        generatedAt: Date = .now
    ) -> ClinicalReportDraft {
        let actualName = [patient.firstName.trimmedForReport, patient.lastName.trimmedForReport]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let displayName = actualName.isEmpty ? "Paziente" : actualName
        var issues: [ReportValidationIssue] = []

        if actualName.isEmpty {
            issues.append(.init(id: "patient.name", message: "Nome e cognome del paziente non sono completi."))
        }

        let demographics = makeDemographicsText(for: patient, displayName: actualName, issues: &issues)
        let diagnoses = makeDiagnosesText(for: patient, issues: &issues)
        let remoteHistory = patient.readableRemotePsychiatricHistory.normalizedReportNewlines.trimmedForReport
        if remoteHistory.isEmpty {
            issues.append(.init(id: "clinical.remoteHistory", message: "L'anamnesi psichiatrica remota non è documentata e sarà omessa."))
        }

        let comorbidities = makeComorbiditiesAndAllergiesText(for: patient, issues: &issues)
        let clinicalNotes = ClinicalNote.timelineSorted(patient.clinicalNotes)
            .filter { !$0.isAutomaticSystemUpdate && !$0.readableContent.trimmedForReport.isEmpty }
        let currentNote = clinicalNotes.first
        let currentStatus = makeCurrentClinicalStatusText(from: currentNote, issues: &issues)
        let therapy = makeCurrentTherapyText(for: patient, issues: &issues)
        let bloodTests = makeBloodTestsText(for: patient, issues: &issues)
        let recentNotes = makeRecentNotesText(
            from: clinicalNotes.filter { $0.id != currentNote?.id },
            limit: options.recentNotesCount
        )
        let psychometrics = makePsychometricScalesText(for: patient)

        let sections: [ClinicalReportSection] = [
            section(.demographics, "Dati anagrafici", demographics, source: .demographics),
            section(.diagnoses, "Inquadramento diagnostico", diagnoses, source: .clinicalRecord),
            section(.remoteHistory, "Anamnesi psichiatrica remota", remoteHistory, source: .clinicalRecord),
            section(.comorbiditiesAndAllergies, "Comorbidità mediche e allergie", comorbidities, source: .clinicalRecord),
            section(.currentClinicalStatus, "Quadro clinico attuale", currentStatus, source: .clinicalNotes),
            section(.currentTherapy, "Terapia psicofarmacologica", therapy, source: .therapy),
            section(.bloodTests, "Esami ematochimici", bloodTests, source: .bloodTests),
            section(
                .recentNotes,
                "Note cliniche recenti",
                recentNotes,
                isIncluded: options.includeRecentNotes && !recentNotes.isEmpty,
                source: .clinicalNotes
            ),
            section(
                .psychometricScales,
                "Valutazioni psicometriche",
                psychometrics,
                isIncluded: options.includePsychometricScales && !psychometrics.isEmpty,
                source: .psychometricScales
            ),
            section(
                .conclusions,
                "Conclusioni",
                "",
                isIncluded: false,
                source: .clinician
            )
        ]

        return ClinicalReportDraft(
            patientID: patient.id,
            patientDisplayName: displayName,
            title: "Relazione clinica",
            documentDate: generatedAt,
            sections: sections,
            issues: issues
        )
    }

    func render(
        draft: ClinicalReportDraft,
        profile: ProfessionalReportProfile
    ) throws -> PDFDocument {
        guard !draft.includedSections.isEmpty else {
            throw PatientReportServiceError.emptyDocument
        }

        let content = makeAttributedDocument(draft: draft, profile: profile.normalized)
        guard content.length > 0 else {
            throw PatientReportServiceError.emptyDocument
        }

        let normalizedProfile = profile.normalized
        let ranges = try paginatedCharacterRanges(
            for: content,
            firstPageHeaderHeight: firstPageHeaderHeight(for: normalizedProfile)
        )
        guard ranges.reduce(0, { $0 + $1.length }) == content.length,
              ranges.first?.location == 0,
              ranges.last.map(NSMaxRange) == content.length
        else {
            throw PatientReportServiceError.incompletePagination
        }

        let document = PDFDocument()
        for (index, range) in ranges.enumerated() {
            let pageView = ClinicalReportPageView(
                pageSize: pageSize,
                content: content.attributedSubstring(from: range),
                profile: normalizedProfile,
                documentTitle: draft.title,
                patientName: draft.patientDisplayName,
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
                throw PatientReportServiceError.pageCreationFailed(index + 1)
            }
            document.insert(page, at: document.pageCount)
        }

        guard document.pageCount == ranges.count else {
            throw PatientReportServiceError.incompletePagination
        }

        var attributes: [PDFDocumentAttribute: Any] = [
            .titleAttribute: draft.title,
            .subjectAttribute: "Relazione clinica",
            .creationDateAttribute: draft.documentDate
        ]
        if !normalizedProfile.fullName.isEmpty {
            attributes[.authorAttribute] = normalizedProfile.fullName
        }
        document.documentAttributes = attributes

        guard document.dataRepresentation() != nil else {
            throw PatientReportServiceError.documentSerializationFailed
        }
        return document
    }

    func makeReportDocument(for patient: Patient, latestNotesCount: Int) throws -> PDFDocument {
        let draft = makeDraft(
            for: patient,
            options: ReportOptions(recentNotesCount: latestNotesCount)
        )
        return try render(draft: draft, profile: .current())
    }

    @discardableResult
    func print(document: PDFDocument, jobTitle: String) throws -> Bool {
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
        return printOperation.run()
    }

    private func section(
        _ kind: ClinicalReportSection.Kind,
        _ title: String,
        _ text: String,
        isIncluded: Bool? = nil,
        source: ClinicalReportSection.Source
    ) -> ClinicalReportSection {
        let normalizedText = text.normalizedReportNewlines.trimmedForReport
        return ClinicalReportSection(
            kind: kind,
            title: title,
            text: normalizedText,
            isIncluded: isIncluded ?? !normalizedText.isEmpty,
            source: source
        )
    }

    private func makeDemographicsText(
        for patient: Patient,
        displayName: String,
        issues: inout [ReportValidationIssue]
    ) -> String {
        var primaryLine: [String] = []
        var secondaryLine: [String] = []
        if !displayName.isEmpty {
            primaryLine.append("Nome e cognome: \(displayName)")
        }
        if let dateOfBirth = patient.dateOfBirth {
            primaryLine.append("Data di nascita: \(dateText(dateOfBirth))")
            if let age = patient.ageInYears {
                primaryLine.append("Età: \(age) anni")
            }
        } else {
            issues.append(.init(id: "patient.birthDate", message: "La data di nascita non è registrata e sarà omessa."))
        }

        let place = patient.placeOfBirth.trimmedForReport
        let province = patient.birthProvince?.trimmedForReport ?? ""
        if !place.isEmpty {
            secondaryLine.append(province.isEmpty ? "Luogo di nascita: \(place)" : "Luogo di nascita: \(place) (\(province))")
        } else {
            issues.append(.init(id: "patient.birthPlace", message: "Il luogo di nascita non è registrato e sarà omesso."))
        }

        let taxCode = patient.taxCode.trimmedForReport
        if !taxCode.isEmpty {
            secondaryLine.append("Codice fiscale: \(taxCode)")
        }
        return [primaryLine, secondaryLine]
            .filter { !$0.isEmpty }
            .map { $0.joined(separator: " · ") }
            .joined(separator: "\n")
    }

    private func makeDiagnosesText(
        for patient: Patient,
        issues: inout [ReportValidationIssue]
    ) -> String {
        let primary = patient.readablePrimaryDiagnosis.trimmedForReport
        let secondary = patient.readableSecondaryDiagnosis.trimmedForReport
        var lines: [String] = []
        if !primary.isEmpty { lines.append("Diagnosi principale: \(primary)") }
        if !secondary.isEmpty { lines.append("Diagnosi secondaria: \(secondary)") }
        if lines.isEmpty {
            issues.append(.init(id: "clinical.diagnoses", message: "Non sono registrate diagnosi; la sezione sarà omessa."))
        }
        return lines.joined(separator: "\n")
    }

    private func makeComorbiditiesAndAllergiesText(
        for patient: Patient,
        issues: inout [ReportValidationIssue]
    ) -> String {
        let comorbidities = patient.readableMedicalComorbidities.normalizedReportNewlines.trimmedForReport
        let allergies = patient.readableAllergies.normalizedReportNewlines.trimmedForReport
        var blocks: [String] = []
        if !comorbidities.isEmpty { blocks.append("Comorbidità mediche\n\(comorbidities)") }
        if !allergies.isEmpty { blocks.append("Allergie\n\(allergies)") }
        if blocks.isEmpty {
            issues.append(.init(
                id: "clinical.comorbidities",
                message: "Comorbidità e allergie non sono documentate; la sezione sarà omessa."
            ))
        }
        return blocks.joined(separator: "\n\n")
    }

    private func makeCurrentClinicalStatusText(
        from note: ClinicalNote?,
        issues: inout [ReportValidationIssue]
    ) -> String {
        guard let note else {
            issues.append(.init(
                id: "clinical.currentStatus",
                message: "Non è disponibile una nota clinica descrittiva per il quadro attuale."
            ))
            return ""
        }
        return "Valutazione del \(dateText(note.createdAt))\n\n\(note.readableContent.normalizedReportNewlines.trimmedForReport)"
    }

    private func makeCurrentTherapyText(
        for patient: Patient,
        issues: inout [ReportValidationIssue]
    ) -> String {
        let lines = activeTherapyLines(for: patient)
        if lines.isEmpty {
            issues.append(.init(id: "clinical.therapy", message: "Non è registrata una terapia attiva; la sezione sarà omessa."))
        }
        return lines.map { "• \($0)" }.joined(separator: "\n")
    }

    private func activeTherapyLines(for patient: Patient) -> [String] {
        patient.therapyItems
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.medicationName != rhs.medicationName { return lhs.medicationName < rhs.medicationName }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { item in
                let head = [item.medicationName.trimmedForReport, item.dosage.trimmedForReport]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let posology = item.posology.trimmedForReport
                if head.isEmpty { return posology }
                if posology.isEmpty { return head }
                return "\(head) — \(posology)"
            }
            .filter { !$0.isEmpty }
    }

    private func makeBloodTestsText(
        for patient: Patient,
        issues: inout [ReportValidationIssue]
    ) -> String {
        let payload = BloodTestsSectionViewModel.decodePayload(from: patient.bloodTestsTableJSON)
        let orderedColumns = payload.columns.sorted { lhs, rhs in
            let left = BloodTestsSectionViewModel.parsedDate(from: lhs.dateText) ?? .distantPast
            let right = BloodTestsSectionViewModel.parsedDate(from: rhs.dateText) ?? .distantPast
            if left != right { return left > right }
            return lhs.dateText > rhs.dateText
        }
        guard let latest = orderedColumns.first else {
            issues.append(.init(id: "clinical.bloodTests", message: "Non sono registrati esami ematochimici; la sezione sarà omessa."))
            return ""
        }

        let values = extractBloodValues(
            from: payload,
            columnID: latest.id,
            preferredTests: focusedBloodTests(for: activeTherapyLines(for: patient)),
            fallbackLimit: 5
        )
        guard !values.isEmpty else {
            issues.append(.init(
                id: "clinical.bloodTestValues",
                message: "L'ultimo controllo ematochimico non contiene valori testuali da riportare."
            ))
            return ""
        }
        return (["Controllo del \(latest.dateText)"] + values.map { "• \($0)" }).joined(separator: "\n")
    }

    private func focusedBloodTests(for therapyLines: [String]) -> [String] {
        let therapy = therapyLines.joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
            .lowercased()
        var tests: [String] = []
        if therapy.contains("litio") {
            tests += ["Litiemia (Li)", "Creatinina (Crea)", "eGFR", "TSH", "Sodio (Na)"]
        }
        if therapy.contains("valpro") {
            tests += ["Valproatemia (Ac. valproico)", "AST (GOT)", "ALT (GPT)", "Gamma GT (GGT)", "Ammonio", "Piastrine (PLT)"]
        }
        if therapy.contains("carbamazep") {
            tests += ["Carbamazepinemia (Car)", "Sodio (Na)", "AST (GOT)", "ALT (GPT)", "Gamma GT (GGT)", "Leucociti (WBC)"]
        }
        if therapy.contains("lamotrig") {
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
            }), let value = row.values[columnKey]?.trimmedForReport, !value.isEmpty else {
                return nil
            }
            return "\(row.testName): \(value)"
        }

        let focused = preferredTests.compactMap(value)
        if !focused.isEmpty { return focused }

        return payload.rows.compactMap { row -> String? in
            guard let value = row.values[columnKey]?.trimmedForReport, !value.isEmpty else { return nil }
            return "\(row.testName): \(value)"
        }
        .prefix(fallbackLimit)
        .map { $0 }
    }

    private func makeRecentNotesText(from notes: [ClinicalNote], limit: Int) -> String {
        notes.prefix(limit).map { note in
            "Nota del \(dateText(note.createdAt))\n\(note.readableContent.normalizedReportNewlines.trimmedForReport)"
        }
        .joined(separator: "\n\n")
    }

    private func makePsychometricScalesText(for patient: Patient) -> String {
        var lines: [String] = []
        if let latest = AssessmentDateEditing.sorted(patient.phq9Assessments).first {
            lines.append("PHQ-9 del \(dateText(latest.date)): \(latest.totalScore)/27 — gravità \(latest.severity.label.lowercased()).")
        }
        if let latest = AssessmentDateEditing.sorted(patient.gad7Assessments).first {
            lines.append("GAD-7 del \(dateText(latest.date)): \(latest.totalScore)/21 — gravità \(latest.severity.label.lowercased()).")
        }
        if let latest = AssessmentDateEditing.sorted(patient.mdqAssessments).first {
            let outcome = latest.isScreenPositive ? "screening positivo" : "screening negativo"
            lines.append("MDQ del \(dateText(latest.date)): \(latest.part1YesCount)/13 risposte positive — \(outcome).")
        }
        for scale in BeckScale.allCases {
            if let latest = BeckAssessment.sorted(patient.beckAssessments, for: scale).first {
                if let score = latest.totalScore, let severity = latest.severity {
                    lines.append("\(scale.label) del \(dateText(latest.date)): \(score)/63 — fascia descrittiva di gravità \(severity.label.lowercased()) dei sintomi (punteggio grezzo).")
                    if let percentile = scale.italianPercentile(for: score) {
                        lines.append("BAI: percentile \(percentile) secondo le norme italiane del modulo, ristampa 2016.")
                    }
                } else {
                    lines.append("\(scale.label) del \(dateText(latest.date)): punteggi incompleti o non validi, non interpretabili.")
                }
                if latest.requiresClinicalReview {
                    lines.append("BDI-II: item 9 positivo; necessario approfondimento clinico dell’ideazione suicidaria, indipendentemente dal totale.")
                }
            }
        }
        if let latest = AssessmentDateEditing.sorted(patient.madrsAssessments).first {
            if let score = latest.totalScore, let severity = latest.severity {
                lines.append("MADRS del \(dateText(latest.date)): \(score)/60 — fascia descrittiva di gravità \(severity.label.lowercased()) dei sintomi, valutazione clinica.")
            } else {
                lines.append("MADRS del \(dateText(latest.date)): punteggi incompleti o non validi, non interpretabili.")
            }
            if !latest.raterName.isEmpty { lines.append("MADRS: valutatore \(latest.raterName).") }
            if latest.requiresClinicalReview {
                lines.append("MADRS: item 10 con punteggio > 0; necessario approfondimento clinico dell’ideazione suicidaria, indipendentemente dal totale.")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func makeAttributedDocument(
        draft: ClinicalReportDraft,
        profile: ProfessionalReportProfile
    ) -> NSAttributedString {
        let bodyFont = NSFont(name: "Times New Roman", size: 11.5) ?? NSFont.systemFont(ofSize: 11.5)
        let bodyBold = NSFont(name: "Times New Roman Bold", size: 11.5) ?? NSFont.boldSystemFont(ofSize: 11.5)
        let demographicsFont = NSFont(name: "Times New Roman", size: 10.75) ?? NSFont.systemFont(ofSize: 10.75)
        let demographicsBold = NSFont(name: "Times New Roman Bold", size: 11) ?? NSFont.boldSystemFont(ofSize: 11)
        let titleFont = NSFont(name: "Times New Roman Bold", size: 15) ?? NSFont.boldSystemFont(ofSize: 15)
        let patientFont = NSFont(name: "Times New Roman Bold", size: 12) ?? NSFont.boldSystemFont(ofSize: 12)

        let titleStyle = paragraphStyle(alignment: .center, lineHeight: 1.15, spacingAfter: 5)
        let patientStyle = paragraphStyle(alignment: .center, lineHeight: 1.15, spacingAfter: 3)
        let dateStyle = paragraphStyle(alignment: .center, lineHeight: 1.1, spacingAfter: 12)
        let headingStyle = paragraphStyle(alignment: .left, lineHeight: 1.2, spacingBefore: 10, spacingAfter: 5)
        let bodyStyle = paragraphStyle(alignment: .left, lineHeight: 1.28, spacingAfter: 7)
        let demographicsHeadingStyle = paragraphStyle(alignment: .left, lineHeight: 1.05, spacingBefore: 7, spacingAfter: 3)
        let demographicsBodyStyle = paragraphStyle(alignment: .left, lineHeight: 1.05, spacingAfter: 5)
        let signatureStyle = paragraphStyle(alignment: .right, lineHeight: 1.2, spacingBefore: 24, spacingAfter: 2)

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: draft.title.trimmedForReport + "\n", attributes: [
            .font: titleFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: titleStyle
        ]))
        result.append(NSAttributedString(string: draft.patientDisplayName.trimmedForReport + "\n", attributes: [
            .font: patientFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: patientStyle
        ]))
        result.append(NSAttributedString(string: "Data: \(dateText(draft.documentDate))\n", attributes: [
            .font: bodyFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: dateStyle
        ]))

        for section in draft.includedSections {
            let isDemographics = section.kind == .demographics
            let heading = NSMutableAttributedString(string: section.title.trimmedForReport + "\n", attributes: [
                .font: isDemographics ? demographicsBold : bodyBold,
                .foregroundColor: NSColor.black,
                .paragraphStyle: isDemographics ? demographicsHeadingStyle : headingStyle,
                .reportHeading: true
            ])
            result.append(heading)
            result.append(NSAttributedString(string: section.text.normalizedReportNewlines.trimmedForReport + "\n", attributes: [
                .font: isDemographics ? demographicsFont : bodyFont,
                .foregroundColor: NSColor.black,
                .paragraphStyle: isDemographics ? demographicsBodyStyle : bodyStyle
            ]))
        }

        let doctorName = profile.fullName.trimmedForReport
        if !doctorName.isEmpty {
            let signatureStart = result.length
            let signature = NSMutableAttributedString(string: "\nFirma\n\n\n" + doctorName + "\n", attributes: [
                .font: bodyFont,
                .foregroundColor: NSColor.black,
                .paragraphStyle: signatureStyle
            ])
            signature.addAttribute(.font, value: bodyBold, range: (signature.string as NSString).range(of: "Firma"))
            result.append(signature)
            let contextStart = signatureContextStart(in: result.string as NSString, before: signatureStart)
            result.addAttribute(
                .reportKeepTogether,
                value: true,
                range: NSRange(location: contextStart, length: result.length - contextStart)
            )
        }
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
        let keepTogetherRanges = attributedRanges(for: .reportKeepTogether, in: content)

        while location < content.length {
            let size = contentSize(pageIndex: ranges.count, firstPageHeaderHeight: firstPageHeaderHeight)
            var range = fittingCharacterRange(in: content, startingAt: location, size: size)
            guard range.length > 0 else { throw PatientReportServiceError.paginationDidNotAdvance }

            range = adjustedRange(
                range,
                in: content,
                keepTogetherRanges: keepTogetherRanges
            )
            guard range.length > 0, range.location == location else {
                throw PatientReportServiceError.paginationDidNotAdvance
            }
            ranges.append(range)
            location = NSMaxRange(range)
        }

        guard location == content.length else {
            throw PatientReportServiceError.incompletePagination
        }
        return ranges
    }

    private func fittingCharacterRange(
        in content: NSAttributedString,
        startingAt location: Int,
        size: NSSize
    ) -> NSRange {
        let remaining = content.attributedSubstring(from: NSRange(location: location, length: content.length - location))
        let storage = NSTextStorage(attributedString: remaining)
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
        content.enumerateAttribute(.reportHeading, in: adjusted) { value, range, _ in
            if value != nil { lastHeadingRange = range }
        }
        if let heading = lastHeadingRange {
            let afterHeadingLocation = NSMaxRange(heading)
            let adjustedEnd = NSMaxRange(adjusted)
            if afterHeadingLocation <= adjustedEnd {
                let afterRange = NSRange(location: afterHeadingLocation, length: adjustedEnd - afterHeadingLocation)
                let afterText = (content.string as NSString).substring(with: afterRange).trimmedForReport
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

final class ClinicalReportPageView: NSView {
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
            text = NSMutableAttributedString(string: profile.headerLines.joined(separator: "\n"), attributes: [
                .font: regular,
                .foregroundColor: NSColor.black,
                .paragraphStyle: style
            ])
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
    static let reportHeading = NSAttributedString.Key("it.chirone.report.heading")
    static let reportKeepTogether = NSAttributedString.Key("it.chirone.report.keepTogether")
}

private extension String {
    var trimmedForReport: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedReportNewlines: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
