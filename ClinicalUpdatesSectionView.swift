import SwiftUI
import SwiftData

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

    @State private var isEditing = false
    @State private var draftContent = ""
    @State private var draftWellbeing = 5
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

    private var isAutomaticTherapyUpdate: Bool {
        note.content.hasPrefix("Aggiornamento terapia farmacologica:")
    }

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

                if !isAutomaticTherapyUpdate {
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
                        note.content = draftContent
                        if !isAutomaticTherapyUpdate {
                            note.wellbeingScore = draftWellbeing
                        }
                        note.updatedAt = .now
                        isEditing = false
                        onEditingStateChange(note.id, false)
                    } else {
                        draftContent = note.content
                        draftWellbeing = note.wellbeingScore
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

                    if !isAutomaticTherapyUpdate {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Benessere percepito: \(draftWellbeing)/10")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            PerceivedWellbeingPickerView(wellbeing: $draftWellbeing)
                        }
                    }

                    HStack {
                        Button("Annulla") {
                            draftContent = note.content
                            draftWellbeing = note.wellbeingScore
                            isEditing = false
                            onEditingStateChange(note.id, false)
                        }

                        Button("Salva") {
                            note.content = draftContent
                            if !isAutomaticTherapyUpdate {
                                note.wellbeingScore = draftWellbeing
                            }
                            note.updatedAt = .now
                            isEditing = false
                            onEditingStateChange(note.id, false)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Text(note.content.isEmpty ? "Nessun contenuto" : note.content)
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
            }
            .frame(minHeight: 100)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.25))
            )
            .padding(.horizontal, 8)

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
            .padding(.horizontal, 12)
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
    @State private var notesPageOffset = 0
    @State private var timelineNotes: [ClinicalNote] = []
    @State private var totalNotesCount = 0
    @State private var editingNoteIDs: Set<UUID> = []

    let onDraftStateChange: (Bool) -> Void

    private let notesPageSize = 5
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
                sortBy: [SortDescriptor(\ClinicalNote.createdAt, order: .reverse)]
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
        notesPageOffset = 0
        refreshTimelineNotes()
        onDraftStateChange(hasUnsavedDrafts)
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
                NewClinicalNoteComposerView(
                    content: $newNoteContent,
                    wellbeing: $newNoteWellbeing,
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
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            notesPageOffset = 0
            editingNoteIDs.removeAll()
            refreshTimelineNotes()
            onDraftStateChange(hasUnsavedDrafts)
        }
        .onChange(of: patient.id) { _, _ in
            notesPageOffset = 0
            editingNoteIDs.removeAll()
            newNoteContent = ""
            newNoteWellbeing = 5
            refreshTimelineNotes()
            onDraftStateChange(hasUnsavedDrafts)
        }
        .onChange(of: patient.clinicalNotes.count) { _, _ in
            notesPageOffset = 0
            refreshTimelineNotes()
            onDraftStateChange(hasUnsavedDrafts)
        }
        .onChange(of: newNoteContent) { _, _ in
            onDraftStateChange(hasUnsavedDrafts)
        }
        .onDisappear {
            onDraftStateChange(false)
        }
    }
}
