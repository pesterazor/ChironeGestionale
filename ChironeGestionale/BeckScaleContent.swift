import SwiftData
import SwiftUI

struct BeckScaleContent: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var patient: Patient
    let scale: BeckScale

    @State private var isPresentingNewAssessment = false
    @State private var showingDeleteError = false
    @State private var detailAssessment: BeckAssessment?
    @State private var assessmentToDelete: BeckAssessment?

    private var assessments: [BeckAssessment] {
        BeckAssessment.sorted(patient.beckAssessments, for: scale)
    }

    var body: some View {
        let assessments = self.assessments
        let records = assessments.map { PsychometricTrendRecord($0) }
        let configuration = PsychometricTrendConfiguration.beck(scale)
        let trend = PsychometricTrendData(newestFirst: records, maximum: configuration.maximum)
        return VStack(alignment: .leading, spacing: ClinicalSpacing.m) {
            if let latest = assessments.first {
                PsychometricTrendView(data: trend, configuration: configuration) {
                    latestScoreCard(latest, record: records[0], configuration: configuration)
                }
                history(for: assessments)
            } else {
                emptyState
            }
            HStack {
                Button("Nuova valutazione") { isPresentingNewAssessment = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("beck_new_\(scale.rawValue)")
                Spacer()
                Link("Edizione italiana e manuale", destination: scale.publisherURL)
                    .font(.caption)
            }
            Text("Le fasce del punteggio grezzo descrivono la gravità dei sintomi e non costituiscono una diagnosi. Consulta il manuale per l’interpretazione clinica.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .alert("Eliminazione non riuscita", isPresented: $showingDeleteError) {
            Button("OK", role: .cancel) {}
        } message: { Text("La valutazione è stata conservata. Riprova a eliminarla.") }
        .sheet(isPresented: $isPresentingNewAssessment) {
            AppLockGateView {
                BeckAssessmentSheet(
                    scale: scale,
                    patientFullName: patient.fullName,
                    existingAssessment: nil,
                    onSave: saveAssessment,
                    onCancel: { isPresentingNewAssessment = false }
                )
            }
        }
        .sheet(item: $detailAssessment) { assessment in
            AppLockGateView {
                BeckAssessmentSheet(
                    scale: scale,
                    patientFullName: patient.fullName,
                    existingAssessment: assessment,
                    onSave: { _, _ in nil },
                    onCancel: { detailAssessment = nil }
                )
            }
        }
        .confirmationDialog("Eliminare questa valutazione?", isPresented: Binding(
            get: { assessmentToDelete != nil },
            set: { if !$0 { assessmentToDelete = nil } }
        ), presenting: assessmentToDelete) { assessment in
            Button("Elimina", role: .destructive) {
                do { try AssessmentDeletion.delete(assessment, in: modelContext) }
                catch { showingDeleteError = true }
                assessmentToDelete = nil
            }
            Button("Annulla", role: .cancel) { assessmentToDelete = nil }
        } message: { assessment in
            Text("La valutazione \(scale.label) del \(dateText(assessment.date)) verrà eliminata definitivamente.")
        }
    }

    private func latestScoreCard(_ assessment: BeckAssessment, record: PsychometricTrendRecord, configuration: PsychometricTrendConfiguration) -> some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
            PsychometricLatestScore(record: record, configuration: configuration)
            if let score = record.score, let percentile = scale.italianPercentile(for: score) {
                Text("Percentile italiano: \(percentile) · modulo 2016")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Dettagli") { detailAssessment = assessment }
            if assessment.requiresClinicalReview { BeckClinicalReviewNotice() }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        VStack(spacing: ClinicalSpacing.s) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("Nessuna valutazione \(scale.label) registrata")
                .font(.headline)
            Text(scale.fullName)
                .font(.subheadline.weight(.medium))
            Text(scale.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, ClinicalSpacing.l)
    }

    private func history(for assessments: [BeckAssessment]) -> some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
            Text("Storico valutazioni").font(.subheadline.weight(.medium))
            ForEach(assessments) { assessment in
                HStack(spacing: ClinicalSpacing.m) {
                    Text(dateText(assessment.date)).frame(width: 120, alignment: .leading)
                    if let score = assessment.totalScore, let severity = assessment.severity {
                        Text("\(score) / 63").monospacedDigit()
                        Text(severity.label).foregroundStyle(severity.color)
                    } else {
                        Text("Non valida").foregroundStyle(.secondary)
                    }
                    if assessment.requiresClinicalReview {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help("Item 9 positivo: approfondimento clinico necessario")
                    }
                    Spacer()
                    AssessmentDateEditButton(assessment: assessment, scaleLabel: scale.label)
                    Button("Dettagli") { detailAssessment = assessment }
                    Button {
                        assessmentToDelete = assessment
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Elimina valutazione \(scale.label) del \(dateText(assessment.date))")
                }
                .padding(ClinicalSpacing.s)
                Divider()
            }
        }
    }

    private func saveAssessment(date: Date, answerIndices: [Int]) -> String? {
        guard scale.totalScore(forAnswers: answerIndices) != nil else {
            return "Seleziona una risposta per ciascuno dei 21 item."
        }
        let previousUpdatedAt = patient.updatedAt
        let assessment = BeckAssessment(scale: scale, date: date, answerIndices: answerIndices, patient: patient)
        modelContext.insert(assessment)
        patient.beckAssessments.append(assessment)
        patient.updatedAt = .now
        do {
            try modelContext.save()
            isPresentingNewAssessment = false
            return nil
        } catch {
            patient.beckAssessments.removeAll { $0.id == assessment.id }
            modelContext.delete(assessment)
            patient.updatedAt = previousUpdatedAt
            return "La valutazione non è stata salvata. I punteggi rimangono nella scheda: riprova."
        }
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT")))
    }
}
