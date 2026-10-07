import SwiftUI

struct BeckAssessmentSheet: View {
    let scale: BeckScale
    let patientFullName: String
    let existingAssessment: BeckAssessment?
    let onSave: (Date, [Int]) -> String?
    let onCancel: () -> Void

    @State private var answerIndices = Array(repeating: -1, count: BeckScale.itemCount)
    @State private var assessmentDate: Date = .now
    @State private var saveError: String?

    init(
        scale: BeckScale,
        patientFullName: String,
        existingAssessment: BeckAssessment?,
        onSave: @escaping (Date, [Int]) -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.scale = scale
        self.patientFullName = patientFullName
        self.existingAssessment = existingAssessment
        self.onSave = onSave
        self.onCancel = onCancel
        if let assessment = existingAssessment {
            _assessmentDate = State(initialValue: assessment.date)
            _answerIndices = State(initialValue: (0..<BeckScale.itemCount).map {
                assessment.answerIndices.indices.contains($0) ? assessment.answerIndices[$0] : -1
            })
        }
    }

    private var isReadOnly: Bool { existingAssessment != nil }
    private var totalScore: Int? {
        if let existingAssessment { return existingAssessment.totalScore }
        return scale.totalScore(forAnswers: answerIndices)
    }
    private var completedCount: Int {
        answerIndices.enumerated().filter { scale.questions[$0.offset].options.indices.contains($0.element) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: ClinicalSpacing.m) {
                    Text(scale.instructions)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if scale == .bai {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section {
                                ForEach(0..<BeckScale.itemCount, id: \.self) { index in
                                    baiRow(index)
                                }
                            } header: {
                                baiColumnHeaders
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: ClinicalSpacing.m) {
                            ForEach(0..<BeckScale.itemCount, id: \.self) { index in
                                bdiQuestion(index)
                            }
                        }
                    }
                    Text("Le fasce descrivono la gravità dei sintomi e non costituiscono una diagnosi. Per l’interpretazione secondo le norme italiane, consulta il manuale.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(ClinicalSpacing.l)
            }
            Divider()
            footer
        }
        .frame(width: 820, height: 700)
        .alert("Salvataggio non riuscito", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Riprova a salvare la valutazione.")
        }
    }

    private var header: some View {
        HStack(spacing: ClinicalSpacing.l) {
            VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
                Text("\(isReadOnly ? "Valutazione" : "Nuova valutazione") \(scale.label)")
                    .font(.title2.weight(.semibold))
                Text(patientFullName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(scale.fullName) · \(scale.timeframeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: ClinicalSpacing.xs) {
                Text("Data somministrazione").font(.caption).foregroundStyle(.secondary)
                if let assessment = existingAssessment {
                    Text(assessment.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT"))))
                    AssessmentDateEditButton(assessment: assessment, scaleLabel: scale.label)
                } else {
                    DatePicker("Data somministrazione", selection: $assessmentDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .fixedSize()
                }
            }
        }
        .padding(ClinicalSpacing.l)
    }

    private var baiColumnHeaders: some View {
        HStack(spacing: 0) {
            Text("Sintomo").font(.caption.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(BeckQuestionnaires.baiOptions) { option in
                Text(option.text.replacingOccurrences(of: " — ", with: "\n"))
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .frame(width: 86)
            }
        }
        .padding(ClinicalSpacing.s)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func baiRow(_ index: Int) -> some View {
        HStack(spacing: 0) {
            Text("\(index + 1). \(scale.questions[index].title)")
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(0...3, id: \.self) { answer in
                answerButton(question: index, answer: answer, showsText: false)
                    .frame(width: 86)
            }
        }
        .padding(ClinicalSpacing.s)
        .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.03) : .clear)
    }

    private func bdiQuestion(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
            Text("\(index + 1). \(scale.questions[index].title)")
                .font(.headline)
            ForEach(scale.questions[index].options.indices, id: \.self) { answer in
                answerButton(question: index, answer: answer, showsText: true)
            }
        }
        .padding(ClinicalSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    private func answerButton(question index: Int, answer: Int, showsText: Bool) -> some View {
        let option = scale.questions[index].options[answer]
        let isSelected = answerIndices[index] == answer
        return Button {
            answerIndices[index] = isSelected ? -1 : answer
        } label: {
            HStack(alignment: .center, spacing: ClinicalSpacing.s) {
                Text(option.code)
                    .font(.body.monospacedDigit().weight(.medium))
                    .frame(width: 36, height: 30)
                    .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2)))
                    .foregroundStyle(isSelected ? .white : .primary)
                if showsText {
                    Text(option.text)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
        .help(option.text)
        .accessibilityLabel("Item \(index + 1), risposta \(option.code): \(option.text)")
        .accessibilityValue(isSelected ? "Selezionato" : "Non selezionato")
        .accessibilityIdentifier("beck_item_\(index + 1)_answer_\(option.code)")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
            HStack(spacing: ClinicalSpacing.m) {
                VStack(alignment: .leading, spacing: 3) {
                    if let totalScore, let severity = scale.severity(for: totalScore) {
                        Text("Totale: \(totalScore) / 63 · \(severity.label)")
                            .font(.headline)
                            .foregroundStyle(severity.color)
                    } else {
                        Text("\(completedCount) di 21 risposte")
                            .font(.headline)
                    }
                    Text(totalScore == nil ? "Completa tutti gli item per calcolare il totale." : "Fascia descrittiva del punteggio grezzo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let totalScore, let percentile = scale.italianPercentile(for: totalScore) {
                        Text("Percentile italiano: \(percentile) · modulo 2016")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(isReadOnly ? "Chiudi" : "Annulla", action: onCancel)
                    .keyboardShortcut(.escape)
                if !isReadOnly {
                    Button("Salva valutazione") {
                        guard totalScore != nil else { return }
                        saveError = onSave(assessmentDate, answerIndices)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(totalScore == nil)
                    .accessibilityIdentifier("beck_save_assessment")
                }
            }
            Text(scale.thresholdsText)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if scale.requiresClinicalReview(answerIndices: answerIndices) {
                BeckClinicalReviewNotice()
            }
        }
        .padding(ClinicalSpacing.l)
    }
}

struct BeckClinicalReviewNotice: View {
    var body: some View {
        Label("Item 9 positivo: approfondire clinicamente l’ideazione suicidaria, indipendentemente dal punteggio totale.", systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("beck_clinical_review_notice")
    }
}
