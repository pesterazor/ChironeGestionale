import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    private enum SidebarSortOption: String, CaseIterable, Identifiable {
        case name
        case lastVisit

        var id: String { rawValue }

        var title: String {
            switch self {
            case .name:
                return "Nome"
            case .lastVisit:
                return "Ultima visita"
            }
        }
    }

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
    @State private var newPatientBirthPlaceSuggestions: [ItalianTaxCode.PlaceSuggestion] = []
    @State private var showNewPatientBirthPlaceSuggestions = false

    @State private var sidebarSortOption: SidebarSortOption = .name

    @FocusState private var isNewPatientBirthPlaceFocused: Bool

    private var filteredPatients: [Patient] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let baseList: [Patient]
        if trimmedQuery.isEmpty {
            baseList = patients
        } else {
            baseList = patients.filter { patient in
                patient.searchableTokens.contains { token in
                    token.contains(trimmedQuery)
                }
            }
        }

        switch sidebarSortOption {
        case .name:
            return baseList.sorted { lhs, rhs in
                let compare = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
                if compare == .orderedSame {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return compare == .orderedAscending
            }

        case .lastVisit:
            return baseList.sorted { lhs, rhs in
                switch (lhs.lastVisitDate, rhs.lastVisitDate) {
                case let (lDate?, rDate?):
                    if lDate != rDate {
                        return lDate > rDate
                    }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }

                let compare = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
                if compare == .orderedSame {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return compare == .orderedAscending
            }
        }
    }

    private var selectedPatient: Patient? {
        guard let selectedPatientID else { return nil }
        return patients.first(where: { $0.id == selectedPatientID })
    }

    private var canCreatePatient: Bool {
        !newPatientFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newPatientLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newPatientPlaceOfBirth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasNewPatientDraftData: Bool {
        !newPatientFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !newPatientLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !newPatientGender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !newPatientPlaceOfBirth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !newPatientBirthProvince.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.prominentDetail)
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

                Menu {
                    ForEach(SidebarSortOption.allCases) { option in
                        Button {
                            sidebarSortOption = option
                        } label: {
                            if sidebarSortOption == option {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Label("Ordina", systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .help("Ordina elenco pazienti")
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

    private var addPatientSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nuovo paziente")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Nome *", text: $newPatientFirstName)
            TextField("Cognome *", text: $newPatientLastName)
            DatePicker("Data di nascita *", selection: $newPatientBirthDate, displayedComponents: .date)
            Picker("Genere", selection: $newPatientGender) {
                Text("Maschio").tag("Maschio")
                Text("Femmina").tag("Femmina")
                Text("Altro").tag("Altro")
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Luogo di nascita *", text: $newPatientPlaceOfBirth)
                    .focused($isNewPatientBirthPlaceFocused)
                    .onChange(of: newPatientPlaceOfBirth) { _, _ in
                        refreshNewPatientBirthPlaceSuggestions()
                        showNewPatientBirthPlaceSuggestions = !newPatientPlaceOfBirth
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    }
                    .onSubmit {
                        showNewPatientBirthPlaceSuggestions = false
                    }
                    .onChange(of: isNewPatientBirthPlaceFocused) { _, focused in
                        if !focused {
                            showNewPatientBirthPlaceSuggestions = false
                        }
                    }
                    .onChange(of: newPatientBirthProvince) { _, _ in
                        if showNewPatientBirthPlaceSuggestions {
                            refreshNewPatientBirthPlaceSuggestions()
                        }
                    }

                if showNewPatientBirthPlaceSuggestions &&
                    !newPatientBirthPlaceSuggestions.isEmpty &&
                    !newPatientPlaceOfBirth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(newPatientBirthPlaceSuggestions) { suggestion in
                                Button {
                                    applyNewPatientBirthPlaceSuggestion(suggestion)
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
                    }
                    .frame(maxHeight: 120)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }

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
        .onExitCommand {
            if showNewPatientBirthPlaceSuggestions {
                showNewPatientBirthPlaceSuggestions = false
                newPatientBirthPlaceSuggestions = []
            } else if hasNewPatientDraftData {
                NSSound.beep()
            } else {
                resetNewPatientDraft()
                showAddPatientSheet = false
            }
        }
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
        newPatientBirthPlaceSuggestions = []
        showNewPatientBirthPlaceSuggestions = false
    }

    private func refreshNewPatientBirthPlaceSuggestions() {
        let provinceFilter: String? = {
            let trimmed = newPatientBirthProvince
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            return trimmed.count == 2 ? trimmed : nil
        }()

        newPatientBirthPlaceSuggestions = ItalianTaxCode.suggestions(
            for: newPatientPlaceOfBirth,
            province: provinceFilter
        )
    }

    private func applyNewPatientBirthPlaceSuggestion(_ suggestion: ItalianTaxCode.PlaceSuggestion) {
        newPatientPlaceOfBirth = suggestion.name
        newPatientBirthProvince = suggestion.province
        newPatientBirthPlaceSuggestions = []
        showNewPatientBirthPlaceSuggestions = false
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

#Preview {
    ContentView()
        .modelContainer(for: [Patient.self, ClinicalNote.self, TherapyMedication.self], inMemory: true)
}
