//
//  ContentView.swift
//  ChironeGestionale
//
//  Created by Peste on 21/04/2026.
//

import SwiftUI
import SwiftData
import AppKit
import ObjectiveC

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Patient.lastName), SortDescriptor(\Patient.firstName)]) private var patients: [Patient]

    @State private var searchText = ""
    @State private var selectedPatientID: UUID?
    @State private var showAddPatientSheet = false
    @State private var newPatientFirstName = ""
    @State private var newPatientLastName = ""
    @State private var newPatientBirthDate = Date()
    @State private var newPatientGender = ""
    @State private var newPatientPlaceOfBirth = ""
    @State private var newPatientBirthProvince = ""

    private var filteredPatients: [Patient] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmedQuery.isEmpty else {
            return patients
        }

        return patients.filter { patient in
            patient.searchableTokens.contains { token in
                token.contains(trimmedQuery)
            }
        }
    }

    private var selectedPatient: Patient? {
        guard let selectedPatientID else { return nil }
        return patients.first(where: { $0.id == selectedPatientID })
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            detailContent
        }
        .frame(minWidth: 900, minHeight: 640)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showAddPatientSheet = true
                } label: {
                    Label("Nuovo paziente", systemImage: "plus")
                }

                Button(action: openSelectedPatientWindow) {
                    Label("Apri cartella clinica", systemImage: "arrow.up.forward.app")
                }
                .disabled(selectedPatient == nil)
            }
        }
        .sheet(isPresented: $showAddPatientSheet) {
            addPatientSheet
        }
        .onAppear {
            if selectedPatientID == nil {
                selectedPatientID = patients.first?.id
            }
        }
        .onChange(of: patients.count) { _, _ in
            guard let currentSelection = selectedPatientID else {
                selectedPatientID = patients.first?.id
                return
            }

            if !patients.contains(where: { $0.id == currentSelection }) {
                selectedPatientID = patients.first?.id
            }
        }
    }

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            if filteredPatients.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Nessun paziente" : "Nessun risultato",
                    systemImage: searchText.isEmpty ? "person.crop.rectangle.stack" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Crea il primo paziente per iniziare." : "Prova a modificare i termini di ricerca.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedPatientID) {
                    ForEach(filteredPatients, id: \.id) { patient in
                        PatientRowView(patient: patient)
                            .tag(patient.id)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Apri cartella clinica") {
                                    selectedPatientID = patient.id
                                    openPatientWindow(patient)
                                }

                                Divider()

                                Button(role: .destructive) {
                                    delete(patient)
                                } label: {
                                    Label("Elimina paziente", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
                .environment(\.controlActiveState, .active)
            }

            Divider()

            HStack {
                Text("\(filteredPatients.count) pazienti")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("• filtrati")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.clear)
        }
        .searchable(
            text: $searchText,
            placement: .sidebar,
            prompt: "Cerca per nome, cognome, codice fiscale o telefono"
        )
    }

    private var detailContent: some View {
        Group {
            if let patient = selectedPatient {
                PatientSelectionSummaryView(patient: patient, openAction: {
                    openPatientWindow(patient)
                })
            } else {
                ContentUnavailableView(
                    "Nessun paziente selezionato",
                    systemImage: "person.text.rectangle",
                    description: Text("Seleziona un paziente dalla sidebar per visualizzare il riepilogo.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var canCreatePatient: Bool {
        !newPatientFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newPatientLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newPatientPlaceOfBirth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var addPatientSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nuovo paziente")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Nome *", text: $newPatientFirstName)
            TextField("Cognome *", text: $newPatientLastName)
            DatePicker("Data di nascita *", selection: $newPatientBirthDate, displayedComponents: .date)
            Picker("Genere", selection: $newPatientGender) {
                Text("Non specificato").tag("")
                Text("Maschio").tag("Maschio")
                Text("Femmina").tag("Femmina")
                Text("Altro").tag("Altro")
            }
            .pickerStyle(.segmented)

            TextField("Luogo di nascita *", text: $newPatientPlaceOfBirth)
            TextField("Provincia (es. TO)", text: $newPatientBirthProvince)

            HStack {
                Spacer()

                Button("Annulla") {
                    resetNewPatientDraft()
                    showAddPatientSheet = false
                }

                Button("Crea paziente") {
                    addPatient()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreatePatient)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(minWidth: 420)
    }

    private func addPatient() {
        guard canCreatePatient else { return }

        let firstName = newPatientFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastName = newPatientLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeOfBirth = newPatientPlaceOfBirth.trimmingCharacters(in: .whitespacesAndNewlines)
        let birthProvince = newPatientBirthProvince.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let generatedTaxCode = ItalianTaxCode.generate(
            firstName: firstName,
            lastName: lastName,
            birthDate: newPatientBirthDate,
            gender: newPatientGender,
            placeOfBirth: placeOfBirth,
            birthProvince: birthProvince.isEmpty ? nil : birthProvince
        ) ?? ""

        withAnimation {
            let newPatient = Patient(
                firstName: firstName,
                lastName: lastName,
                dateOfBirth: newPatientBirthDate,
                gender: newPatientGender,
                taxCode: generatedTaxCode,
                placeOfBirth: placeOfBirth,
                birthProvince: birthProvince.isEmpty ? nil : birthProvince,
                createdAt: .now,
                updatedAt: .now
            )
            modelContext.insert(newPatient)
            selectedPatientID = newPatient.id
        }

        resetNewPatientDraft()
        showAddPatientSheet = false
    }

    private func resetNewPatientDraft() {
        newPatientFirstName = ""
        newPatientLastName = ""
        newPatientBirthDate = Date()
        newPatientGender = ""
        newPatientPlaceOfBirth = ""
        newPatientBirthProvince = ""
    }

    private func openSelectedPatientWindow() {
        guard let patient = selectedPatient else { return }
        openPatientWindow(patient)
    }

    private func openPatientWindow(_ patient: Patient) {
        PatientWindowCoordinator.shared.open(patient: patient, modelContainer: modelContext.container)
    }

    private func delete(_ patient: Patient) {
        withAnimation {
            if selectedPatientID == patient.id {
                selectedPatientID = nil
            }
            modelContext.delete(patient)
        }
    }
}

private struct PatientRowView: View {
    let patient: Patient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(patient.displayTitle)
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                if !patient.primaryDiagnosis.isEmpty {
                    Label(patient.primaryDiagnosis, systemImage: "cross.case")
                        .lineLimit(1)
                }

                if !patient.phoneNumber.isEmpty {
                    Label(patient.phoneNumber, systemImage: "phone")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct PatientSelectionSummaryView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var patient: Patient
    let openAction: () -> Void

    @State private var birthPlaceSuggestions: [ItalianTaxCode.PlaceSuggestion] = []
    @State private var showBirthPlaceSuggestions = false
    @FocusState private var isBirthPlaceFocused: Bool

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { patient.dateOfBirth ?? .now },
            set: {
                patient.dateOfBirth = $0
                patient.updatedAt = .now
            }
        )
    }

    private var canGenerateTaxCode: Bool {
        ItalianTaxCode.generate(
            firstName: patient.firstName,
            lastName: patient.lastName,
            birthDate: patient.dateOfBirth,
            gender: patient.gender,
            placeOfBirth: patient.placeOfBirth,
            birthProvince: patient.birthProvince
        ) != nil
    }

    private func autoFillTaxCodeIfPossible(force: Bool = false) {
        guard let generated = ItalianTaxCode.generate(
            firstName: patient.firstName,
            lastName: patient.lastName,
            birthDate: patient.dateOfBirth,
            gender: patient.gender,
            placeOfBirth: patient.placeOfBirth,
            birthProvince: patient.birthProvince
        ) else {
            return
        }

        let current = patient.taxCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if force || current.isEmpty {
            patient.taxCode = generated
            patient.updatedAt = .now
        }
    }

    private func refreshBirthPlaceSuggestions() {
        birthPlaceSuggestions = ItalianTaxCode.suggestions(
            for: patient.placeOfBirth,
            province: patient.birthProvince
        )
    }

    private func applyBirthPlaceSuggestion(_ suggestion: ItalianTaxCode.PlaceSuggestion) {
        patient.placeOfBirth = suggestion.name
        patient.birthProvince = suggestion.province
        birthPlaceSuggestions = []
        showBirthPlaceSuggestions = false
        autoFillTaxCodeIfPossible(force: true)
        patient.updatedAt = .now
    }

    private func syncResidenceLegacy() {
        let parts = [
            patient.residenceAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            patient.residenceCity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            patient.residenceProvince?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ]
        .filter { !$0.isEmpty }

        patient.residence = parts.joined(separator: ", ")
    }

    private func hydrateResidenceFieldsIfNeeded() {
        guard (patient.residenceAddress ?? "").isEmpty,
              (patient.residenceCity ?? "").isEmpty,
              (patient.residenceProvince ?? "").isEmpty,
              !patient.residence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let chunks = patient.residence.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let first = chunks.first, !first.isEmpty {
            patient.residenceAddress = first
        }
        if chunks.count > 1, !chunks[1].isEmpty {
            patient.residenceCity = chunks[1]
        }
        if chunks.count > 2, !chunks[2].isEmpty {
            patient.residenceProvince = String(chunks[2].prefix(2)).uppercased()
        }
    }

    private func demographicTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(patient.fullName)
                            .font(.title2)
                            .fontWeight(.semibold)

                        if !patient.primaryDiagnosis.isEmpty {
                            Label(patient.primaryDiagnosis, systemImage: "cross.case")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(action: openAction) {
                        Label("Apri cartella clinica", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if !patient.hasRequiredDemographics {
                    Label("Completa nome, cognome e data di nascita (campi obbligatori)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Nome *")
                                TextField("", text: $patient.firstName, prompt: Text("Nome"))
                                    .onChange(of: patient.firstName) { _, _ in
                                        patient.updatedAt = .now
                                        autoFillTaxCodeIfPossible()
                                    }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Cognome *")
                                TextField("", text: $patient.lastName, prompt: Text("Cognome"))
                                    .onChange(of: patient.lastName) { _, _ in
                                        patient.updatedAt = .now
                                        autoFillTaxCodeIfPossible()
                                    }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    demographicTitle("Data di nascita *")
                                    DatePicker("", selection: birthDateBinding, displayedComponents: .date)
                                        .labelsHidden()
                                        .frame(width: 200, alignment: .leading)
                                        .onChange(of: patient.dateOfBirth) { _, _ in
                                            autoFillTaxCodeIfPossible()
                                        }
                                }
                                .frame(width: 220, alignment: .leading)

                                VStack(alignment: .leading, spacing: 6) {
                                    demographicTitle("Genere")
                                    Picker("", selection: Binding(
                                        get: { patient.gender ?? "" },
                                        set: { patient.gender = $0.isEmpty ? nil : $0 }
                                    )) {
                                        Text("Non specificato").tag("")
                                        Text("Maschio").tag("Maschio")
                                        Text("Femmina").tag("Femmina")
                                        Text("Altro").tag("Altro")
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.segmented)
                                    .onChange(of: patient.gender) { _, _ in
                                        patient.updatedAt = .now
                                        autoFillTaxCodeIfPossible()
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    demographicTitle("Data di nascita *")
                                    DatePicker("", selection: birthDateBinding, displayedComponents: .date)
                                        .labelsHidden()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .onChange(of: patient.dateOfBirth) { _, _ in
                                            autoFillTaxCodeIfPossible()
                                        }
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    demographicTitle("Genere")
                                    Picker("", selection: Binding(
                                        get: { patient.gender ?? "" },
                                        set: { patient.gender = $0.isEmpty ? nil : $0 }
                                    )) {
                                        Text("Non specificato").tag("")
                                        Text("Maschio").tag("Maschio")
                                        Text("Femmina").tag("Femmina")
                                        Text("Altro").tag("Altro")
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.segmented)
                                    .onChange(of: patient.gender) { _, _ in
                                        patient.updatedAt = .now
                                        autoFillTaxCodeIfPossible()
                                    }
                                }
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Codice fiscale")
                                HStack(spacing: 8) {
                                    TextField("", text: $patient.taxCode, prompt: Text("Codice fiscale"))
                                        .onChange(of: patient.taxCode) { _, _ in patient.updatedAt = .now }

                                    Button("Ricalcola") {
                                        autoFillTaxCodeIfPossible(force: true)
                                    }
                                    .disabled(!canGenerateTaxCode)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Diagnosi principale")
                                TextField("", text: $patient.primaryDiagnosis, prompt: Text("Diagnosi principale"))
                                    .onChange(of: patient.primaryDiagnosis) { _, _ in patient.updatedAt = .now }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Diagnosi secondaria")
                                TextField("", text: $patient.secondaryDiagnosis, prompt: Text("Diagnosi secondaria"))
                                    .onChange(of: patient.secondaryDiagnosis) { _, _ in patient.updatedAt = .now }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Luogo di nascita")
                                TextField("", text: $patient.placeOfBirth, prompt: Text("Es. Torino"))
                                    .focused($isBirthPlaceFocused)
                                    .onChange(of: patient.placeOfBirth) { _, _ in
                                        patient.updatedAt = .now
                                        refreshBirthPlaceSuggestions()
                                        showBirthPlaceSuggestions = true
                                        autoFillTaxCodeIfPossible()
                                    }
                                    .onSubmit {
                                        showBirthPlaceSuggestions = false
                                    }
                                    .onChange(of: isBirthPlaceFocused) { _, focused in
                                        if !focused {
                                            showBirthPlaceSuggestions = false
                                        }
                                    }

                                if showBirthPlaceSuggestions && isBirthPlaceFocused && !birthPlaceSuggestions.isEmpty && !patient.placeOfBirth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(birthPlaceSuggestions) { suggestion in
                                            Button {
                                                applyBirthPlaceSuggestion(suggestion)
                                            } label: {
                                                Text(suggestion.displayText)
                                                    .font(.caption)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                        }
                                    }
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(nsColor: .controlBackgroundColor))
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Provincia")
                                TextField("", text: Binding(
                                    get: { patient.birthProvince ?? "" },
                                    set: { patient.birthProvince = $0.isEmpty ? nil : String($0.prefix(2)).uppercased() }
                                ), prompt: Text("TO"))
                                .onChange(of: patient.birthProvince) { _, _ in
                                    patient.updatedAt = .now
                                    autoFillTaxCodeIfPossible()
                                }
                            }
                            .frame(width: 90)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Indirizzo")
                                TextField("", text: Binding(
                                    get: { patient.residenceAddress ?? "" },
                                    set: { patient.residenceAddress = $0.isEmpty ? nil : $0 }
                                ), prompt: Text("Via/Piazza e numero civico"))
                                .onChange(of: patient.residenceAddress) { _, _ in
                                    patient.updatedAt = .now
                                    syncResidenceLegacy()
                                }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Città")
                                TextField("", text: Binding(
                                    get: { patient.residenceCity ?? "" },
                                    set: { patient.residenceCity = $0.isEmpty ? nil : $0 }
                                ), prompt: Text("Città"))
                                .onChange(of: patient.residenceCity) { _, _ in
                                    patient.updatedAt = .now
                                    syncResidenceLegacy()
                                }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Provincia")
                                TextField("", text: Binding(
                                    get: { patient.residenceProvince ?? "" },
                                    set: { patient.residenceProvince = $0.isEmpty ? nil : String($0.prefix(2)).uppercased() }
                                ), prompt: Text("TO"))
                                .onChange(of: patient.residenceProvince) { _, _ in
                                    patient.updatedAt = .now
                                    syncResidenceLegacy()
                                }
                            }
                            .frame(width: 90)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Telefono")
                                TextField("", text: $patient.phoneNumber, prompt: Text("Numero di telefono"))
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Emergenza")
                                TextField("", text: $patient.emergencyContact, prompt: Text("Contatto di emergenza"))
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Privacy")
                                Toggle("Consenso firmato", isOn: $patient.privacyConsentSigned)
                                    .toggleStyle(.switch)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Medico di famiglia (MMG)")
                                TextField("", text: $patient.generalPractitioner, prompt: Text("MMG"))
                                    .onChange(of: patient.generalPractitioner) { _, _ in patient.updatedAt = .now }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("CSM di riferimento")
                                TextField("", text: $patient.referenceCSM, prompt: Text("CSM"))
                                    .onChange(of: patient.referenceCSM) { _, _ in patient.updatedAt = .now }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Curante di riferimento")
                                TextField("", text: $patient.referringClinician, prompt: Text("Curante"))
                                    .onChange(of: patient.referringClinician) { _, _ in patient.updatedAt = .now }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 900, alignment: .leading)
                    .padding(.vertical, 2)
                } label: {
                    Label("Anagrafica", systemImage: "person.text.rectangle")
                        .font(.headline)
                }

                GroupBox {
                    HStack {
                        Label("Dati clinici e aggiornamenti sono nella scheda clinica del paziente.", systemImage: "stethoscope")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: openAction) {
                            Label("Apri scheda clinica", systemImage: "arrow.up.forward.app")
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Sezione clinica", systemImage: "cross.case")
                        .font(.headline)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            hydrateResidenceFieldsIfNeeded()
            autoFillTaxCodeIfPossible()
        }
    }
}

private struct TherapyMedicationRow: View {
    @Bindable var item: TherapyMedication
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Farmaco", text: $item.medicationName)
                TextField("Dosaggio", text: $item.dosage)
                TextField("Posologia", text: $item.posology)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            Toggle("Attivo", isOn: $item.isActive)
                .toggleStyle(.switch)
        }
        .textFieldStyle(.roundedBorder)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct ClinicalNoteCardView: View {
    @Bindable var note: ClinicalNote
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(note.createdAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if note.updatedAt > note.createdAt {
                    Text("Modificata")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))

                TextEditor(text: $note.content)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .onChange(of: note.content) { _, _ in
                        note.updatedAt = .now
                    }
            }
            .frame(minHeight: 90)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.25))
            )

            HStack {
                Text("Benessere: \(note.wellbeingScore)/10")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Slider(value: Binding(
                    get: { Double(note.wellbeingScore) },
                    set: {
                        note.wellbeingScore = Int($0.rounded())
                        note.updatedAt = .now
                    }
                ), in: 0...10, step: 1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct PatientClinicalWindowView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var patient: Patient

    @State private var newNoteContent = ""
    @State private var newNoteWellbeing = 5

    private var sortedNotes: [ClinicalNote] {
        patient.clinicalNotes.sorted { $0.createdAt > $1.createdAt }
    }

    private var activeTherapyItems: [TherapyMedication] {
        patient.therapyItems
            .filter(\.isActive)
            .sorted { $0.medicationName.localizedCaseInsensitiveCompare($1.medicationName) == .orderedAscending }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(patient.fullName)
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    if !patient.primaryDiagnosis.isEmpty {
                        Label(patient.primaryDiagnosis, systemImage: "cross.case")
                            .foregroundStyle(.secondary)
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

                            VStack(alignment: .leading, spacing: 6) {
                                clinicalTitle("Esenzioni")
                                TextField("", text: $patient.exemptions, prompt: Text("Esenzioni"))
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
                    .onChange(of: patient.exemptions) { _, _ in patient.updatedAt = .now }
                    .onChange(of: patient.medicalComorbidities) { _, _ in patient.updatedAt = .now }
                    .onChange(of: patient.remotePsychiatricHistory) { _, _ in patient.updatedAt = .now }
                }

                GroupBox("Terapia attuale") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(activeTherapyItems) { item in
                            TherapyMedicationRow(item: item) {
                                modelContext.delete(item)
                                patient.updatedAt = .now
                            }
                        }

                        Button {
                            let newItem = TherapyMedication(patient: patient)
                            modelContext.insert(newItem)
                            patient.therapyItems.append(newItem)
                            patient.updatedAt = .now
                        } label: {
                            Label("Aggiungi farmaco", systemImage: "plus")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Aggiornamenti clinici") {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nuova nota")
                                .font(.headline)

                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .textBackgroundColor))

                                TextEditor(text: $newNoteContent)
                                    .font(.body)
                                    .scrollContentBackground(.hidden)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 6)
                            }
                            .frame(minHeight: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.secondary.opacity(0.25))
                            )

                            HStack {
                                Text("Benessere: \(newNoteWellbeing)/10")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Slider(value: Binding(
                                    get: { Double(newNoteWellbeing) },
                                    set: { newNoteWellbeing = Int($0.rounded()) }
                                ), in: 0...10, step: 1)
                            }

                            Button {
                                let note = ClinicalNote(
                                    content: newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines),
                                    wellbeingScore: newNoteWellbeing,
                                    patient: patient
                                )
                                modelContext.insert(note)
                                patient.clinicalNotes.append(note)
                                patient.updatedAt = .now
                                newNoteContent = ""
                                newNoteWellbeing = 5
                            } label: {
                                Label("Salva nota", systemImage: "square.and.arrow.down")
                            }
                            .disabled(newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        Divider()

                        if sortedNotes.isEmpty {
                            Text("Nessun aggiornamento clinico")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(sortedNotes) { note in
                                ClinicalNoteCardView(note: note) {
                                    modelContext.delete(note)
                                    patient.updatedAt = .now
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            hydrateLegacyAnamnesisIfNeeded()
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(value.isEmpty ? .tertiary : .primary)
                .textSelection(.enabled)
        } label: {
            Text(label)
        }
    }
}

private final class PatientWindowCoordinator {
    static let shared = PatientWindowCoordinator()

    private var windows: [UUID: NSWindow] = [:]

    private init() {}

    func open(patient: Patient, modelContainer: ModelContainer) {
        if let existingWindow = windows[patient.id] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = PatientClinicalWindowView(patient: patient)
            .modelContainer(modelContainer)

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = patient.displayTitle
        window.setContentSize(NSSize(width: 980, height: 720))
        window.minSize = NSSize(width: 820, height: 600)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        let delegate = PatientWindowDelegate(patientID: patient.id) { [weak self] patientID in
            self?.windows.removeValue(forKey: patientID)
        }

        window.delegate = delegate
        objc_setAssociatedObject(window, "patientWindowDelegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        windows[patient.id] = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class PatientWindowDelegate: NSObject, NSWindowDelegate {
    let patientID: UUID
    let onClose: (UUID) -> Void

    init(patientID: UUID, onClose: @escaping (UUID) -> Void) {
        self.patientID = patientID
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose(patientID)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Patient.self, ClinicalNote.self, TherapyMedication.self], inMemory: true)
}
