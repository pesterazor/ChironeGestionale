import SwiftUI
import SwiftData

struct GAD7ScaleContent: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var patient: Patient
    @State private var isPresentingNewAssessment = false
    @State private var showingDeleteError = false

    private var sortedAssessments: [GAD7Assessment] {
        AssessmentDateEditing.sorted(patient.gad7Assessments)
    }

    var body: some View {
        let sortedAssessments = self.sortedAssessments
        let records = sortedAssessments.map { PsychometricTrendRecord($0) }
        let configuration = PsychometricTrendConfiguration.gad7
        let trend = PsychometricTrendData(newestFirst: records, maximum: configuration.maximum)
        return Group {
            if sortedAssessments.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: ClinicalSpacing.m) {
                    if !records.isEmpty {
                        PsychometricTrendView(data: trend, configuration: configuration) {
                            PsychometricLatestScore(record: records[0], configuration: configuration)
                        }
                    }
                    historyTable(for: sortedAssessments)
                    Button("Nuova valutazione") {
                        isPresentingNewAssessment = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .alert("Eliminazione non riuscita", isPresented: $showingDeleteError) {
            Button("OK", role: .cancel) {}
        } message: { Text("La valutazione è stata conservata. Riprova a eliminarla.") }
        .sheet(isPresented: $isPresentingNewAssessment) {
            AppLockGateView {
                GAD7AssessmentSheet(
                    patientFullName: patient.fullName,
                    onSave: { date, scores in
                        guard PsychometricResponseValidation.isComplete(scores, itemCount: 7, range: 0...3) else { return "Completa tutte le risposte prima di salvare." }
                        let previousUpdatedAt = patient.updatedAt
                        let assessment = GAD7Assessment(date: date, scores: scores, patient: patient)
                        modelContext.insert(assessment)
                        patient.gad7Assessments.append(assessment)
                        patient.updatedAt = .now
                        do {
                            try modelContext.save()
                            isPresentingNewAssessment = false
                            return nil
                        } catch {
                            patient.gad7Assessments.removeAll { $0.id == assessment.id }
                            modelContext.delete(assessment)
                            patient.updatedAt = previousUpdatedAt
                            return "La valutazione non è stata salvata. Le risposte sono ancora nella scheda: riprova."
                        }
                    },
                    onCancel: {
                        isPresentingNewAssessment = false
                    }
                )
            }
        }
    }
}

private extension GAD7ScaleContent {
    var emptyState: some View {
        VStack(spacing: ClinicalSpacing.m) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            VStack(spacing: ClinicalSpacing.xs) {
                Text("Nessuna valutazione GAD-7 registrata")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Il GAD-7 è uno strumento standardizzato a 7 item per lo screening e il monitoraggio dei disturbi d'ansia generalizzata.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            Button("Nuova valutazione") {
                isPresentingNewAssessment = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ClinicalSpacing.l)
    }

    func historyTable(for assessments: [GAD7Assessment]) -> some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
            Text("Storico valutazioni")
                .font(.subheadline.weight(.medium))

            VStack(spacing: 0) {
                ForEach(Array(assessments.enumerated()), id: \.element.id) { index, assessment in
                    GAD7AssessmentRow(assessment: assessment) {
                        deleteAssessment(assessment)
                    }
                    if index < assessments.count - 1 {
                        Divider()
                            .padding(.horizontal, ClinicalSpacing.m)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.secondary.opacity(0.12))
            )
        }
    }

    func deleteAssessment(_ assessment: GAD7Assessment) {
        do { try AssessmentDeletion.delete(assessment, in: modelContext) }
        catch { showingDeleteError = true }
    }
}

// MARK: - Shared subviews

private struct GAD7SeverityBadge: View {
    let severity: GAD7Severity

    var body: some View {
        Text(severity.label.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.4)
            .foregroundStyle(severity.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(severity.color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(severity.color.opacity(0.35)))
    }
}

private struct GAD7AssessmentRow: View {
    let assessment: GAD7Assessment
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showingDeleteAlert = false

