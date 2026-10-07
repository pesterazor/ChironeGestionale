import SwiftUI

struct PHQ9AssessmentSheet: View {
    let patientFullName: String
    let onSave: (Date, [Int]) -> Void
    let onCancel: () -> Void

    @State private var scores: [Int] = Array(repeating: 0, count: 9)
    @State private var assessmentDate: Date = .now

    private var totalScore: Int { scores.reduce(0, +) }
    private var severity: PHQ9Severity { PHQ9Severity.from(score: totalScore) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
            Divider()
            questionList
            Divider()
            sheetFooter
        }
        .frame(minWidth: 740, minHeight: 520)
    }
}

private extension PHQ9AssessmentSheet {
    var sheetHeader: some View {
        HStack(alignment: .center, spacing: ClinicalSpacing.l) {
            VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
                Text("Nuova valutazione PHQ-9")
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

    var questionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                columnHeaders
                ForEach(Array(PHQ9.questions.enumerated()), id: \.offset) { index, question in
                    PHQ9QuestionRow(
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

    var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("Item")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(Array(PHQ9.shortAnswerLabels.enumerated()), id: \.offset) { index, label in
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

    var sheetFooter: some View {
        HStack(alignment: .center, spacing: ClinicalSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: ClinicalSpacing.s) {
                    Text("Punteggio totale:")
                        .font(.subheadline.weight(.medium))
                    Text("\(totalScore)")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("/ 27")
                        .foregroundStyle(.secondary)
                    Text("—")
                        .foregroundStyle(.secondary)
                    Text(severity.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(severity.color)
                }
                Text("0–4 Minimale · 5–9 Lieve · 10–14 Moderata · 15–19 Mod. grave · 20–27 Grave")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Annulla") { onCancel() }
                .keyboardShortcut(.escape)

            Button("Salva valutazione") {
                onSave(assessmentDate, scores)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(ClinicalSpacing.l)
    }
}

private struct PHQ9QuestionRow: View {
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
                        score = value
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
                    .help(PHQ9.answerLabels[value])
                    .frame(width: 88)
                }
            }
        }
        .padding(.horizontal, ClinicalSpacing.l)
        .padding(.vertical, 11)
        .background(isEven ? Color.primary.opacity(0.025) : Color.clear)
    }
}
