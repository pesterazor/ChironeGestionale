import SwiftUI
import SwiftData

@MainActor
final class ClinicalDraftAutosaveStore {
    static let shared = ClinicalDraftAutosaveStore()

    private struct StoredDraft: Codable {
        let encryptedContent: String?
        let plainFallbackContent: String?
        let wellbeing: Int
        let noteDate: Date
    }

    struct RestoredDraft {
        let content: String
        let wellbeing: Int
        let noteDate: Date
    }

    private let storageKeyPrefix = "clinicalDraftAutosave.patient."
    private let defaults: UserDefaults
    private let encrypt: @MainActor (String) -> String?
    private let decrypt: @MainActor (String?) -> String?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults = .standard,
        encrypt: @escaping @MainActor (String) -> String? = { SecureDataCipher.shared.encrypt($0) },
        decrypt: @escaping @MainActor (String?) -> String? = { SecureDataCipher.shared.decrypt($0) }
    ) {
        self.defaults = defaults
        self.encrypt = encrypt
        self.decrypt = decrypt
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    @discardableResult
    func saveDraft(patientID: UUID, content: String, wellbeing: Int, noteDate: Date) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && wellbeing == 5 {
            clearDraft(patientID: patientID)
            return true
        }

        let encrypted = trimmed.isEmpty ? nil : encrypt(trimmed)
        // Preserve the last recoverable draft if the encryption key is unavailable.
        guard trimmed.isEmpty || encrypted != nil else { return false }
        let payload = StoredDraft(
            encryptedContent: encrypted,
            plainFallbackContent: nil,
            wellbeing: min(max(wellbeing, 1), 10),
            noteDate: noteDate
        )
        guard let data = try? encoder.encode(payload) else { return false }
        defaults.set(data, forKey: key(for: patientID))
        return true
    }

    func loadDraft(patientID: UUID) -> RestoredDraft? {
        guard let data = defaults.data(forKey: key(for: patientID)),
              let decoded = try? decoder.decode(StoredDraft.self, from: data)
        else {
            return nil
        }

        let content: String
        if let encrypted = decoded.encryptedContent,
           let decrypted = decrypt(encrypted) {
            content = decrypted
        } else if let legacyContent = decoded.plainFallbackContent {
            content = legacyContent
        } else if decoded.encryptedContent == nil {
            content = ""
        } else {
            return nil
        }

        // Migrate legacy drafts without keeping a second, unencrypted copy.
        if decoded.plainFallbackContent != nil {
            saveDraft(patientID: patientID, content: content, wellbeing: decoded.wellbeing, noteDate: decoded.noteDate)
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

@MainActor
enum ClinicalNoteEditing {
    static func save(
        _ note: ClinicalNote,
        content: String,
        wellbeing: Int?,
        date: Date?,
        persist: () throws -> Void
    ) throws {
        let original = (note.content, note.encryptedContent, note.wellbeingScore, note.createdAt, note.updatedAt)
        let patientUpdatedAt = note.patient?.updatedAt
        guard note.protectContent(content) else { throw SecureDataCipherError.keyCreationFailed }
        if let wellbeing { note.wellbeingScore = wellbeing }
        if let date { note.createdAt = date }
        note.updatedAt = .now
        note.patient?.updatedAt = .now
        do {
            try persist()
        } catch {
            (note.content, note.encryptedContent, note.wellbeingScore, note.createdAt, note.updatedAt) = original
            if let patientUpdatedAt { note.patient?.updatedAt = patientUpdatedAt }
            throw error
        }
    }
}

private struct ClinicalNoteCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: ClinicalNote
    let onDelete: () -> Void
    let onEditingStateChange: (UUID, Bool) -> Void
    let onSaved: () -> Void
    let canEnterEditing: Bool

    @State private var isEditing = false
    @State private var draftContent = ""
    @State private var draftWellbeing = 5
    @State private var draftDate = Date()
    @State private var shouldEditDate = false
    @State private var showDeleteConfirmation = false
    @State private var saveError: String?

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
        note.isAutomaticSystemUpdate
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
                        saveEdits()
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
                .accessibilityLabel(isEditing ? "Conferma modifica" : "Modifica nota")
                .disabled((!isEditing && !canEnterEditing) || (isEditing && draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                actionIconButton(symbol: "trash", isDestructive: true) {
                    showDeleteConfirmation = true
                }
                .accessibilityLabel("Elimina nota")
                .disabled(!canEnterEditing && !isEditing)
                .confirmationDialog(
                    "Eliminare questo aggiornamento clinico?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Elimina", role: .destructive) {
                        isEditing = false
                        onEditingStateChange(note.id, false)
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
                            saveEdits()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } else {
                let content = note.readableContent
                Text(content.isEmpty ? "Nessun contenuto" : content)
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
        .alert("Impossibile salvare la nota", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private func saveEdits() {
        do {
            try ClinicalNoteEditing.save(note, content: draftContent,
                wellbeing: isAutomaticSystemUpdate ? nil : draftWellbeing,
                date: shouldEditDate ? draftDate : nil) {
                try modelContext.save()
            }
            isEditing = false
            onEditingStateChange(note.id, false)
            onSaved()
        } catch {
            saveError = "La modifica è ancora disponibile. Riprova il salvataggio. " + error.localizedDescription
        }
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
    var canSave = true

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
            .disabled(!canSave || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    let editingNoteIDs: Set<UUID>

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
                        ClinicalNoteCardView(
                            note: note,
                            onDelete: { onDelete(note) },
                            onEditingStateChange: onEditingStateChange,
                            onSaved: onNoteSaved,
                            canEnterEditing: editingNoteIDs.isEmpty || editingNoteIDs.contains(note.id)
                        )
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
    @State private var saveError: String?
    @State private var autosaveFailed = false

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

    private let notesPageSize = 5
    private let autosaveDebounceNanoseconds: UInt64 = 2_000_000_000

    private struct DraftSnapshot: Equatable {
        let content: String
        let wellbeing: Int
        let noteDate: Date
    }
    private var hasUnsavedDrafts: Bool {
        !newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !editingNoteIDs.isEmpty
    }

    private var canGoToOlderNotesPage: Bool {
        editingNoteIDs.isEmpty && notesPageOffset + notesPageSize < totalNotesCount
    }

    private var canGoToNewerNotesPage: Bool {
        editingNoteIDs.isEmpty && notesPageOffset > 0
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
        guard editingNoteIDs.isEmpty, !newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let originalUpdatedAt = patient.updatedAt
        let timestamp = newNoteDate
        let note = ClinicalNote(
            content: "",
            wellbeingScore: newNoteWellbeing,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        guard note.protectContent(newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            saveError = "La protezione della nota non è disponibile. La bozza è conservata: riprova il salvataggio."
            return
        }
        note.patient = patient
        modelContext.insert(note)
        patient.clinicalNotes.append(note)
        patient.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            patient.clinicalNotes.removeAll { $0.id == note.id }
            modelContext.delete(note)
            patient.updatedAt = originalUpdatedAt
            saveError = "La bozza è ancora disponibile. Riprova il salvataggio. " + error.localizedDescription
            return
        }
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
        onSaved?()
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
        guard currentSnapshot != lastAutosavedSnapshot else { return }
        let didSave = ClinicalDraftAutosaveStore.shared.saveDraft(
            patientID: patient.id,
            content: newNoteContent,
            wellbeing: newNoteWellbeing,
            noteDate: newNoteDate
        )
        autosaveFailed = !didSave
        guard didSave else { return }
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
        ClinicalSectionBox("Aggiornamenti clinici", systemImage: "note.text") {
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
                    onSave: saveNewNote,
                    canSave: editingNoteIDs.isEmpty
                )

                if !editingNoteIDs.isEmpty {
                    Text("Salva o annulla la nota in modifica prima di cambiare pagina o aggiungerne una nuova.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if autosaveFailed {
                    Label("Recupero automatico della bozza non disponibile: mantieni aperta la scheda e salva la nota.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

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
                            if editingNoteIDs.isEmpty { refreshTimelineNotes() }
                        }
                        onDraftStateChange(hasUnsavedDrafts)
                    },
                    onNoteSaved: {
                        if editingNoteIDs.isEmpty { refreshTimelineNotes() }
                    },
                    editingNoteIDs: editingNoteIDs
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Impossibile salvare la nota", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
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
            guard editingNoteIDs.isEmpty else { return }
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
            guard AppLockViewModel.shared.permitsClinicalAccess, isNotificationForThisPatient(notification) else { return }
            saveNewNote()
        }
    }
}
