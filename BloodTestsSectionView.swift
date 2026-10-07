import SwiftUI
import Foundation
import SwiftData
import AppKit

@MainActor
enum BloodTestsPersistence {
    static func save(
        _ payload: BloodTestsTablePayload,
        replacing previous: BloodTestsTablePayload,
        for patient: Patient,
        in context: ModelContext,
        persist: () throws -> Void
    ) throws {
        let encoded = BloodTestsSectionViewModel.encodePayload(payload)
        guard !encoded.isEmpty else { throw CocoaError(.coderInvalidValue) }
        let originalJSON = patient.bloodTestsTableJSON
        let originalUpdatedAt = patient.updatedAt
        var automaticNote: ClinicalNote?
        if let content = BloodTestsSectionViewModel.bloodTestsRequestNoteText(from: previous, to: payload) {
            let note = ClinicalNote(wellbeingScore: 0)
            guard note.protectContent(content) else { throw SecureDataCipherError.keyCreationFailed }
            automaticNote = note
        }
        patient.bloodTestsTableJSON = encoded
        patient.updatedAt = .now
        if let note = automaticNote {
            note.patient = patient
            context.insert(note)
            patient.clinicalNotes.append(note)
        }
        do {
            try persist()
        } catch {
            patient.bloodTestsTableJSON = originalJSON
            patient.updatedAt = originalUpdatedAt
            if let note = automaticNote {
                patient.clinicalNotes.removeAll { $0.id == note.id }
                context.delete(note)
            }
            throw error
        }
    }
}

