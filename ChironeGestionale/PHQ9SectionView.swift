import SwiftUI
import SwiftData

struct PHQ9ScaleContent: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var patient: Patient
    @State private var isPresentingNewAssessment = false
    @State private var showingDeleteError = false

    private var sortedAssessments: [PHQ9Assessment] {
        AssessmentDateEditing.sorted(patient.phq9Assessments)
    }

    var body: some View {
        let sortedAssessments = self.sortedAssessments
        let records = sortedAssessments.map { PsychometricTrendRecord($0) }
        let configuration = PsychometricTrendConfiguration.phq9
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
                PHQ9AssessmentSheet(
                    patientFullName: patient.fullName,
                    onSave: { date, scores in
                        guard PsychometricResponseValidation.isComplete(scores, itemCount: 9, range: 0...3) else { return "Completa tutte le risposte prima di salvare." }
                        let previousUpdatedAt = patient.updatedAt
                        let assessment = PHQ9Assessment(date: date, scores: scores, patient: patient)
                        modelContext.insert(assessment)
                        patient.phq9Assessments.append(assessment)
                        patient.updatedAt = .now
                        do {
                            try modelContext.save()
                            isPresentingNewAssessment = false
                            return nil
                        } catch {
                            patient.phq9Assessments.removeAll { $0.id == assessment.id }
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

private extension PHQ9ScaleContent {
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
        do { try AssessmentDeletion.delete(assessment, in: modelContext) }
        catch { showingDeleteError = true }
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

            if let score = PsychometricTrendRecord(assessment).score {
                Text("\(score) / 27").font(.body.monospacedDigit())
                PHQ9SeverityBadge(severity: assessment.severity)
            } else {
                Text("Non valida").foregroundStyle(.secondary)
            }

            Spacer()

            AssessmentDateEditButton(assessment: assessment, scaleLabel: "PHQ-9")

            Button {
                showingDeleteAlert = true
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Elimina valutazione")
            .accessibilityLabel("Elimina valutazione PHQ9")
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
