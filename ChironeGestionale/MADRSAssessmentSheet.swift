import SwiftUI

struct MADRSAssessmentSheet: View {
    let patientFullName: String
    let existingAssessment: MADRSAssessment?
    let onSave: (Date, [Int], String) -> String?
    let onCancel: () -> Void

    @State private var scores = Array(repeating: -1, count: MADRS.itemCount)
    @State private var assessmentDate: Date = .now
    @State private var raterName = ""
    @State private var saveError: String?

    init(patientFullName: String, existingAssessment: MADRSAssessment? = nil, onSave: @escaping (Date, [Int], String) -> String?, onCancel: @escaping () -> Void) {
        self.patientFullName = patientFullName
        self.existingAssessment = existingAssessment
        self.onSave = onSave
        self.onCancel = onCancel
        if let assessment = existingAssessment {
            _scores = State(initialValue: (0..<MADRS.itemCount).map {
                assessment.scores.indices.contains($0) ? assessment.scores[$0] : -1
            })
            _assessmentDate = State(initialValue: assessment.date)
            _raterName = State(initialValue: assessment.raterName)
        }
    }

    private var isReadOnly: Bool { existingAssessment != nil }
    private var totalScore: Int? {
        if let existingAssessment { return existingAssessment.totalScore }
        return MADRS.totalScore(for: scores)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: ClinicalSpacing.m) {
                    Text(isReadOnly
                         ? "Valutazione compilata dal clinico. Sono riportate le risposte salvate; i valori 1, 3 e 5 indicano situazioni intermedie fra le descrizioni adiacenti."
                         : "Valutazione a cura del clinico. Seleziona un punteggio per ciascun item sulla base del colloquio e dell’osservazione. I valori 1, 3 e 5 indicano situazioni intermedie fra le descrizioni adiacenti.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(MADRS.questions.indices, id: \.self) { index in
                        questionView(index)
                    }
                }
                .padding(ClinicalSpacing.l)
            }
            Divider()
            footer
        }
        .frame(width: 820, height: 700)
        .alert("Salvataggio non riuscito", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Riprova a salvare la valutazione.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: ClinicalSpacing.l) {
            VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
                Text("\(isReadOnly ? "Valutazione" : "Nuova valutazione") MADRS")
                    .font(.title2.weight(.semibold))
                Text(patientFullName).foregroundStyle(.secondary)
                Text(MADRS.fullName).font(.caption).foregroundStyle(.secondary)
                if isReadOnly {
                    if !raterName.isEmpty { Text("Valutatore: \(raterName)").font(.caption) }
                } else {
                    TextField("Valutatore (facoltativo)", text: $raterName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 330)
                        .accessibilityIdentifier("madrs_rater_name")
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: ClinicalSpacing.s) {
                Text("Data somministrazione").font(.caption).foregroundStyle(.secondary)
                if let assessment = existingAssessment {
                    Text(assessment.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT"))))
                    AssessmentDateEditButton(assessment: assessment, scaleLabel: "MADRS")
                } else {
                    DatePicker("Data somministrazione", selection: $assessmentDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
            }
        }
        .padding(ClinicalSpacing.l)
    }

    private func questionView(_ index: Int) -> some View {
        let question = MADRS.questions[index]
        return VStack(alignment: .leading, spacing: ClinicalSpacing.m) {
            Text("\(index + 1). \(question.title)").font(.headline)
            HStack(alignment: .top, spacing: ClinicalSpacing.l) {
                Text(question.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 250, alignment: .leading)
                VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
                    ForEach(0...6, id: \.self) { value in
                        answerButton(item: index, value: value)
                    }
                }
            }
        }
        .padding(ClinicalSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    private func answerButton(item: Int, value: Int) -> some View {
        let isSelected = scores[item] == value
        let label = MADRS.questions[item].answerLabel(for: value)
        let content = HStack(spacing: ClinicalSpacing.s) {
            Text("\(value)")
                .font(.body.monospacedDigit().weight(.medium))
                .frame(width: 32, height: 30)
                .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2)))
                .foregroundStyle(isSelected ? .white : .primary)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(value.isMultiple(of: 2) ? .primary : .secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        return Group {
            if isReadOnly {
                content.accessibilityElement(children: .ignore)
            } else {
                Button { scores[item] = isSelected ? -1 : value } label: { content }
                    .buttonStyle(.plain)
            }
        }
        .accessibilityLabel("Item \(item + 1), punteggio \(value): \(label)")
        .accessibilityValue(isSelected ? "Selezionato" : "Non selezionato")
        .accessibilityIdentifier("madrs_item_\(item + 1)_score_\(value)")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
            HStack(spacing: ClinicalSpacing.m) {
                VStack(alignment: .leading, spacing: 3) {
                    if let totalScore, let severity = MADRSSeverity.from(score: totalScore) {
                        Text("Totale: \(totalScore) / 60 · \(severity.label)")
                            .font(.headline)
                            .foregroundStyle(severity.color)
                    } else {
                        Text("\(scores.filter { (0...6).contains($0) }.count) di 10 item valutati")
                            .font(.headline)
                    }
                    Text(totalScore == nil ? "Completa tutti gli item per calcolare il totale." : "Fascia descrittiva di gravità dei sintomi, non diagnosi.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(isReadOnly ? "Chiudi" : "Annulla", action: onCancel).keyboardShortcut(.escape)
                if !isReadOnly {
                    Button("Salva valutazione") {
                        guard totalScore != nil else { return }
                        saveError = onSave(assessmentDate, scores, raterName.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(totalScore == nil)
                    .accessibilityIdentifier("madrs_save_assessment")
                }
            }
            Text(MADRS.thresholdsText).font(.caption2).foregroundStyle(.secondary)
            if MADRS.requiresClinicalReview(scores: scores) { MADRSClinicalReviewNotice() }
        }
        .padding(ClinicalSpacing.l)
    }
}

struct MADRSClinicalReviewNotice: View {
    var body: some View {
        Label("Item 10 con punteggio > 0: approfondire clinicamente l’ideazione suicidaria, indipendentemente dal totale.", systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("madrs_clinical_review_notice")
    }
}
