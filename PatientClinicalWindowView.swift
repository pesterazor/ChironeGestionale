import SwiftUI
import SwiftData

private struct TherapyDraftItem: Identifiable, Equatable {
    let id: UUID
    let sourceID: UUID?
    var medicationName: String
    var dosage: String
    var posology: String
}

private struct NormalizedTherapyRow: Equatable {
    let sourceID: UUID?
    let medicationName: String
    let dosage: String
    let posology: String
}

private enum OrganFunctionStatus: String {
    case green
    case yellow
    case red

    var color: Color {
        switch self {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    var next: OrganFunctionStatus {
        switch self {
        case .green: return .yellow
        case .yellow: return .red
        case .red: return .green
        }
    }

    static func from(_ rawValue: String) -> OrganFunctionStatus {
        OrganFunctionStatus(rawValue: rawValue.lowercased()) ?? .green
    }
}

private struct OrganFunctionIndicatorView: View {
    let title: String
    @Binding var status: String
    let onChange: () -> Void

    private var resolvedStatus: OrganFunctionStatus {
        OrganFunctionStatus.from(status)
    }

    var body: some View {
        Button {
            status = resolvedStatus.next.rawValue
            onChange()
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(resolvedStatus.color)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .strokeBorder(resolvedStatus.color.opacity(0.35), lineWidth: 1)
                    )
                    .accessibilityHidden(true)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44)
        }
        .buttonStyle(.plain)
    }
}

private struct OrganFunctionsSummaryView: View {
    @Binding var heartStatus: String
    @Binding var liverStatus: String
    @Binding var kidneyStatus: String
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            OrganFunctionIndicatorView(title: "Cuore", status: $heartStatus, onChange: onChange)
            OrganFunctionIndicatorView(title: "Fegato", status: $liverStatus, onChange: onChange)
            OrganFunctionIndicatorView(title: "Reni", status: $kidneyStatus, onChange: onChange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.15))
        )
    }
}

private struct TherapyMedicationRow: View {
    @Binding var item: TherapyDraftItem
    let onDelete: () -> Void

    @ViewBuilder
    private func actionIconButton(symbol: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(isDestructive ? Color.red : Color.primary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.secondary.opacity(0.25))
                )
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack {
            TextField("Farmaco", text: $item.medicationName)
            TextField("Dosaggio", text: $item.dosage)
            TextField("Posologia", text: $item.posology)

            actionIconButton(symbol: "trash", isDestructive: true, action: onDelete)
        }
        .textFieldStyle(.roundedBorder)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct PatientClinicalWindowView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var patient: Patient
    @State private var therapyDraft: [TherapyDraftItem] = []

    private var heartStatusBinding: Binding<String> {
        Binding(
            get: { patient.heartFunctionStatus ?? "green" },
            set: { patient.heartFunctionStatus = $0 }
        )
    }

    private var liverStatusBinding: Binding<String> {
        Binding(
            get: { patient.liverFunctionStatus ?? "green" },
            set: { patient.liverFunctionStatus = $0 }
        )
    }

    private var kidneyStatusBinding: Binding<String> {
        Binding(
            get: { patient.kidneyFunctionStatus ?? "green" },
            set: { patient.kidneyFunctionStatus = $0 }
        )
    }

