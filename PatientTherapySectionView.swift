import SwiftUI

struct TherapyDraftItem: Identifiable, Equatable {
    let id: UUID
    let sourceID: UUID?
    var medicationName: String
    var dosage: String
    var posology: String
}

struct NormalizedTherapyRow: Equatable {
    let sourceID: UUID?
    let medicationName: String
    let dosage: String
    let posology: String
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

struct PatientTherapySectionView: View {
    @Binding var therapyDraft: [TherapyDraftItem]
    let pendingTherapyMedicationFocusID: UUID?
    let hasUnsavedTherapyChanges: Bool
    let onMedicationAutofocused: (UUID) -> Void
    let onDeleteRow: (UUID) -> Void
    let onAddRow: () -> Void
    let onSave: () -> Void

    var body: some View {
        GroupBox("Terapia attuale") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach($therapyDraft) { $item in
                    TherapyMedicationRow(
                        item: $item,
                        shouldAutoFocusMedication: pendingTherapyMedicationFocusID == item.id,
                        onMedicationAutofocused: {
                            onMedicationAutofocused(item.id)
                        },
                        onDelete: {
                            onDeleteRow(item.id)
                        }
                    )
                }

                HStack(spacing: 10) {
                    Button {
                        onAddRow()
                    } label: {
                        Label("Aggiungi farmaco", systemImage: "plus")
                    }
                    .accessibilityIdentifier("therapy_add_medication_button")
                    .keyboardShortcut("n", modifiers: [.command, .option])

                    Button("Salva terapia") {
                        onSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("therapy_save_button")
                    .keyboardShortcut("t", modifiers: [.command, .option])
                    .disabled(!hasUnsavedTherapyChanges)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