    var body: some View {
        HStack(spacing: ClinicalSpacing.m) {
            Text(assessment.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT"))))
                .font(.body)
                .frame(width: 120, alignment: .leading)

            if let score = PsychometricTrendRecord(assessment).score {
                Text("\(score) / 21").font(.body.monospacedDigit())
                GAD7SeverityBadge(severity: assessment.severity)
            } else {
                Text("Non valida").foregroundStyle(.secondary)
            }

            Spacer()

            AssessmentDateEditButton(assessment: assessment, scaleLabel: "GAD-7")

            Button {
                showingDeleteAlert = true
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Elimina valutazione")
            .accessibilityLabel("Elimina valutazione GAD7")
        }
        .padding(.horizontal, ClinicalSpacing.m)
        .padding(.vertical, 10)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .alert("Eliminare questa valutazione?", isPresented: $showingDeleteAlert) {
            Button("Elimina", role: .destructive) { onDelete() }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("La valutazione del \(assessment.date.formatted(.dateTime.day().month(.abbreviated).year())) verrà eliminata definitivamente.")
        }
    }
}

// MARK: - Assessment sheet

struct GAD7AssessmentSheet: View {
    let patientFullName: String
    let onSave: (Date, [Int]) -> String?
    let onCancel: () -> Void

    @State private var scores: [Int] = Array(repeating: -1, count: 7)
    @State private var saveError: String?
    @State private var assessmentDate: Date = .now

    private var isComplete: Bool { PsychometricResponseValidation.isComplete(scores, itemCount: 7, range: 0...3) }
    private var totalScore: Int { scores.filter { $0 >= 0 }.reduce(0, +) }
    private var severity: GAD7Severity { GAD7Severity.from(score: totalScore) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
            Divider()
            questionList
            Divider()
            sheetFooter
        }
        .frame(minWidth: 740, minHeight: 460)
        .alert("Valutazione non salvata", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "Riprova a salvare la valutazione.") }
    }

    private var sheetHeader: some View {
        HStack(alignment: .center, spacing: ClinicalSpacing.l) {
            VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
                Text("Nuova valutazione GAD-7")
                    .font(.title2.weight(.semibold))
                Text(patientFullName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: ClinicalSpacing.xs) {
                Text("Data somministrazione")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker("", selection: $assessmentDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
        }
        .padding(ClinicalSpacing.l)
    }

    private var questionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                columnHeaders
                ForEach(Array(GAD7.questions.enumerated()), id: \.offset) { index, question in
                    GAD7QuestionRow(
                        number: index + 1,
                        question: question,
                        score: $scores[index],
                        isEven: index.isMultiple(of: 2)
                    )
                }
                Text("Nelle ultime 2 settimane, con quale frequenza ha avuto i disturbi elencati?")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, ClinicalSpacing.l)
                    .padding(.top, ClinicalSpacing.m)
                    .padding(.bottom, ClinicalSpacing.s)
            }
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("Item")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(Array(GAD7.shortAnswerLabels.enumerated()), id: \.offset) { index, label in
                    VStack(spacing: 2) {
                        Text("\(index)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 88)
                }
            }
        }
        .padding(.horizontal, ClinicalSpacing.l)
        .padding(.vertical, ClinicalSpacing.s)
        .background(Color.primary.opacity(0.04))
    }

    private var sheetFooter: some View {
        HStack(alignment: .center, spacing: ClinicalSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                if isComplete {
                    HStack(alignment: .firstTextBaseline, spacing: ClinicalSpacing.s) {
                        Text("Punteggio totale:")
                            .font(.subheadline.weight(.medium))
                        Text("\(totalScore)")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text("/ 21")
                            .foregroundStyle(.secondary)
                        Text("—")
                            .foregroundStyle(.secondary)
                        Text(severity.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(severity.color)
                    }
                } else {
                    Text("\(scores.filter { (0...3).contains($0) }.count) di 7 risposte completate")
                        .font(.headline)
                    Text("Rispondi a tutti gli item per calcolare il risultato.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("0–4 Minima · 5–9 Lieve · 10–14 Moderata · 15–21 Grave")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Annulla") { onCancel() }
                .keyboardShortcut(.escape)

            Button("Salva valutazione") {
                guard isComplete else { return }
                saveError = onSave(assessmentDate, scores)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!isComplete)
        }
        .padding(ClinicalSpacing.l)
    }
}

private struct GAD7QuestionRow: View {
    let number: Int
    let question: String
    @Binding var score: Int
    let isEven: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .top, spacing: ClinicalSpacing.s) {
                Text("\(number).")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
                Text(question)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(0..<4) { value in
                    Button {
                        score = score == value ? -1 : value
                    } label: {
                        ZStack {
                            Circle()
                                .fill(score == value ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                            Circle()
                                .strokeBorder(
                                    score == value ? Color.accentColor : Color.secondary.opacity(0.30),
                                    lineWidth: 1.5
                                )
                            if score == value {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(value)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help(GAD7.answerLabels[value])
                    .accessibilityLabel("Item \(number): \(GAD7.answerLabels[value])")
                    .accessibilityValue(score == value ? "Selezionato" : "Non selezionato")
                    .frame(width: 88)
                }
            }
        }
        .padding(.horizontal, ClinicalSpacing.l)
        .padding(.vertical, 11)
        .background(isEven ? Color.primary.opacity(0.025) : Color.clear)
    }
}
