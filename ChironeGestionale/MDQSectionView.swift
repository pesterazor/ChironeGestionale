import SwiftUI
import SwiftData

struct MDQScaleContent: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var patient: Patient
    @State private var isPresentingNewAssessment = false
    @State private var showingDeleteError = false

    private var sortedAssessments: [MDQAssessment] {
        AssessmentDateEditing.sorted(patient.mdqAssessments)
    }

    var body: some View {
        let sortedAssessments = self.sortedAssessments
        let records = sortedAssessments.map { PsychometricTrendRecord($0) }
        let configuration = PsychometricTrendConfiguration.mdq
        let trend = PsychometricTrendData(newestFirst: records, maximum: configuration.maximum)
        return Group {
            if sortedAssessments.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: ClinicalSpacing.m) {
                    if let latest = sortedAssessments.first {
                        PsychometricTrendView(data: trend, configuration: configuration) {
                            latestScoreCard(latest, record: records[0], configuration: configuration)
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
                MDQAssessmentSheet(
                    patientFullName: patient.fullName,
                    onSave: { date, part1, part2, part3 in
                        guard PsychometricResponseValidation.isCompleteMDQ(part1: part1, part2: part2 ? 1 : 0, part3: part3) else { return "Completa tutte le risposte prima di salvare." }
                        let previousUpdatedAt = patient.updatedAt
                        let assessment = MDQAssessment(
                            date: date,
                            part1Answers: part1,
                            part2Answer: part2,
                            part3RawValue: part3,
                            patient: patient
                        )
                        modelContext.insert(assessment)
                        patient.mdqAssessments.append(assessment)
                        patient.updatedAt = .now
                        do {
                            try modelContext.save()
                            isPresentingNewAssessment = false
                            return nil
                        } catch {
                            patient.mdqAssessments.removeAll { $0.id == assessment.id }
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

private extension MDQScaleContent {
    var emptyState: some View {
        VStack(spacing: ClinicalSpacing.m) {
            Image(systemName: "moon.stars")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            VStack(spacing: ClinicalSpacing.xs) {
                Text("Nessuna valutazione MDQ registrata")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Il Mood Disorder Questionnaire (MDQ) è uno strumento di screening per i disturbi bipolari, basato su 13 sintomi e tre criteri diagnostici.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            Button("Nuova valutazione") {
                isPresentingNewAssessment = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ClinicalSpacing.l)
    }

    private func latestScoreCard(_ assessment: MDQAssessment, record: PsychometricTrendRecord, configuration: PsychometricTrendConfiguration) -> some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
            PsychometricLatestScore(record: record, configuration: configuration)
            if record.score != nil {
                MDQResultBadge(isPositive: assessment.isScreenPositive)
                criterionRow("A", met: assessment.criterionA, detail: "≥7 sintomi (\(assessment.part1YesCount)/13)")
                criterionRow("B", met: assessment.criterionB, detail: "sintomi in co-occorrenza")
                criterionRow("C", met: assessment.criterionC, detail: "impatto \(assessment.impact.label.lowercased())")
            } else {
                Text("Screening e criteri non valutabili").font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    func criterionRow(_ label: String, met: Bool, detail: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? .green : Color.secondary.opacity(0.4))
                .font(.caption)
            Text("Criterio \(label): \(detail)")
                .font(.caption)
                .foregroundStyle(met ? .primary : .secondary)
        }
    }

    func historyTable(for assessments: [MDQAssessment]) -> some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
            Text("Storico valutazioni")
                .font(.subheadline.weight(.medium))

            VStack(spacing: 0) {
                ForEach(Array(assessments.enumerated()), id: \.element.id) { index, assessment in
                    MDQAssessmentRow(assessment: assessment) {
                        deleteAssessment(assessment)
                    }
                    if index < assessments.count - 1 {
                        Divider().padding(.horizontal, ClinicalSpacing.m)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.12)))
        }
    }

    func deleteAssessment(_ assessment: MDQAssessment) {
        do { try AssessmentDeletion.delete(assessment, in: modelContext) }
        catch { showingDeleteError = true }
    }
}

// MARK: - Subviews

private struct MDQResultBadge: View {
    let isPositive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isPositive ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
            Text(isPositive ? "POSITIVO" : "NEGATIVO")
                .font(.caption2.weight(.bold))
                .tracking(0.4)
        }
        .foregroundStyle(isPositive ? Color.red : Color.green)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill((isPositive ? Color.red : Color.green).opacity(0.12)))
        .overlay(Capsule().strokeBorder((isPositive ? Color.red : Color.green).opacity(0.35)))
    }
}

private struct MDQAssessmentRow: View {
    let assessment: MDQAssessment
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showingDeleteAlert = false

    var body: some View {
        HStack(spacing: ClinicalSpacing.m) {
            Text(assessment.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT"))))
                .font(.body)
                .frame(width: 120, alignment: .leading)

            if let score = PsychometricTrendRecord(assessment).score {
                Text("\(score)/13 sintomi").font(.body.monospacedDigit())
                MDQResultBadge(isPositive: assessment.isScreenPositive)
            } else {
                Text("Non valida").foregroundStyle(.secondary)
            }

            Spacer()

            AssessmentDateEditButton(assessment: assessment, scaleLabel: "MDQ")

            Button {
                showingDeleteAlert = true
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Elimina valutazione")
            .accessibilityLabel("Elimina valutazione MDQ")
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

struct MDQAssessmentSheet: View {
    let patientFullName: String
    let onSave: (Date, [Int], Bool, Int) -> String?
    let onCancel: () -> Void

    @State private var part1: [Int] = Array(repeating: -1, count: 13)
    @State private var part2: Int = -1
    @State private var part3Raw: Int = -1
    @State private var saveError: String?
    @State private var assessmentDate: Date = .now

    private var part1YesCount: Int { part1.filter { $0 == 1 }.count }
    private var impact: MDQImpact { MDQImpact(rawValue: part3Raw) ?? .none }
    private var criterionA: Bool { part1YesCount >= 7 }
    private var criterionB: Bool { part2 == 1 }
    private var isComplete: Bool { PsychometricResponseValidation.isCompleteMDQ(part1: part1, part2: part2, part3: part3Raw) }
    private var criterionC: Bool { impact.meetsCriterion }
    private var isPositive: Bool { criterionA && criterionB && criterionC }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    part1Section
                    Divider().padding(.vertical, ClinicalSpacing.s)
                    part2Section
                    Divider().padding(.vertical, ClinicalSpacing.s)
                    part3Section
                }
                .padding(.bottom, ClinicalSpacing.m)
            }
            Divider()
            sheetFooter
        }
        .frame(minWidth: 760, minHeight: 580)
        .alert("Valutazione non salvata", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "Riprova a salvare la valutazione.") }
    }

    private var sheetHeader: some View {
        HStack(alignment: .center, spacing: ClinicalSpacing.l) {
            VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
                Text("Nuova valutazione MDQ")
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

    private var part1Section: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
                Text("Parte 1")
                    .font(.headline)
                Text(MDQ.part1Prefix)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, ClinicalSpacing.l)
            .padding(.top, ClinicalSpacing.m)
            .padding(.bottom, ClinicalSpacing.s)

            // Column headers
            HStack(spacing: 0) {
                Text("Sintomo").font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Text("No").font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: 60)
                Text("Sì").font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: 60)
            }
            .padding(.horizontal, ClinicalSpacing.l)
            .padding(.vertical, ClinicalSpacing.xs)
            .background(Color.primary.opacity(0.04))

            ForEach(Array(MDQ.part1Questions.enumerated()), id: \.offset) { index, question in
                MDQBinaryRow(
                    number: index + 1,
                    question: question,
                    value: $part1[index],
                    isEven: index.isMultiple(of: 2)
                )
            }

            HStack {
                Spacer()
                Text("\(part1YesCount)/13 sintomi selezionati")
                    .font(.caption)
                    .foregroundStyle(criterionA ? .green : .secondary)
                    .monospacedDigit()
                if criterionA {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            .padding(.horizontal, ClinicalSpacing.l)
            .padding(.top, ClinicalSpacing.s)
        }
    }

    private var part2Section: some View {
        HStack(alignment: .center, spacing: ClinicalSpacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Parte 2")
                    .font(.headline)
                Text(MDQ.part2Question)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Parte 2", selection: $part2) {
                Text("Da valutare").tag(-1)
                Text("No").tag(0)
                Text("Sì").tag(1)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, ClinicalSpacing.l)
        .padding(.vertical, ClinicalSpacing.s)
    }

    private var part3Section: some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
            Text("Parte 3")
                .font(.headline)
            Text(MDQ.part3Question)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Parte 3", selection: $part3Raw) {
                Text("Da valutare").tag(-1)
                ForEach(MDQImpact.allCases) { impact in
                    Text(impact.label).tag(impact.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, ClinicalSpacing.l)
        .padding(.vertical, ClinicalSpacing.s)
    }

    private var sheetFooter: some View {
        HStack(alignment: .center, spacing: ClinicalSpacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                if isComplete {
                    Text(isPositive ? "Screening POSITIVO" : "Screening NEGATIVO")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isPositive ? .red : .secondary)
                    HStack(spacing: ClinicalSpacing.m) {
                        criterionIndicator("A", met: criterionA, detail: "≥7 sintomi")
                        criterionIndicator("B", met: criterionB, detail: "co-occorrenza")
                        criterionIndicator("C", met: criterionC, detail: "impatto sig.")
                    }
                } else {
                    Text("Compilazione incompleta").font(.headline)
                    Text("Rispondi ai 13 item e completa le parti 2 e 3.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Positivo = Criteri A + B + C soddisfatti contemporaneamente")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Annulla") { onCancel() }
                .keyboardShortcut(.escape)

            Button("Salva valutazione") {
                guard isComplete else { return }
                saveError = onSave(assessmentDate, part1, part2 == 1, part3Raw)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!isComplete)
        }
        .padding(ClinicalSpacing.l)
    }

    private func criterionIndicator(_ label: String, met: Bool, detail: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? .green : Color.secondary.opacity(0.4))
                .font(.caption)
            Text("Crit. \(label): \(detail)")
                .font(.caption)
                .foregroundStyle(met ? .primary : .secondary)
        }
    }
}

