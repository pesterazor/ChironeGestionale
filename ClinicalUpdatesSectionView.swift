import SwiftUI
import SwiftData

@MainActor
private final class ClinicalDraftAutosaveStore {
    static let shared = ClinicalDraftAutosaveStore()

    private struct StoredDraft: Codable {
        let encryptedContent: String?
        let plainFallbackContent: String
        let wellbeing: Int
        let noteDate: Date
    }

    struct RestoredDraft {
        let content: String
        let wellbeing: Int
        let noteDate: Date
    }

    private let storageKeyPrefix = "clinicalDraftAutosave.patient."
    private let defaults = UserDefaults.standard
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func saveDraft(patientID: UUID, content: String, wellbeing: Int, noteDate: Date) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && wellbeing == 5 {
            clearDraft(patientID: patientID)
            return
        }

        let payload = StoredDraft(
            encryptedContent: SecureDataCipher.shared.encrypt(trimmed),
            plainFallbackContent: trimmed,
            wellbeing: min(max(wellbeing, 1), 10),
            noteDate: noteDate
        )
        guard let data = try? encoder.encode(payload) else { return }
        defaults.set(data, forKey: key(for: patientID))
    }

    func loadDraft(patientID: UUID) -> RestoredDraft? {
        guard let data = defaults.data(forKey: key(for: patientID)),
              let decoded = try? decoder.decode(StoredDraft.self, from: data)
        else {
            return nil
        }

        let content: String
        if let encrypted = decoded.encryptedContent,
           let decrypted = SecureDataCipher.shared.decrypt(encrypted) {
            content = decrypted
        } else {
            content = decoded.plainFallbackContent
        }

        return RestoredDraft(
            content: content,
            wellbeing: min(max(decoded.wellbeing, 1), 10),
            noteDate: decoded.noteDate
        )
    }

    func clearDraft(patientID: UUID) {
        defaults.removeObject(forKey: key(for: patientID))
    }

    private func key(for patientID: UUID) -> String {
        storageKeyPrefix + patientID.uuidString
    }
}

private func wellbeingColor(for score: Int) -> Color {
    switch score {
    case ..<4:
        return .red
    case 4...6:
        return .yellow
    default:
        return .green
    }
}

private struct ClinicalNoteCardView: View {
    @Bindable var note: ClinicalNote
    let onDelete: () -> Void
    let onEditingStateChange: (UUID, Bool) -> Void
    let onSaved: () -> Void

    @State private var isEditing = false
    @State private var draftContent = ""
    @State private var draftWellbeing = 5
    @State private var draftDate = Date()
    @State private var shouldEditDate = false
    @State private var showDeleteConfirmation = false

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

    private var isAutomaticSystemUpdate: Bool {
        note.readableContent.hasPrefix("Aggiornamento terapia farmacologica:") ||
        note.readableContent.hasPrefix("Richiesti esami ematochimici:") ||
        note.readableContent.hasPrefix("Presa visione esami ematochimici:")
    }

    private var shouldShowWellbeing: Bool {
        !isAutomaticSystemUpdate && note.wellbeingScore > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(note.createdAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if shouldShowWellbeing {
                    Text("Benessere percepito: \(note.wellbeingScore)/10")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(wellbeingColor(for: note.wellbeingScore).opacity(0.9))
                        )
                }

                actionIconButton(symbol: isEditing ? "checkmark.circle" : "pencil") {
                    if isEditing {
                        note.protectContent(draftContent)
                        if !isAutomaticSystemUpdate {
                            note.wellbeingScore = draftWellbeing
                        }
                        if shouldEditDate {
                            note.createdAt = draftDate
                        }
                        note.updatedAt = .now
                        isEditing = false
                        onEditingStateChange(note.id, false)
                        onSaved()
                    } else {
                        draftContent = note.readableContent
                        draftWellbeing = note.wellbeingScore
                        draftDate = note.createdAt
                        shouldEditDate = false
                        isEditing = true
                        onEditingStateChange(note.id, true)
                    }
                }
                .help(isEditing ? "Conferma modifica" : "Modifica nota")

                actionIconButton(symbol: "trash", isDestructive: true) {
                    showDeleteConfirmation = true
                }
                .confirmationDialog(
                    "Eliminare questo aggiornamento clinico?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Elimina", role: .destructive) {
                        onDelete()
                    }
                    Button("Annulla", role: .cancel) { }
                } message: {
                    Text("L'operazione non può essere annullata.")
                }
            }

            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))

                        TextEditor(text: $draftContent)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
                    }
                    .frame(minHeight: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.25))
                    )

                    if !isAutomaticSystemUpdate {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Benessere percepito: \(draftWellbeing)/10")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            PerceivedWellbeingPickerView(wellbeing: $draftWellbeing)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Modifica data e ora della nota", isOn: $shouldEditDate)
                            .toggleStyle(.checkbox)

                        if shouldEditDate {
                            DatePicker(
                                "",
                                selection: $draftDate,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                        }
                    }

                    HStack {
                        Button("Annulla") {
                            draftContent = note.readableContent
                            draftWellbeing = note.wellbeingScore
                            draftDate = note.createdAt
                            shouldEditDate = false
                            isEditing = false
                            onEditingStateChange(note.id, false)
                        }

                        Button("Salva") {
                            note.protectContent(draftContent)
                            if !isAutomaticSystemUpdate {
                                note.wellbeingScore = draftWellbeing
                            }
                            if shouldEditDate {
                                note.createdAt = draftDate
                            }
                            note.updatedAt = .now
                            isEditing = false
                            onEditingStateChange(note.id, false)
                            onSaved()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Text(note.readableContent.isEmpty ? "Nessun contenuto" : note.readableContent)
                    .textSelection(.enabled)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.18))
        )
        .padding(.vertical, 2)
    }
}

