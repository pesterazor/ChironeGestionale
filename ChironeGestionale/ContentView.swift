import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    private struct CommandPaletteAction: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let keywords: [String]
        let handler: () -> Void
    }

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
    @EnvironmentObject private var commandPaletteState: CommandPaletteState
    @Query(sort: [SortDescriptor(\Patient.lastName), SortDescriptor(\Patient.firstName)]) private var patients: [Patient]

    @State private var searchText = ""
    @State private var selectedPatientID: UUID?
    @State private var showAddPatientSheet = false
    @State private var didAttemptWindowRestore = false

    @State private var newPatientFirstName = ""
    @State private var newPatientLastName = ""
    @State private var newPatientBirthDate = Date()
    @State private var newPatientGender = ""
    @State private var newPatientPlaceOfBirth = ""
    @State private var newPatientBirthProvince = ""
    @State private var newPatientBirthPlaceSuggestions: [ItalianTaxCode.PlaceSuggestion] = []
    @State private var showNewPatientBirthPlaceSuggestions = false

    @State private var sidebarSortOption: SidebarSortOption = .name
    @State private var commandPaletteQuery = ""
    @State private var commandPaletteOpenedAt: Date?

    @FocusState private var isNewPatientBirthPlaceFocused: Bool

    private var commandPaletteActions: [CommandPaletteAction] {
        [
            CommandPaletteAction(
                title: "Nuovo paziente",
                subtitle: "Apre la scheda di creazione paziente",
                keywords: ["nuovo", "paziente", "anagrafica", "create"]
            ) {
                showAddPatientSheet = true
            },
            CommandPaletteAction(
                title: "Apri cartella clinica selezionata",
                subtitle: "Apre la finestra clinica del paziente corrente",
                keywords: ["apri", "cartella", "clinica", "finestra", "patient"]
            ) {
                openSelectedPatientWindow()
            },
            CommandPaletteAction(
                title: "Ordina pazienti per nome",
                subtitle: "Imposta ordinamento alfabetico",
                keywords: ["ordina", "nome", "alfabetico", "sidebar"]
            ) {
                sidebarSortOption = .name
            },
            CommandPaletteAction(
                title: "Ordina pazienti per ultima visita",
                subtitle: "Prioritizza pazienti con attività recente",
                keywords: ["ordina", "ultima", "visita", "recenti", "sidebar"]
            ) {
                sidebarSortOption = .lastVisit
            },
            CommandPaletteAction(
                title: "Pulisci ricerca pazienti",
                subtitle: "Azzera il filtro testuale in sidebar",
                keywords: ["pulisci", "ricerca", "filtro", "search"]
            ) {
                searchText = ""
            },
            CommandPaletteAction(
                title: "Salva nota clinica (paziente attivo)",
                subtitle: "Esegue salvataggio nota nella cartella clinica attiva",
                keywords: ["salva", "nota", "clinica", "active", "patient"]
            ) {
                dispatchCommandToActivePatientWindow(.commandPaletteSaveClinicalNoteRequested)
            },
            CommandPaletteAction(
                title: "Aggiungi farmaco (paziente attivo)",
                subtitle: "Aggiunge una riga terapia nella cartella clinica attiva",
                keywords: ["aggiungi", "farmaco", "terapia", "active", "patient"]
            ) {
                dispatchCommandToActivePatientWindow(.commandPaletteAddTherapyMedicationRequested)
            },
            CommandPaletteAction(
                title: "Salva terapia (paziente attivo)",
                subtitle: "Salva terapia farmacologica della cartella attiva",
                keywords: ["salva", "terapia", "farmaco", "active", "patient"]
            ) {
                dispatchCommandToActivePatientWindow(.commandPaletteSaveTherapyRequested)
            },
            CommandPaletteAction(
                title: "Salva esami (paziente attivo)",
                subtitle: "Salva tabella esami nella cartella clinica attiva",
                keywords: ["salva", "esami", "ematochimici", "active", "patient"]
            ) {
                dispatchCommandToActivePatientWindow(.commandPaletteSaveBloodTestsRequested)
            }
        ]
    }

    private var filteredCommandPaletteActions: [CommandPaletteAction] {
        let query = commandPaletteQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return commandPaletteActions
        }

        return commandPaletteActions.filter { action in
            if action.title.lowercased().contains(query) || action.subtitle.lowercased().contains(query) {
                return true
            }
            return action.keywords.contains(where: { $0.lowercased().contains(query) })
        }
    }

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
                .accessibilityIdentifier("new_patient_button")

                Button(action: openSelectedPatientWindow) {
                    Label("Apri cartella clinica", systemImage: "arrow.up.forward.app")
                }
                .disabled(selectedPatient == nil)
                .accessibilityIdentifier("open_patient_window_button")
            }
        }
        .sheet(isPresented: $showAddPatientSheet) {
            addPatientSheet
        }
        .sheet(isPresented: $commandPaletteState.isPresented, onDismiss: {
            commandPaletteQuery = ""
            commandPaletteOpenedAt = nil
        }) {
            commandPaletteSheet
        }
        .onAppear {
            if !didAttemptWindowRestore {
                didAttemptWindowRestore = true
                PatientWindowCoordinator.shared.restoreOpenWindows(modelContainer: modelContext.container)
            }

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
        .onChange(of: commandPaletteState.isPresented) { _, isPresented in
            if isPresented {
                commandPaletteOpenedAt = Date()
            } else {
                commandPaletteOpenedAt = nil
            }
        }
    }

    private var commandPaletteSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Command Palette")
                .font(.title3.weight(.semibold))

            TextField("Cerca azione (es. nuovo paziente, apri cartella, ordina...)", text: $commandPaletteQuery)
                .textFieldStyle(.roundedBorder)

            if filteredCommandPaletteActions.isEmpty {
                ContentUnavailableView(
                    "Nessuna azione trovata",
                    systemImage: "magnifyingglass",
                    description: Text("Prova con un termine diverso.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredCommandPaletteActions) { action in
                    Button {
                        action.handler()
                        logCommandPaletteExecution(actionTitle: action.title)
                        commandPaletteState.dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(action.title)
                                .font(.body.weight(.semibold))
                            Text(action.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(action.title == "Apri cartella clinica selezionata" && selectedPatient == nil)
                }
                .listStyle(.inset)
            }

            HStack {
                Text("Shortcut")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("⌘K")
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                    )
                Spacer()
                Button("Chiudi") {
                    commandPaletteState.dismiss()
                }
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 420)
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
                .accessibilityIdentifier("new_patient_first_name")
            TextField("Cognome *", text: $newPatientLastName)
                .accessibilityIdentifier("new_patient_last_name")
            DatePicker("Data di nascita *", selection: $newPatientBirthDate, displayedComponents: .date)
            Picker("Genere", selection: $newPatientGender) {
                Text("Maschio").tag("Maschio")
                Text("Femmina").tag("Femmina")
                Text("Altro").tag("Altro")
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Luogo di nascita *", text: $newPatientPlaceOfBirth)
                    .accessibilityIdentifier("new_patient_birth_place")
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
                .accessibilityIdentifier("new_patient_birth_province")

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
                .accessibilityIdentifier("create_patient_button")
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

    private func dispatchCommandToActivePatientWindow(_ name: Notification.Name) {
        guard let activePatient = PatientWindowCoordinator.shared.activePatient() else {
            NSSound.beep()
            return
        }

        NotificationCenter.default.post(
            name: name,
            object: self,
            userInfo: ["patientID": activePatient.id.uuidString]
        )
    }

    private func logCommandPaletteExecution(actionTitle: String) {
        let normalizedAction = actionTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")

        let latencyMs: Int? = {
            guard let openedAt = commandPaletteOpenedAt else { return nil }
            let elapsed = Date().timeIntervalSince(openedAt)
            if elapsed < 0 { return nil }
            return Int((elapsed * 1000).rounded())
        }()

        let latencyBucket: String = {
            guard let latencyMs else { return "unknown" }
            switch latencyMs {
            case 0..<750: return "<750ms"
            case 750..<1500: return "750-1500ms"
            case 1500..<3000: return "1.5-3s"
            case 3000..<6000: return "3-6s"
            default: return ">6s"
            }
        }()

        var metadata: [String: String] = [
            "action": normalizedAction,
            "latency_bucket": latencyBucket
        ]
        if let latencyMs {
            metadata["latency_ms"] = String(latencyMs)
        }

        AuditTrailService.shared.log(.commandPaletteActionExecuted, metadata: metadata)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Patient.self, ClinicalNote.self, TherapyMedication.self], inMemory: true)
}
