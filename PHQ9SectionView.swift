import SwiftUI
import Charts
import SwiftData

struct PHQ9SectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var patient: Patient
    @State private var isPresentingNewAssessment = false

    private var sortedAssessments: [PHQ9Assessment] {
        patient.phq9Assessments.sorted { $0.date > $1.date }
    }

    var body: some View {
        ClinicalSectionBox("PHQ-9 — Depressione", systemImage: "brain.head.profile") {
            if sortedAssessments.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: ClinicalSpacing.m) {
                    if let latest = sortedAssessments.first {
                        latestScoreCard(latest)
                    }
                    if sortedAssessments.count >= 2 {
                        scoreChart(for: sortedAssessments)
                    }
                    historyTable(for: sortedAssessments)
                    Button("Nuova valutazione") {
                        isPresentingNewAssessment = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .sheet(isPresented: $isPresentingNewAssessment) {
            PHQ9AssessmentSheet(
                patientFullName: patient.fullName,
                onSave: { date, scores in
                    let assessment = PHQ9Assessment(date: date, scores: scores, patient: patient)
                    modelContext.insert(assessment)
                    patient.phq9Assessments.append(assessment)
                    patient.updatedAt = .now
                    isPresentingNewAssessment = false
                },
                onCancel: {
                    isPresentingNewAssessment = false
                }
            )
        }
    }
}

private extension PHQ9SectionView {
    var emptyState: some View {
        VStack(spacing: ClinicalSpacing.m) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            VStack(spacing: ClinicalSpacing.xs) {
                Text("Nessuna valutazione PHQ-9 registrata")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Il PHQ-9 è uno strumento standardizzato a 9 item per lo screening e il monitoraggio della depressione.")
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

    func latestScoreCard(_ assessment: PHQ9Assessment) -> some View {
        HStack(alignment: .center, spacing: ClinicalSpacing.l) {
            VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
                Text("Ultima valutazione")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(assessment.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT"))))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(assessment.totalScore)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("/ 27")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Text(assessment.severity.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(assessment.severity.color)
            }

            Spacer(minLength: 0)

            PHQ9SeverityBadge(severity: assessment.severity)
        }
        .padding(ClinicalSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.12))
        )
    }

    func scoreChart(for assessments: [PHQ9Assessment]) -> some View {
        let chronological = assessments.reversed()

        return VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
            Text("Andamento nel tempo")
                .font(.subheadline.weight(.medium))

            Chart {
                RuleMark(y: .value("Lieve", 5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.yellow.opacity(0.55))
                RuleMark(y: .value("Moderata", 10))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.orange.opacity(0.55))
                RuleMark(y: .value("Mod. grave", 15))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.red.opacity(0.45))
                RuleMark(y: .value("Grave", 20))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.red.opacity(0.70))

                ForEach(Array(chronological), id: \.id) { assessment in
                    LineMark(
                        x: .value("Data", assessment.date),
                        y: .value("PHQ-9", assessment.totalScore)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Data", assessment.date),
                        y: .value("PHQ-9", assessment.totalScore)
                    )
                    .foregroundStyle(assessment.severity.color)
                    .symbolSize(55)
                    .annotation(position: .top, spacing: 4) {
                        Text("\(assessment.totalScore)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartYScale(domain: 0...27)
            .chartYAxis {
                AxisMarks(values: [0, 5, 10, 15, 20, 27]) { value in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Locale(identifier: "it_IT")))
                }
            }
            .frame(height: 190)
            .padding(.top, ClinicalSpacing.s)

            HStack(spacing: ClinicalSpacing.m) {
                ForEach([PHQ9Severity.minimal, .mild, .moderate, .moderatelySevere, .severe], id: \.rawValue) { sev in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(sev.color)
                            .frame(width: 8, height: 8)
                        Text("\(sev.label) (\(sev.scoreRange))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    func historyTable(for assessments: [PHQ9Assessment]) -> some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
            Text("Storico valutazioni")
                .font(.subheadline.weight(.medium))

            VStack(spacing: 0) {
                ForEach(Array(assessments.enumerated()), id: \.element.id) { index, assessment in
                    PHQ9AssessmentRow(assessment: assessment) {
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

    func deleteAssessment(_ assessment: PHQ9Assessment) {
        patient.phq9Assessments.removeAll { $0.id == assessment.id }
        modelContext.delete(assessment)
        patient.updatedAt = .now
    }
}

private struct PHQ9SeverityBadge: View {
    let severity: PHQ9Severity

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

private struct PHQ9AssessmentRow: View {
    let assessment: PHQ9Assessment
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showingDeleteAlert = false

    var body: some View {
        HStack(spacing: ClinicalSpacing.m) {
            Text(assessment.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT"))))
                .font(.body)
                .frame(width: 120, alignment: .leading)

            Text("\(assessment.totalScore) / 27")
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)

            PHQ9SeverityBadge(severity: assessment.severity)

            Spacer()

            if isHovered {
                Button {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Elimina valutazione")
            }
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
