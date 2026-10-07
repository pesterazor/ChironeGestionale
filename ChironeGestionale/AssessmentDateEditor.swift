import SwiftData
import SwiftUI

protocol DatedPsychometricAssessment: PersistentModel {
    var id: UUID { get }
    var date: Date { get set }
    var createdAt: Date { get }
    var patient: Patient? { get }
}

extension PHQ9Assessment: DatedPsychometricAssessment {}
extension GAD7Assessment: DatedPsychometricAssessment {}
extension MDQAssessment: DatedPsychometricAssessment {}
extension BeckAssessment: DatedPsychometricAssessment {}
extension MADRSAssessment: DatedPsychometricAssessment {}

enum AssessmentDateEditing {
    enum ValidationError: Error { case invalidDate }

    static func update<T: DatedPsychometricAssessment>(
        _ assessment: T, to date: Date, save: () throws -> Void
    ) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw ValidationError.invalidDate }
        let originalDate = assessment.date
        let originalUpdatedAt = assessment.patient?.updatedAt
        assessment.date = date
        assessment.patient?.updatedAt = .now
        do {
            try save()
        } catch {
            assessment.date = originalDate
            if let originalUpdatedAt { assessment.patient?.updatedAt = originalUpdatedAt }
            throw error
        }
    }

    static func sorted<T: DatedPsychometricAssessment>(_ assessments: [T]) -> [T] {
        assessments.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString > $1.id.uuidString
        }
    }
}

enum AssessmentDeletion {
    static func delete<T: DatedPsychometricAssessment>(
        _ assessment: T, in context: ModelContext, save: (() throws -> Void)? = nil
    ) throws {
        try ClinicalPersistence.perform(in: context, changes: {
            assessment.patient?.updatedAt = .now
            context.delete(assessment)
        }, save: save)
    }
}

struct AssessmentDateEditButton<T: DatedPsychometricAssessment>: View {
    @Environment(\.modelContext) private var modelContext
    let assessment: T
    let scaleLabel: String
    @State private var isPresented = false

    var body: some View {
        Button("Modifica data", systemImage: "calendar") { isPresented = true }
            .help("Modifica la data di somministrazione della valutazione \(scaleLabel)")
            .accessibilityIdentifier("assessment_date_edit_\(scaleLabel)_\(assessment.id)")
            .sheet(isPresented: $isPresented) {
                AppLockGateView {
                    AssessmentDateEditorSheet(
                        scaleLabel: scaleLabel,
                        patientName: assessment.patient?.fullName ?? "",
                        date: assessment.date,
                        onSave: { date in
                            try AssessmentDateEditing.update(assessment, to: date) {
                                try modelContext.save()
                            }
                            isPresented = false
                        },
                        onCancel: { isPresented = false }
                    )
                }
            }
    }
}

struct AssessmentDateEditorSheet: View {
    let scaleLabel: String
    let patientName: String
    let originalDate: Date
    let onSave: (Date) throws -> Void
    let onCancel: () -> Void
    @State private var selectedDate: Date
    @State private var showingSaveError = false

    init(scaleLabel: String, patientName: String, date: Date, onSave: @escaping (Date) throws -> Void, onCancel: @escaping () -> Void) {
        self.scaleLabel = scaleLabel
        self.patientName = patientName
        self.originalDate = date
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedDate = State(initialValue: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.l) {
            VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
                Text("Modifica data · \(scaleLabel)").font(.title2.weight(.semibold))
                if !patientName.isEmpty {
                    Text(patientName).foregroundStyle(.secondary)
                }
            }
            DatePicker("Data somministrazione", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.field)
                .accessibilityIdentifier("assessment_date_picker")
            HStack {
                Spacer()
                Button("Annulla", action: onCancel).keyboardShortcut(.escape)
                Button("Salva data") {
                    do { try onSave(selectedDate) }
                    catch { showingSaveError = true }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(Calendar.current.isDate(selectedDate, inSameDayAs: originalDate))
                .accessibilityIdentifier("assessment_date_save")
            }
        }
        .padding(ClinicalSpacing.l)
        .frame(width: 420)
        .alert("Data non salvata", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Non è stato possibile salvare la nuova data. Riprova; la valutazione conserva la data precedente.")
        }
    }
}
