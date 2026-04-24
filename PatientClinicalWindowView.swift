import SwiftUI
import SwiftData

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

struct PatientClinicalWindowView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var patient: Patient

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

                ClinicalUpdatesSectionView(patient: patient)
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