private struct PerceivedWellbeingPickerView: View {
    @Binding var wellbeing: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...10, id: \.self) { score in
                let color = wellbeingColor(for: score)
                let isSelected = wellbeing == score

                Button {
                    wellbeing = score
                } label: {
                    Text("\(score)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : color)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(isSelected ? color : color.opacity(0.18))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(color.opacity(isSelected ? 0 : 0.45), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Benessere percepito \(score) su 10")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NewClinicalNoteComposerView: View {
    @Binding var content: String
    @Binding var wellbeing: Int
    @Binding var noteDate: Date
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nuova nota")
                .font(.headline)
                .padding(.leading, 8)
                .padding(.vertical, 4)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))

                TextEditor(text: $content)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("clinical_new_note_text")
            }
            .frame(minHeight: 100)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.25))
            )
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Data e ora aggiornamento")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                DatePicker(
                    "",
                    selection: $noteDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("Benessere percepito: \(wellbeing)/10")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                PerceivedWellbeingPickerView(wellbeing: $wellbeing)
            }
            .padding(.horizontal, 12)

            Button(action: onSave) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.headline)
                    Text("Salva nota")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("clinical_save_note_button")
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct ClinicalTimelineView: View {
    let notes: [ClinicalNote]
    let totalCount: Int
    let currentRangeText: String
    let canGoToNewerPage: Bool
    let canGoToOlderPage: Bool
    let onGoToNewerPage: () -> Void
    let onGoToOlderPage: () -> Void
    let onDelete: (ClinicalNote) -> Void
    let onEditingStateChange: (UUID, Bool) -> Void
    let onNoteSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Timeline")
                    .font(.headline)

                Spacer()

                Text(currentRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Button(action: onGoToNewerPage) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canGoToNewerPage)
                    .help("Aggiornamenti più recenti")

                    Button(action: onGoToOlderPage) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canGoToOlderPage)
                    .help("Aggiornamenti più vecchi")
                }
            }

            if notes.isEmpty {
                Text("Nessun aggiornamento clinico")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(notes) { note in
                        ClinicalNoteCardView(note: note) {
                            onDelete(note)
                        } onEditingStateChange: { noteID, isEditing in
                            onEditingStateChange(noteID, isEditing)
                        } onSaved: {
                            onNoteSaved()
                        }
                    }
                }
            }
        }
        .padding(12)
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