struct BloodTestsSectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var patient: Patient
    let onDraftStateChange: (Bool) -> Void
    let onSaved: (() -> Void)?

    init(
        patient: Patient,
        onDraftStateChange: @escaping (Bool) -> Void,
        onSaved: (() -> Void)? = nil
    ) {
        self.patient = patient
        self.onDraftStateChange = onDraftStateChange
        self.onSaved = onSaved
    }

    @State private var draft = BloodTestsTablePayload.empty
    @State private var persistedDraft = BloodTestsTablePayload.empty
    @State private var newCustomTestName = ""
    @State private var didLoad = false
    @State private var newColumnDate = Date()
    @State private var selectedColumnID: UUID?
    @State private var editingColumnID: UUID?
    @State private var editingColumnDate = Date()
    @State private var isPresentingEditColumnPopover = false
    @State private var rowIndexByID: [UUID: Int] = [:]
    @State private var cachedSortedColumns: [BloodTestColumnRecord] = []
    @State private var cachedSortedRows: [BloodTestRowRecord] = []
    @State private var lastRowsStructureKey: [UUID: String] = [:]
    @State private var saveError: String?
    @State private var hasUncommittedCellChanges = false
    @FocusState private var isNewExamNameFocused: Bool

    private var hasUnsavedChanges: Bool {
        draft != persistedDraft || hasUncommittedCellChanges
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

    private func computeSortedColumns(from columns: [BloodTestColumnRecord]) -> [BloodTestColumnRecord] {
        // Date parsing is considerably costlier than comparing the resulting dates.
        let datesByID = Dictionary(uniqueKeysWithValues: columns.map {
            ($0.id, BloodTestsSectionViewModel.parsedDate(from: $0.dateText))
        })
        return columns.sorted { lhs, rhs in
            let leftDate = datesByID[lhs.id] ?? nil
            let rightDate = datesByID[rhs.id] ?? nil
            switch (leftDate, rightDate) {
            case let (l?, r?):
                if l != r {
                    return l > r
                }
                return lhs.dateText.localizedCaseInsensitiveCompare(rhs.dateText) == .orderedAscending
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.dateText.localizedCaseInsensitiveCompare(rhs.dateText) == .orderedAscending
            }
        }
    }

    private func computeSortedRows(from rows: [BloodTestRowRecord]) -> [BloodTestRowRecord] {
        rows.sorted { lhs, rhs in
            let leftKey = BloodTestsDefaults.normalizedName(BloodTestsDefaults.canonicalName(lhs.testName))
            let rightKey = BloodTestsDefaults.normalizedName(BloodTestsDefaults.canonicalName(rhs.testName))
            let leftOrder = BloodTestsDefaults.defaultTestOrder[leftKey]
            let rightOrder = BloodTestsDefaults.defaultTestOrder[rightKey]

            switch (leftOrder, rightOrder) {
            case let (l?, r?):
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.testName.localizedCaseInsensitiveCompare(rhs.testName) == .orderedAscending
            }
        }
    }

    private func refreshSortedCaches() {
        cachedSortedColumns = computeSortedColumns(from: draft.columns)
        cachedSortedRows = computeSortedRows(from: draft.rows)
        lastRowsStructureKey = currentRowsStructureKey()
    }

    private func currentRowsStructureKey() -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: draft.rows.map { ($0.id, $0.testName) })
    }

    var body: some View {
        ClinicalSectionBox("Esami ematochimici", systemImage: "drop.circle") {
            VStack(alignment: .leading, spacing: 12) {
                topControls
                    .popover(isPresented: $isPresentingEditColumnPopover, arrowEdge: .bottom) {
                        AppLockGateView { editColumnPopoverContent }
                    }

                tableContainer

                addExamRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Esami non salvati", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            loadFromPatient()
            onDraftStateChange(hasUnsavedChanges)
            rebuildRowIndex()
            refreshSortedCaches()
        }
        .onChange(of: patient.id) { _, _ in
            loadFromPatient()
            onDraftStateChange(hasUnsavedChanges)
            rebuildRowIndex()
            refreshSortedCaches()
        }
        .onChange(of: hasUnsavedChanges) { _, value in
            onDraftStateChange(value)
        }
        .onChange(of: draft.rows) { _, _ in
            rebuildRowIndex()
            let currentKey = currentRowsStructureKey()
            if currentKey != lastRowsStructureKey {
                // Row added, removed, or renamed: full resort required.
                lastRowsStructureKey = currentKey
                cachedSortedRows = computeSortedRows(from: draft.rows)
            } else {
                // Only cell values changed: propagate updated values to sorted rows
                // in-place without paying the sort cost (O(n) vs O(n log n)).
                for i in cachedSortedRows.indices {
                    if let idx = rowIndexByID[cachedSortedRows[i].id] {
                        cachedSortedRows[i] = draft.rows[idx]
                    }
                }
            }
        }
        .onChange(of: draft.columns) { _, _ in
            cachedSortedColumns = computeSortedColumns(from: draft.columns)
        }
        .onDisappear {
            onDraftStateChange(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteSaveBloodTestsRequested)) { notification in
            guard AppLockViewModel.shared.permitsClinicalAccess, isNotificationForThisPatient(notification) else { return }
            saveDraft()
        }
    }
}

