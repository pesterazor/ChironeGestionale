import SwiftData
import SwiftUI

struct MADRSScaleContent: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var patient: Patient
    @State private var isPresentingNewAssessment = false
    @State private var showingDeleteError = false
    @State private var detailAssessment: MADRSAssessment?
    @State private var assessmentToDelete: MADRSAssessment?

    private var assessments: [MADRSAssessment] {
        AssessmentDateEditing.sorted(patient.madrsAssessments)
    }

    var body: some View {
        let assessments = self.assessments
        let records = assessments.map { PsychometricTrendRecord($0) }
        let configuration = PsychometricTrendConfiguration.madrs
        let trend = PsychometricTrendData(newestFirst: records, maximum: configuration.maximum)
        return VStack(alignment: .leading, spacing: ClinicalSpacing.m) {
            if let latest = assessments.first {
                PsychometricTrendView(data: trend, configuration: configuration) {
                    latestScoreCard(latest, record: records[0], configuration: configuration)
                }
                history(for: assessments)
            } else {
                VStack(spacing: ClinicalSpacing.s) {
                    Image(systemName: "list.clipboard").font(.system(size: 38)).foregroundStyle(.secondary)
                    Text("Nessuna valutazione MADRS registrata").font(.headline)
                    Text(MADRS.fullName).font(.subheadline.weight(.medium))
                    Text("Scala a 10 item compilata dal clinico per valutare la gravità dei sintomi depressivi.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ClinicalSpacing.l)
            }
            Button("Nuova valutazione") { isPresentingNewAssessment = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("madrs_new_assessment")
            Text("Le fasce del punteggio totale sono descrittive e non costituiscono una diagnosi.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .alert("Eliminazione non riuscita", isPresented: $showingDeleteError) {
            Button("OK", role: .cancel) {}
        } message: { Text("La valutazione è stata conservata. Riprova a eliminarla.") }
        .sheet(isPresented: $isPresentingNewAssessment) {
            AppLockGateView {
                MADRSAssessmentSheet(patientFullName: patient.fullName, onSave: saveAssessment, onCancel: { isPresentingNewAssessment = false })
            }
        }
        .sheet(item: $detailAssessment) { assessment in
            AppLockGateView {
                MADRSAssessmentSheet(
                    patientFullName: patient.fullName, existingAssessment: assessment,
                    onSave: { _, _, _ in nil }, onCancel: { detailAssessment = nil }
                )
            }
        }
        .confirmationDialog("Eliminare questa valutazione?", isPresented: Binding(
            get: { assessmentToDelete != nil }, set: { if !$0 { assessmentToDelete = nil } }
        ), presenting: assessmentToDelete) { assessment in
            Button("Elimina", role: .destructive) {
                do { try AssessmentDeletion.delete(assessment, in: modelContext) }
                catch { showingDeleteError = true }
                assessmentToDelete = nil
            }
            Button("Annulla", role: .cancel) { assessmentToDelete = nil }
        } message: { assessment in
            Text("La valutazione MADRS del \(dateText(assessment.date)) verrà eliminata definitivamente.")
        }
    }

    private func latestScoreCard(_ assessment: MADRSAssessment, record: PsychometricTrendRecord, configuration: PsychometricTrendConfiguration) -> some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
            PsychometricLatestScore(record: record, configuration: configuration)
            if !assessment.raterName.isEmpty {
                Text("Valutatore: \(assessment.raterName)").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Dettagli") { detailAssessment = assessment }
            if assessment.requiresClinicalReview { MADRSClinicalReviewNotice() }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func history(for assessments: [MADRSAssessment]) -> some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
            Text("Storico valutazioni").font(.subheadline.weight(.medium))
            ForEach(assessments) { assessment in
                HStack(spacing: ClinicalSpacing.m) {
                    Text(dateText(assessment.date)).frame(width: 120, alignment: .leading)
                    if let score = assessment.totalScore, let severity = assessment.severity {
                        Text("\(score) / 60").monospacedDigit()
                        Text(severity.label).foregroundStyle(severity.color)
                    } else {
                        Text("Non valida").foregroundStyle(.secondary)
                    }
                    if assessment.requiresClinicalReview {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            .help("Approfondire clinicamente l’item 10")
                    }
                    Spacer()
                    AssessmentDateEditButton(assessment: assessment, scaleLabel: "MADRS")
                    Button("Dettagli") { detailAssessment = assessment }
                    Button { assessmentToDelete = assessment } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Elimina valutazione MADRS del \(dateText(assessment.date))")
                }
                .padding(ClinicalSpacing.s)
                Divider()
            }
        }
    }

    private func saveAssessment(date: Date, scores: [Int], raterName: String) -> String? {
        guard MADRS.totalScore(for: scores) != nil else { return "Valuta tutti i 10 item con un punteggio da 0 a 6." }
        let previousUpdatedAt = patient.updatedAt
        let assessment = MADRSAssessment(date: date, scores: scores, raterName: raterName, patient: patient)
        modelContext.insert(assessment)
        patient.madrsAssessments.append(assessment)
        patient.updatedAt = .now
        do {
            try modelContext.save()
            isPresentingNewAssessment = false
            return nil
        } catch {
            patient.madrsAssessments.removeAll { $0.id == assessment.id }
            modelContext.delete(assessment)
            patient.updatedAt = previousUpdatedAt
            return "La valutazione non è stata salvata. I punteggi rimangono nella scheda: riprova."
        }
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT")))
    }
}