struct ClinicalUpdatesSectionView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var patient: Patient

    @State private var newNoteContent = ""
    @State private var newNoteWellbeing = 5
    @State private var newNoteDate = Date()
    @State private var notesPageOffset = 0
    @State private var timelineNotes: [ClinicalNote] = []
    @State private var totalNotesCount = 0
    @State private var editingNoteIDs: Set<UUID> = []
    @State private var didRestoreDraft = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var lastAutosaveSignature = ""
    @State private var lastAutosavedSnapshot: DraftSnapshot?

    let onDraftStateChange: (Bool) -> Void

    private let notesPageSize = 5
    private let autosaveDebounceNanoseconds: UInt64 = 10_000_000_000

    private struct DraftSnapshot {
        let content: String
        let wellbeing: Int
        let noteDate: Date
    }
    private var hasUnsavedDrafts: Bool {
        !newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !editingNoteIDs.isEmpty
    }

    private var canGoToOlderNotesPage: Bool {
        notesPageOffset + notesPageSize < totalNotesCount
    }

    private var canGoToNewerNotesPage: Bool {
        notesPageOffset > 0
    }

    private var currentRangeText: String {
        guard totalNotesCount > 0, !timelineNotes.isEmpty else {
            return "0 aggiornamenti"
        }

        let start = notesPageOffset + 1
        let end = min(notesPageOffset + timelineNotes.count, totalNotesCount)
        return "\(start)-\(end) di \(totalNotesCount)"
    }

    private func refreshTimelineNotes() {
        let patientID = patient.id
        let countDescriptor = FetchDescriptor<ClinicalNote>(
            predicate: #Predicate { note in
                note.patient?.id == patientID
            }
        )

        do {
            totalNotesCount = try modelContext.fetchCount(countDescriptor)

            if totalNotesCount == 0 {
                notesPageOffset = 0
                timelineNotes = []
                return
            }

            let maxOffset = max(0, ((totalNotesCount - 1) / notesPageSize) * notesPageSize)
            notesPageOffset = min(notesPageOffset, maxOffset)

            var notesDescriptor = FetchDescriptor<ClinicalNote>(
                predicate: #Predicate { note in
                    note.patient?.id == patientID
                },
                sortBy: [
                    SortDescriptor(\ClinicalNote.createdAt, order: .reverse),
                    SortDescriptor(\ClinicalNote.updatedAt, order: .reverse),
                    SortDescriptor(\ClinicalNote.id, order: .reverse)
                ]
            )
            notesDescriptor.fetchOffset = notesPageOffset
            notesDescriptor.fetchLimit = notesPageSize

            timelineNotes = try modelContext.fetch(notesDescriptor)
        } catch {
            totalNotesCount = 0
            notesPageOffset = 0
            timelineNotes = []
        }

        let visibleIDs = Set(timelineNotes.map(\.id))
        editingNoteIDs = editingNoteIDs.intersection(visibleIDs)
        onDraftStateChange(hasUnsavedDrafts)
    }

    private func saveNewNote() {
        guard !newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let timestamp = newNoteDate
        let note = ClinicalNote(
            content: "",
            wellbeingScore: newNoteWellbeing,
            createdAt: timestamp,
            updatedAt: timestamp,
            patient: patient
        )
        note.protectContent(newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines))
        modelContext.insert(note)
        patient.clinicalNotes.append(note)
        patient.updatedAt = .now
        newNoteContent = ""
        newNoteWellbeing = 5
        newNoteDate = .now
        ClinicalDraftAutosaveStore.shared.clearDraft(patientID: patient.id)
        autosaveTask?.cancel()
        autosaveTask = nil
        lastAutosaveSignature = ""
        lastAutosavedSnapshot = nil
        didRestoreDraft = false
        notesPageOffset = 0
        refreshTimelineNotes()
        onDraftStateChange(hasUnsavedDrafts)
    }

    private func restoreDraftIfAvailable() {
        guard let restored = ClinicalDraftAutosaveStore.shared.loadDraft(patientID: patient.id) else {
            didRestoreDraft = false
            return
        }

        newNoteContent = restored.content
        newNoteWellbeing = restored.wellbeing
        newNoteDate = restored.noteDate
        didRestoreDraft = !restored.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        lastAutosaveSignature = autosaveSignature()
        lastAutosavedSnapshot = DraftSnapshot(
            content: newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines),
            wellbeing: newNoteWellbeing,
            noteDate: newNoteDate
        )
    }

    private func autosaveSignature() -> String {
        let trimmed = newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmed)|\(newNoteWellbeing)|\(newNoteDate.timeIntervalSince1970)"
    }

    private func autosaveDraftNow() {
        let signature = autosaveSignature()
        guard signature != lastAutosaveSignature else { return }
        let currentSnapshot = DraftSnapshot(
            content: newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines),
            wellbeing: newNoteWellbeing,
            noteDate: newNoteDate
        )
        guard isSignificantDraftChange(from: lastAutosavedSnapshot, to: currentSnapshot) else { return }
        ClinicalDraftAutosaveStore.shared.saveDraft(
            patientID: patient.id,
            content: newNoteContent,
            wellbeing: newNoteWellbeing,
            noteDate: newNoteDate
        )
        lastAutosaveSignature = signature
        lastAutosavedSnapshot = currentSnapshot
    }

    private func scheduleAutosaveDraft() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: autosaveDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            autosaveDraftNow()
        }
    }

    private func isSignificantDraftChange(from previous: DraftSnapshot?, to current: DraftSnapshot) -> Bool {
        guard let previous else {
            return !current.content.isEmpty
        }

        if previous.wellbeing != current.wellbeing {
            return true
        }

        if abs(current.noteDate.timeIntervalSince(previous.noteDate)) >= 60 {
            return true
        }

        if previous.content.isEmpty != current.content.isEmpty {
            return true
        }

        let lengthDelta = abs(current.content.count - previous.content.count)
        if lengthDelta >= 20 {
            return true
        }

        return false
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

    private func deleteNote(_ note: ClinicalNote) {
        modelContext.delete(note)
        patient.updatedAt = .now
        refreshTimelineNotes()
    }

    private func goToOlderNotesPage() {
        guard canGoToOlderNotesPage else { return }
        notesPageOffset += notesPageSize
        refreshTimelineNotes()
    }

    private func goToNewerNotesPage() {
        guard canGoToNewerNotesPage else { return }
        notesPageOffset = max(0, notesPageOffset - notesPageSize)
        refreshTimelineNotes()
    }

    var body: some View {
        GroupBox("Aggiornamenti clinici") {
            VStack(alignment: .leading, spacing: 14) {
                if didRestoreDraft {
                    Label("Bozza recuperata automaticamente", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                NewClinicalNoteComposerView(
                    content: $newNoteContent,
                    wellbeing: $newNoteWellbeing,
                    noteDate: $newNoteDate,
                    onSave: saveNewNote
                )

                ClinicalTimelineView(
                    notes: timelineNotes,
                    totalCount: totalNotesCount,
                    currentRangeText: currentRangeText,
                    canGoToNewerPage: canGoToNewerNotesPage,
                    canGoToOlderPage: canGoToOlderNotesPage,
                    onGoToNewerPage: goToNewerNotesPage,
                    onGoToOlderPage: goToOlderNotesPage,
                    onDelete: deleteNote,
                    onEditingStateChange: { noteID, isEditing in
                        if isEditing {
                            editingNoteIDs.insert(noteID)
                        } else {
                            editingNoteIDs.remove(noteID)
                        }
                        onDraftStateChange(hasUnsavedDrafts)
                    },
                    onNoteSaved: {
                        refreshTimelineNotes()
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            notesPageOffset = 0
            editingNoteIDs.removeAll()
            restoreDraftIfAvailable()
            if newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                newNoteDate = .now
            }
            refreshTimelineNotes()
            onDraftStateChange(hasUnsavedDrafts)
        }
        .onChange(of: patient.id) { _, _ in
            autosaveTask?.cancel()
            autosaveTask = nil
            lastAutosaveSignature = ""
            lastAutosavedSnapshot = nil
            notesPageOffset = 0
            editingNoteIDs.removeAll()
            newNoteContent = ""
            newNoteWellbeing = 5
            newNoteDate = .now
            restoreDraftIfAvailable()
            refreshTimelineNotes()
            onDraftStateChange(hasUnsavedDrafts)
        }
        .onChange(of: patient.clinicalNotes.count) { _, _ in
            notesPageOffset = 0
            refreshTimelineNotes()
            onDraftStateChange(hasUnsavedDrafts)
        }
        .onChange(of: newNoteContent) { _, _ in
            scheduleAutosaveDraft()
            onDraftStateChange(hasUnsavedDrafts)
        }
        .onChange(of: newNoteWellbeing) { _, _ in
            scheduleAutosaveDraft()
            onDraftStateChange(hasUnsavedDrafts)
        }
        .onChange(of: newNoteDate) { _, _ in
            scheduleAutosaveDraft()
            onDraftStateChange(hasUnsavedDrafts)
        }
        .onDisappear {
            autosaveTask?.cancel()
            autosaveTask = nil
            autosaveDraftNow()
            onDraftStateChange(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteSaveClinicalNoteRequested)) { notification in
            guard isNotificationForThisPatient(notification) else { return }
            saveNewNote()
        }
    }
}