    private func clinicalTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func hydrateLegacyAnamnesisIfNeeded() {
        let legacy = patient.medicalHistory.trimmingCharacters(in: .whitespacesAndNewlines)
        let comorb = (patient.medicalComorbidities ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let psych = (patient.remotePsychiatricHistory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !legacy.isEmpty, comorb.isEmpty, psych.isEmpty else { return }
        patient.medicalComorbidities = legacy
    }

    private func draftItem(from item: TherapyMedication) -> TherapyDraftItem {
        TherapyDraftItem(
            id: item.id,
            sourceID: item.id,
            medicationName: item.medicationName,
            dosage: item.dosage,
            posology: item.posology
        )
    }

    private func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedRows(from rows: [TherapyDraftItem]) -> [NormalizedTherapyRow] {
        rows
            .map { row in
                NormalizedTherapyRow(
                    sourceID: row.sourceID,
                    medicationName: trim(row.medicationName),
                    dosage: trim(row.dosage),
                    posology: trim(row.posology)
                )
            }
            .filter { row in
                !(row.medicationName.isEmpty && row.dosage.isEmpty && row.posology.isEmpty)
            }
    }

    private var persistedRows: [TherapyDraftItem] {
        patient.therapyItems.map(draftItem)
    }

    private var hasUnsavedTherapyChanges: Bool {
        normalizedRows(from: therapyDraft) != normalizedRows(from: persistedRows)
    }

    private func loadTherapyDraft() {
        therapyDraft = persistedRows
    }

    private func formatTherapyLine(name: String, dosage: String, posology: String) -> String {
        let core = [name, dosage]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !posology.isEmpty else {
            return core
        }

        if core.isEmpty {
            return posology
        }

        return "\(core) - \(posology)"
    }

    private func therapySummaryText(from medications: [TherapyMedication]) -> String {
        let lines = medications.compactMap { item -> String? in
            let name = trim(item.medicationName)
            let dosage = trim(item.dosage)
            let posology = trim(item.posology)
            guard !name.isEmpty || !dosage.isEmpty || !posology.isEmpty else { return nil }

            return formatTherapyLine(name: name, dosage: dosage, posology: posology)
        }

        return lines.joined(separator: "; ")
    }

    private func therapyChangeNoteText(from medications: [TherapyMedication]) -> String {
        let summary = therapySummaryText(from: medications)
        if summary.isEmpty {
            return "Aggiornamento terapia farmacologica: nessuna terapia attiva."
        }

        let bulletList = medications.compactMap { item -> String? in
            let name = trim(item.medicationName)
            let dosage = trim(item.dosage)
            let posology = trim(item.posology)
            guard !name.isEmpty || !dosage.isEmpty || !posology.isEmpty else { return nil }

            return "- " + formatTherapyLine(name: name, dosage: dosage, posology: posology)
        }
        .joined(separator: "\n")

        return "Aggiornamento terapia farmacologica:\n\(bulletList)"
    }

    private func saveTherapyDraft() {
        guard hasUnsavedTherapyChanges else { return }

        let cleanedDraft = therapyDraft.filter {
            let medication = trim($0.medicationName)
            let dosage = trim($0.dosage)
            let posology = trim($0.posology)
            return !(medication.isEmpty && dosage.isEmpty && posology.isEmpty)
        }

        let existingByID = Dictionary(uniqueKeysWithValues: patient.therapyItems.map { ($0.id, $0) })
        let keptIDs = Set(cleanedDraft.compactMap(\.sourceID))

        for existing in patient.therapyItems where !keptIDs.contains(existing.id) {
            modelContext.delete(existing)
        }

        var updatedTherapyItems: [TherapyMedication] = []
        for draft in cleanedDraft {
            let medication = trim(draft.medicationName)
            let dosage = trim(draft.dosage)
            let posology = trim(draft.posology)

            if let sourceID = draft.sourceID, let existing = existingByID[sourceID] {
                existing.medicationName = medication
                existing.dosage = dosage
                existing.posology = posology
                existing.isActive = true
                existing.updatedAt = .now
                updatedTherapyItems.append(existing)
            } else {
                let newItem = TherapyMedication(
                    medicationName: medication,
                    dosage: dosage,
                    posology: posology,
                    isActive: true,
                    patient: patient
                )
                modelContext.insert(newItem)
                updatedTherapyItems.append(newItem)
            }
        }

        patient.therapyItems = updatedTherapyItems
        patient.currentTherapySummary = therapySummaryText(from: updatedTherapyItems)
        patient.updatedAt = .now

        let therapyNote = ClinicalNote(
            content: therapyChangeNoteText(from: updatedTherapyItems),
            wellbeingScore: 0,
            patient: patient
        )
        modelContext.insert(therapyNote)
        patient.clinicalNotes.append(therapyNote)

        loadTherapyDraft()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(patient.fullName)
                            .font(.largeTitle)
                            .fontWeight(.semibold)

                        if !patient.primaryDiagnosis.isEmpty {
                            Label(patient.primaryDiagnosis, systemImage: "cross.case")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 12)

                    OrganFunctionsSummaryView(
                        heartStatus: heartStatusBinding,
                        liverStatus: liverStatusBinding,
                        kidneyStatus: kidneyStatusBinding
                    ) {
                        patient.updatedAt = .now
                    }
                }

                GroupBox("Dati clinici") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                clinicalTitle("Diagnosi principale")
                                TextField("", text: $patient.primaryDiagnosis, prompt: Text("Diagnosi principale"))
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                clinicalTitle("Diagnosi secondaria")
                                TextField("", text: $patient.secondaryDiagnosis, prompt: Text("Diagnosi secondaria"))
                            }
                            .frame(maxWidth: .infinity)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                clinicalTitle("Allergie")
                                TextField("", text: $patient.allergies, prompt: Text("Allergie"))
                            }
                            .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            clinicalTitle("Comorbidità mediche")
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .textBackgroundColor))

                                TextEditor(text: Binding(
                                    get: { patient.medicalComorbidities ?? "" },
                                    set: { patient.medicalComorbidities = $0.isEmpty ? nil : $0 }
                                ))
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 6)
                            }
                            .frame(minHeight: 110)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.secondary.opacity(0.25))
                            )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            clinicalTitle("Anamnesi psichiatrica remota")
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .textBackgroundColor))

                                TextEditor(text: Binding(
                                    get: { patient.remotePsychiatricHistory ?? "" },
                                    set: { patient.remotePsychiatricHistory = $0.isEmpty ? nil : $0 }
                                ))
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 6)
                            }
                            .frame(minHeight: 110)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.secondary.opacity(0.25))
                            )
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: patient.primaryDiagnosis) { _, _ in patient.updatedAt = .now }
                    .onChange(of: patient.secondaryDiagnosis) { _, _ in patient.updatedAt = .now }
                    .onChange(of: patient.allergies) { _, _ in patient.updatedAt = .now }
                    .onChange(of: patient.medicalComorbidities) { _, _ in patient.updatedAt = .now }
                    .onChange(of: patient.remotePsychiatricHistory) { _, _ in patient.updatedAt = .now }
                }

                GroupBox("Terapia attuale") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($therapyDraft) { $item in
                            TherapyMedicationRow(item: $item) {
                                therapyDraft.removeAll { $0.id == item.id }
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                therapyDraft.append(
                                    TherapyDraftItem(
                                        id: UUID(),
                                        sourceID: nil,
                                        medicationName: "",
                                        dosage: "",
                                        posology: ""
                                    )
                                )
                            } label: {
                                Label("Aggiungi farmaco", systemImage: "plus")
                            }

                            Button("Salva terapia") {
                                saveTherapyDraft()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!hasUnsavedTherapyChanges)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ClinicalUpdatesSectionView(patient: patient)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            hydrateLegacyAnamnesisIfNeeded()
            if patient.heartFunctionStatus == nil { patient.heartFunctionStatus = "green" }
            if patient.liverFunctionStatus == nil { patient.liverFunctionStatus = "green" }
            if patient.kidneyFunctionStatus == nil { patient.kidneyFunctionStatus = "green" }
            loadTherapyDraft()
        }
        .onChange(of: patient.id) { _, _ in
            loadTherapyDraft()
        }
    }
}
