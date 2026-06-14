import SwiftUI

struct PatientClinicalDataSectionView: View {
    @Bindable var patient: Patient

    private func clinicalTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    var body: some View {
        GroupBox("Dati clinici") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        clinicalTitle("Diagnosi principale")
                        TextField(
                            "",
                            text: Binding(
                                get: { patient.readablePrimaryDiagnosis },
                                set: { patient.protectPrimaryDiagnosis($0) }
                            ),
                            prompt: Text("Diagnosi principale")
                        )
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        clinicalTitle("Diagnosi secondaria")
                        TextField(
                            "",
                            text: Binding(
                                get: { patient.readableSecondaryDiagnosis },
                                set: { patient.protectSecondaryDiagnosis($0) }
                            ),
                            prompt: Text("Diagnosi secondaria")
                        )
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        clinicalTitle("Allergie")
                        TextField(
                            "",
                            text: Binding(
                                get: { patient.readableAllergies },
                                set: { patient.protectAllergies($0) }
                            ),
                            prompt: Text("Allergie")
                        )
                    }
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 6) {
                    clinicalTitle("Comorbidità mediche")
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))

                        TextEditor(text: Binding(
                            get: { patient.readableMedicalComorbidities },
                            set: { patient.protectMedicalComorbidities($0) }
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
                            get: { patient.readableRemotePsychiatricHistory },
                            set: { patient.protectRemotePsychiatricHistory($0) }
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
            // The protect* setters write to the encrypted field and clear the plain mirror
            // synchronously. Watching only the encrypted fields (ground truth) avoids
            // a double updatedAt mutation per keystroke.
            .onChange(of: patient.encryptedPrimaryDiagnosis) { _, _ in patient.updatedAt = .now }
            .onChange(of: patient.encryptedSecondaryDiagnosis) { _, _ in patient.updatedAt = .now }
            .onChange(of: patient.encryptedAllergies) { _, _ in patient.updatedAt = .now }
            .onChange(of: patient.encryptedMedicalComorbidities) { _, _ in patient.updatedAt = .now }
            .onChange(of: patient.encryptedRemotePsychiatricHistory) { _, _ in patient.updatedAt = .now }
        }
    }
}