private struct MDQBinaryRow: View {
    let number: Int
    let question: String
    @Binding var value: Int
    let isEven: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .top, spacing: ClinicalSpacing.s) {
                Text("\(number).")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
                Text(question)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // No button
            Button {
                value = value == 0 ? -1 : 0
            } label: {
                ZStack {
                    Circle()
                        .fill(value == 0 ? Color.secondary.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                    Circle()
                        .strokeBorder(value == 0 ? Color.secondary : Color.secondary.opacity(0.25), lineWidth: 1.5)
                    Text("No")
                        .font(.caption.weight(value == 0 ? .semibold : .regular))
                        .foregroundStyle(value == 0 ? .primary : .secondary)
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Item \(number): No")
            .accessibilityValue(value == 0 ? "Selezionato" : "Non selezionato")
            .frame(width: 60)

            // Sì button
            Button {
                value = value == 1 ? -1 : 1
            } label: {
                ZStack {
                    Circle()
                        .fill(value == 1 ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    Circle()
                        .strokeBorder(value == 1 ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1.5)
                    if value == 1 {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("Sì")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Item \(number): Sì")
            .accessibilityValue(value == 1 ? "Selezionato" : "Non selezionato")
            .frame(width: 60)
        }
        .padding(.horizontal, ClinicalSpacing.l)
        .padding(.vertical, 9)
        .background(isEven ? Color.primary.opacity(0.025) : Color.clear)
    }
}