private extension BloodTestsSectionView {
    var topControls: some View {
        HStack(alignment: .center, spacing: 6) {
            DatePicker(
                "",
                selection: $newColumnDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)

            Button("Aggiungi data") {
                addDateColumn(for: newColumnDate)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("bloodtests_add_date_button")

            Button("Salva esami") {
                saveDraft()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(!hasUnsavedChanges)
            .accessibilityIdentifier("bloodtests_save_button")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var editColumnPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modifica data colonna")
                .font(.headline)

            DatePicker(
                "Data",
                selection: $editingColumnDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            HStack {
                Spacer()
                Button("Annulla") {
                    isPresentingEditColumnPopover = false
                    editingColumnID = nil
                }
                Button("Salva") {
                    if let editingColumnID {
                        updateColumnDate(columnID: editingColumnID, to: editingColumnDate)
                    }
                    isPresentingEditColumnPopover = false
                    editingColumnID = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    var tableContainer: some View {
        BloodTestsAppKitTableView(
            rows: cachedSortedRows,
            columns: cachedSortedColumns,
            rowNameForID: rowName(for:),
            setRowName: setRowName(_:to:),
            cellValueForIDs: cellValue(rowID:columnID:),
            setCellValue: setCellValue(rowID:columnID:value:),
            canDeleteRow: canDeleteRow(with:),
            deleteRow: deleteRow(with:),
            onHeaderEditColumn: handleHeaderEditColumn,
            onHeaderAddAfterColumn: handleHeaderAddAfterColumn,
            onHeaderDeleteColumn: handleHeaderDeleteColumn,
            onUncommittedEditChange: { hasUncommittedCellChanges = $0 },
            selectedColumnID: $selectedColumnID
        )
        .accessibilityIdentifier("bloodtests_table")
        .frame(minHeight: 320)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.15))
        )
    }

    var addExamRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nuova voce esame")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Es. PCR, Ferritina, Trigliceridi (Invio per aggiungere)", text: $newCustomTestName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNewExamNameFocused)
                    .submitLabel(.done)
                    .onSubmit(addCustomRow)
                    .frame(maxWidth: 360)
                    .accessibilityIdentifier("bloodtests_new_exam_textfield")
            }

            Spacer()
        }
    }
}

private extension BloodTestsSectionView {
    func rowName(for rowID: UUID) -> String {
        guard let rowIndex = rowIndexByID[rowID], draft.rows.indices.contains(rowIndex) else {
            return ""
        }
        return draft.rows[rowIndex].testName
    }

    func setRowName(_ rowID: UUID, to value: String) {
        guard let index = rowIndexByID[rowID], draft.rows.indices.contains(index) else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.rows[index].testName == trimmed { return }
        draft.rows[index].testName = trimmed
    }

    func cellValue(rowID: UUID, columnID: UUID) -> String {
        let key = columnID.uuidString
        guard let rowIndex = rowIndexByID[rowID], draft.rows.indices.contains(rowIndex) else {
            return ""
        }
        return draft.rows[rowIndex].values[key] ?? ""
    }

    func setCellValue(rowID: UUID, columnID: UUID, value: String) {
        let key = columnID.uuidString
        guard let rowIndex = rowIndexByID[rowID], draft.rows.indices.contains(rowIndex) else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = draft.rows[rowIndex].values[key] ?? ""
        if previous == trimmed { return }

        if trimmed.isEmpty {
            draft.rows[rowIndex].values.removeValue(forKey: key)
        } else {
            draft.rows[rowIndex].values[key] = trimmed
        }

        BloodTestsSectionViewModel.applyDerivedCalculations(
            to: &draft,
            forColumnID: columnID,
            patientDateOfBirth: patient.dateOfBirth,
            patientGender: patient.gender
        )
    }

    func canDeleteRow(with rowID: UUID) -> Bool {
        guard let rowIndex = rowIndexByID[rowID], draft.rows.indices.contains(rowIndex) else { return false }
        let row = draft.rows[rowIndex]
        return !BloodTestsSectionViewModel.isDefaultRow(row)
    }

    func deleteRow(with rowID: UUID) {
        DispatchQueue.main.async {
            removeRow(rowID: rowID)
        }
    }

    func handleHeaderEditColumn(_ columnID: UUID) {
        DispatchQueue.main.async {
            selectedColumnID = columnID
            editingColumnID = columnID
            let currentText = draft.columns.first(where: { $0.id == columnID })?.dateText ?? ""
            editingColumnDate = BloodTestsSectionViewModel.parsedDate(from: currentText) ?? .now
            isPresentingEditColumnPopover = true
        }
    }

    func handleHeaderAddAfterColumn(_ columnID: UUID) {
        DispatchQueue.main.async {
            selectedColumnID = columnID
            addDateColumn(after: columnID)
        }
    }

