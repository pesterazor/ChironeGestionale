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
    private enum FocusField: Hashable {
        case medication
        case dosage
    }

    @Binding var item: TherapyDraftItem
    let shouldAutoFocusMedication: Bool
    let onMedicationAutofocused: () -> Void
    let onDelete: () -> Void
    @State private var medicationSuggestions: [String] = []
    @State private var dosageSuggestions: [String] = []
    @FocusState private var focusedField: FocusField?

    private var shouldShowMedicationSuggestions: Bool {
        focusedField == .medication &&
        item.medicationName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        !medicationSuggestions.isEmpty
    }

    private var shouldShowDosageSuggestions: Bool {
        focusedField == .dosage &&
        !dosageSuggestions.isEmpty
    }

    private func refreshMedicationSuggestions() {
        medicationSuggestions = ActiveIngredientAutocomplete.shared.suggestions(for: item.medicationName)
    }

    private func refreshDosageSuggestions() {
        dosageSuggestions = ActiveIngredientAutocomplete.shared.formulationSuggestions(
            for: item.medicationName,
            formulationQuery: item.dosage
        )
    }

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

    private func triggerAutoFocusIfNeeded() {
        guard shouldAutoFocusMedication else { return }
        DispatchQueue.main.async {
            focusedField = .medication
            onMedicationAutofocused()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Farmaco", text: $item.medicationName)
                        .focused($focusedField, equals: .medication)
                        .onChange(of: item.medicationName) { _, _ in
                            refreshMedicationSuggestions()
                            if focusedField == .dosage {
                                refreshDosageSuggestions()
                            }
                        }
                        .onChange(of: focusedField) { _, field in
                            if field == .medication {
                                refreshMedicationSuggestions()
                            } else if field != .dosage {
                                medicationSuggestions = []
                            }

                            if field == .dosage {
                                refreshDosageSuggestions()
                            } else if field != .medication {
                                dosageSuggestions = []
                            }
                        }
                        .onSubmit {
                            medicationSuggestions = []
                        }

                    if shouldShowMedicationSuggestions {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(medicationSuggestions, id: \.self) { suggestion in
                                    Button {
                                        item.medicationName = suggestion
                                        medicationSuggestions = []
                                        focusedField = .dosage
                                        refreshDosageSuggestions()
                                    } label: {
                                        Text(suggestion)
                                            .font(.caption)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .frame(maxHeight: 140)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Dosaggio", text: $item.dosage)
                        .focused($focusedField, equals: .dosage)
                        .onChange(of: item.dosage) { _, _ in
                            refreshDosageSuggestions()
                        }
                        .onSubmit {
                            dosageSuggestions = []
                        }

                    if shouldShowDosageSuggestions {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(dosageSuggestions, id: \.self) { suggestion in
                                    Button {
                                        item.dosage = suggestion
                                        dosageSuggestions = []
                                    } label: {
                                        Text(suggestion)
                                            .font(.caption)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .frame(maxHeight: 140)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }
                TextField("Posologia", text: $item.posology)

                actionIconButton(symbol: "trash", isDestructive: true, action: onDelete)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(10)
        .onAppear(perform: triggerAutoFocusIfNeeded)
        .onChange(of: shouldAutoFocusMedication) { _, _ in
            triggerAutoFocusIfNeeded()
        }
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
    @State private var pendingTherapyMedicationFocusID: UUID?
    @State private var hasUnsavedClinicalDrafts = false
    @State private var hasUnsavedBloodTestsDrafts = false

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

    private var hasUnsavedChangesInWindow: Bool {
        hasUnsavedTherapyChanges || hasUnsavedClinicalDrafts || hasUnsavedBloodTestsDrafts
    }

    private func updateUnsavedWindowState() {
        PatientWindowUnsavedStateStore.shared.set(hasUnsavedChangesInWindow, for: patient.id)
    }

    private func loadTherapyDraft() {
        therapyDraft = persistedRows
        pendingTherapyMedicationFocusID = nil
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

    private func appendAutomaticClinicalNote(content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let note = ClinicalNote(
            content: "",
            wellbeingScore: 0,
            patient: patient
        )
        note.protectContent(trimmed)
        modelContext.insert(note)
        patient.clinicalNotes.append(note)
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

        appendAutomaticClinicalNote(content: therapyChangeNoteText(from: updatedTherapyItems))

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

                        if !patient.readablePrimaryDiagnosis.isEmpty {
                            Label(patient.readablePrimaryDiagnosis, systemImage: "cross.case")
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
                                TextField(
                                    "",
                                    text: Binding(
                                        get: { patient.readablePrimaryDiagnosis },
                                        set: { patient.protectPrimaryDiagnosis($0) }
                                    ),
                                    prompt: Text("Diagnosi principale")
                                )
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                clinicalTitle("Diagnosi secondaria")
                                TextField(
                                    "",
                                    text: Binding(
                                        get: { patient.readableSecondaryDiagnosis },
                                        set: { patient.protectSecondaryDiagnosis($0) }
                                    ),
                                    prompt: Text("Diagnosi secondaria")
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                clinicalTitle("Allergie")
                                TextField(
                                    "",
                                    text: Binding(
                                        get: { patient.readableAllergies },
                                        set: { patient.protectAllergies($0) }
                                    ),
                                    prompt: Text("Allergie")
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            clinicalTitle("Comorbidità mediche")
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .textBackgroundColor))

                                TextEditor(text: Binding(
                                    get: { patient.readableMedicalComorbidities },
                                    set: { patient.protectMedicalComorbidities($0) }
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
                                    get: { patient.readableRemotePsychiatricHistory },
                                    set: { patient.protectRemotePsychiatricHistory($0) }
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
                    .onChange(of: patient.encryptedPrimaryDiagnosis) { _, _ in patient.updatedAt = .now }
                    .onChange(of: patient.encryptedSecondaryDiagnosis) { _, _ in patient.updatedAt = .now }
                    .onChange(of: patient.encryptedAllergies) { _, _ in patient.updatedAt = .now }
                    .onChange(of: patient.encryptedMedicalComorbidities) { _, _ in patient.updatedAt = .now }
                    .onChange(of: patient.encryptedRemotePsychiatricHistory) { _, _ in patient.updatedAt = .now }
                }

                GroupBox("Terapia attuale") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($therapyDraft) { $item in
                            TherapyMedicationRow(
                                item: $item,
                                shouldAutoFocusMedication: pendingTherapyMedicationFocusID == item.id,
                                onMedicationAutofocused: {
                                    if pendingTherapyMedicationFocusID == item.id {
                                        pendingTherapyMedicationFocusID = nil
                                    }
                                }
                            ) {
                                therapyDraft.removeAll { $0.id == item.id }
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                let newItem = TherapyDraftItem(
                                    id: UUID(),
                                    sourceID: nil,
                                    medicationName: "",
                                    dosage: "",
                                    posology: ""
                                )
                                therapyDraft.append(newItem)
                                pendingTherapyMedicationFocusID = newItem.id
                            } label: {
                                Label("Aggiungi farmaco", systemImage: "plus")
                            }
                            .accessibilityIdentifier("therapy_add_medication_button")
                            .keyboardShortcut("n", modifiers: [.command, .option])

                            Button("Salva terapia") {
                                saveTherapyDraft()
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("therapy_save_button")
                            .keyboardShortcut("t", modifiers: [.command, .option])
                            .disabled(!hasUnsavedTherapyChanges)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ClinicalUpdatesSectionView(patient: patient) { hasUnsavedDrafts in
                    hasUnsavedClinicalDrafts = hasUnsavedDrafts
                    updateUnsavedWindowState()
                }

                BloodTestsSectionView(
                    patient: patient,
                    onDraftStateChange: { hasUnsavedDrafts in
                        hasUnsavedBloodTestsDrafts = hasUnsavedDrafts
                        updateUnsavedWindowState()
                    },
                    onAutoClinicalUpdate: { noteText in
                        appendAutomaticClinicalNote(content: noteText)
                    }
                )
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
            updateUnsavedWindowState()
        }
        .onChange(of: patient.id) { _, _ in
            loadTherapyDraft()
            hasUnsavedClinicalDrafts = false
            hasUnsavedBloodTestsDrafts = false
            updateUnsavedWindowState()
        }
        .onChange(of: hasUnsavedTherapyChanges) { _, _ in
            updateUnsavedWindowState()
        }
        .onChange(of: hasUnsavedClinicalDrafts) { _, _ in
            updateUnsavedWindowState()
        }
        .onChange(of: hasUnsavedBloodTestsDrafts) { _, _ in
            updateUnsavedWindowState()
        }
        .onDisappear {
            PatientWindowUnsavedStateStore.shared.clear(for: patient.id)
        }
    }
}
