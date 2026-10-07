import SwiftUI
import SwiftData

struct PatientClinicalWindowView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var patient: Patient
    @State private var therapyDraft: [TherapyDraftItem] = []
    @State private var pendingTherapyMedicationFocusID: UUID?
    @State private var hasUnsavedClinicalDrafts = false
    @State private var hasUnsavedBloodTestsDrafts = false
    @State private var openingClinicalAlerts: [ClinicalAlert] = []
    @State private var isPresentingQuickCapture = false
    @State private var quickCaptureText = ""
    @State private var quickCaptureWellbeing = 5
    @State private var quickCaptureDate = Date()
    @State private var lastSaveFeedback: ClinicalSaveFeedback?
    @State private var clinicalSaveError: String?

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

    private func hydrateLegacyAnamnesisIfNeeded() {
        let legacy = patient.medicalHistory.trimmingCharacters(in: .whitespacesAndNewlines)
        let comorb = (patient.medicalComorbidities ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let psych = (patient.remotePsychiatricHistory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !legacy.isEmpty, comorb.isEmpty, psych.isEmpty,
              patient.encryptedMedicalComorbidities == nil,
              patient.encryptedRemotePsychiatricHistory == nil else { return }
        if !patient.protectMedicalComorbidities(legacy) {
            clinicalSaveError = "Non è stato possibile proteggere l’anamnesi precedente. Il testo originale è stato conservato."
        }
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

    private func refreshOpeningClinicalAlerts() {
        openingClinicalAlerts = ClinicalAlertService.shared.alertsForPatientOpening(patient)
    }

    private func registerSaveFeedback(area: String) {
        lastSaveFeedback = ClinicalSaveFeedback(area: area, timestamp: .now)
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

    private func appendAutomaticClinicalNote(content: String) throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let note = ClinicalNote(
            content: "",
            wellbeingScore: 0
        )
        guard note.protectContent(trimmed) else { throw SecureDataCipherError.keyCreationFailed }
        note.patient = patient
        modelContext.insert(note)
        patient.clinicalNotes.append(note)
    }

    private func addTherapyMedicationRow() {
        let newItem = TherapyDraftItem(
            id: UUID(),
            sourceID: nil,
            medicationName: "",
            dosage: "",
            posology: ""
        )
        therapyDraft.append(newItem)
        pendingTherapyMedicationFocusID = newItem.id
    }

    private func isNotificationForThisPatient(_ notification: Notification) -> Bool {
        guard
            let userInfo = notification.userInfo,
            let patientIDRaw = userInfo["patientID"] as? String,
            let patientID = UUID(uuidString: patientIDRaw)
        else {
            return false
        }
        return patientID == patient.id
    }

    private func saveTherapyDraft() {
        guard hasUnsavedTherapyChanges else { return }

        do {
            try ClinicalPersistence.perform(in: modelContext) {
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

                try appendAutomaticClinicalNote(content: therapyChangeNoteText(from: updatedTherapyItems))
            }
        } catch {
            clinicalSaveError = "La terapia non è stata salvata. La bozza è ancora disponibile: riprova."
            return
        }
        registerSaveFeedback(area: "Terapia")

        loadTherapyDraft()
        refreshOpeningClinicalAlerts()
    }

    private func openQuickClinicalCapture() {
        quickCaptureText = ""
        quickCaptureWellbeing = 5
        quickCaptureDate = .now
        isPresentingQuickCapture = true
    }

    private func saveQuickClinicalCapture() {
        let trimmed = quickCaptureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let note = ClinicalNote(
            content: "",
            wellbeingScore: quickCaptureWellbeing,
            createdAt: quickCaptureDate,
            updatedAt: quickCaptureDate
        )
        guard note.protectContent(trimmed) else {
            clinicalSaveError = "La protezione della nota non è disponibile. Riprova il salvataggio."
            return
        }
        let originalUpdatedAt = patient.updatedAt
        note.patient = patient
        modelContext.insert(note)
        patient.clinicalNotes.append(note)
        patient.updatedAt = .now
        do {
            try modelContext.save()
            registerSaveFeedback(area: "Nota clinica")
            isPresentingQuickCapture = false
        } catch {
            patient.clinicalNotes.removeAll { $0.id == note.id }
            modelContext.delete(note)
            patient.updatedAt = originalUpdatedAt
            clinicalSaveError = "La bozza è ancora disponibile. Riprova il salvataggio. " + error.localizedDescription
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClinicalSpacing.l) {
                // Header: patient identity + organ indicators on the same row
                VStack(alignment: .leading, spacing: ClinicalSpacing.m) {
                    HStack(alignment: .center, spacing: ClinicalSpacing.l) {
                        VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
                            Text(patient.fullName)
                                .font(.largeTitle)
                                .fontWeight(.semibold)

                            if !patient.readablePrimaryDiagnosis.isEmpty {
                                Label(patient.readablePrimaryDiagnosis, systemImage: "cross.case")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)

                        OrganFunctionsSummaryView(
                            heartStatus: heartStatusBinding,
                            liverStatus: liverStatusBinding,
                            kidneyStatus: kidneyStatusBinding
                        ) {
                            patient.updatedAt = .now
                        }
                    }

                    if !openingClinicalAlerts.isEmpty {
                        ClinicalAlertsPanelView(alerts: openingClinicalAlerts)
                    }

                    if let lastSaveFeedback {
                        ClinicalSaveFeedbackBanner(feedback: lastSaveFeedback)
                    }
                }

                PatientClinicalDataSectionView(patient: patient)

                PatientTherapySectionView(
                    therapyDraft: $therapyDraft,
                    pendingTherapyMedicationFocusID: pendingTherapyMedicationFocusID,
                    hasUnsavedTherapyChanges: hasUnsavedTherapyChanges,
                    onMedicationAutofocused: { rowID in
                        if pendingTherapyMedicationFocusID == rowID {
                            pendingTherapyMedicationFocusID = nil
                        }
                    },
                    onDeleteRow: { rowID in
                        therapyDraft.removeAll { $0.id == rowID }
                    },
                    onAddRow: {
                        addTherapyMedicationRow()
                    },
                    onSave: {
                        saveTherapyDraft()
                    }
                )

                ClinicalUpdatesSectionView(
                    patient: patient,
                    onDraftStateChange: { hasUnsavedDrafts in
                        hasUnsavedClinicalDrafts = hasUnsavedDrafts
                        updateUnsavedWindowState()
                    },
                    onSaved: {
                        registerSaveFeedback(area: "Nota clinica")
                    }
                )

                BloodTestsSectionView(
                    patient: patient,
                    onDraftStateChange: { hasUnsavedDrafts in
                        hasUnsavedBloodTestsDrafts = hasUnsavedDrafts
                        updateUnsavedWindowState()
                    },
                    onSaved: {
                        registerSaveFeedback(area: "Esami ematochimici")
                        refreshOpeningClinicalAlerts()
                    }
                )

                PsychometricScalesSectionView(patient: patient)
            }
            .padding(ClinicalSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Salvataggio non riuscito", isPresented: Binding(
            get: { clinicalSaveError != nil }, set: { if !$0 { clinicalSaveError = nil } }
        )) {
            Button("OK", role: .cancel) { clinicalSaveError = nil }
        } message: { Text(clinicalSaveError ?? "") }
        .onAppear {
            hydrateLegacyAnamnesisIfNeeded()
            if patient.heartFunctionStatus == nil { patient.heartFunctionStatus = "green" }
            if patient.liverFunctionStatus == nil { patient.liverFunctionStatus = "green" }
            if patient.kidneyFunctionStatus == nil { patient.kidneyFunctionStatus = "green" }
            refreshOpeningClinicalAlerts()
            loadTherapyDraft()
            updateUnsavedWindowState()
        }
        .onChange(of: patient.id) { _, _ in
            refreshOpeningClinicalAlerts()
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
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteAddTherapyMedicationRequested)) { notification in
            guard AppLockViewModel.shared.permitsClinicalAccess, isNotificationForThisPatient(notification) else { return }
            addTherapyMedicationRow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteSaveTherapyRequested)) { notification in
            guard AppLockViewModel.shared.permitsClinicalAccess, isNotificationForThisPatient(notification) else { return }
            saveTherapyDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickClinicalCaptureRequested)) { notification in
            guard AppLockViewModel.shared.permitsClinicalAccess, isNotificationForThisPatient(notification) else { return }
            openQuickClinicalCapture()
        }
        .sheet(isPresented: $isPresentingQuickCapture) {
            AppLockGateView {
                QuickClinicalCaptureSheet(
                    patientFullName: patient.fullName,
                    quickCaptureText: $quickCaptureText,
                    quickCaptureDate: $quickCaptureDate,
                    quickCaptureWellbeing: $quickCaptureWellbeing,
                    onCancel: {
                        isPresentingQuickCapture = false
                    },
                    onSave: {
                        saveQuickClinicalCapture()
                    }
                )
            }
        }
    }
}