    func handleHeaderDeleteColumn(_ columnID: UUID) {
        DispatchQueue.main.async {
            selectedColumnID = columnID
            removeDateColumn(columnID: columnID)
        }
    }

}

private extension BloodTestsSectionView {
    func loadFromPatient() {
        let decoded = BloodTestsSectionViewModel.decodePayload(from: patient.bloodTestsTableJSON)
        draft = BloodTestsSectionViewModel.normalizePayload(decoded)
        recalculateDerivedValuesForAllColumns()
        persistedDraft = draft
        rebuildRowIndex()
        refreshSortedCaches()
    }

    func saveDraft() {
        // Finish the active AppKit cell before reading the draft, including keyboard saves.
        if let window = NSApp.keyWindow, !window.makeFirstResponder(nil) { return }
        guard hasUnsavedChanges else { return }
        recalculateDerivedValuesForAllColumns()
        let normalized = BloodTestsSectionViewModel.normalizePayload(draft)
        do {
            try BloodTestsPersistence.save(normalized, replacing: persistedDraft, for: patient, in: modelContext) {
                try modelContext.save()
            }
            draft = normalized
            persistedDraft = normalized
            refreshSortedCaches()
            onSaved?()
        } catch {
            saveError = "Le modifiche restano nella tabella. Riprova il salvataggio. " + error.localizedDescription
        }
    }

    func dateText(from date: Date) -> String {
        BloodTestsSectionViewModel.dateText(from: date)
    }

    func addDateColumn(for date: Date) {
        draft.columns.append(BloodTestColumnRecord(id: UUID(), dateText: dateText(from: date)))
    }

    func addDateColumn(after columnID: UUID) {
        let baseDate = draft.columns.first(where: { $0.id == columnID }).flatMap { BloodTestsSectionViewModel.parsedDate(from: $0.dateText) } ?? .now
        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: baseDate) ?? .now
        let newColumn = BloodTestColumnRecord(id: UUID(), dateText: dateText(from: nextDate))

        if let index = draft.columns.firstIndex(where: { $0.id == columnID }) {
            draft.columns.insert(newColumn, at: index + 1)
        } else {
            draft.columns.append(newColumn)
        }
    }

    func updateColumnDate(columnID: UUID, to newDate: Date) {
        guard let index = draft.columns.firstIndex(where: { $0.id == columnID }) else { return }
        draft.columns[index].dateText = dateText(from: newDate)
    }

    func removeDateColumn(columnID: UUID) {
        draft.columns.removeAll { $0.id == columnID }
        let key = columnID.uuidString
        for index in draft.rows.indices {
            draft.rows[index].values.removeValue(forKey: key)
        }
    }

    func addCustomRow() {
        let name = BloodTestsDefaults.canonicalName(newCustomTestName)
        guard !name.isEmpty else { return }

        let normalized = BloodTestsDefaults.normalizedName(name)
        if draft.rows.contains(where: { BloodTestsDefaults.normalizedName(BloodTestsDefaults.canonicalName($0.testName)) == normalized }) {
            newCustomTestName = ""
            return
        }

        draft.rows.append(BloodTestRowRecord(id: UUID(), testName: name, values: [:]))
        newCustomTestName = ""
        isNewExamNameFocused = true
    }

    func removeRow(rowID: UUID) {
        draft.rows.removeAll { $0.id == rowID }
        rebuildRowIndex()
        refreshSortedCaches()
    }

    func recalculateDerivedValuesForAllColumns() {
        for column in draft.columns {
            BloodTestsSectionViewModel.applyDerivedCalculations(
                to: &draft,
                forColumnID: column.id,
                patientDateOfBirth: patient.dateOfBirth,
                patientGender: patient.gender
            )
        }
    }

    func rebuildRowIndex() {
        var index: [UUID: Int] = [:]
        index.reserveCapacity(draft.rows.count)
        for (rowIndex, row) in draft.rows.enumerated() {
            index[row.id] = rowIndex
        }
        rowIndexByID = index
    }

}
