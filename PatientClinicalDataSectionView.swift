import SwiftUI

struct PatientClinicalDataSectionView: View {
    @Bindable var patient: Patient
    @State private var showingEncryptionError = false

    var body: some View {
        ClinicalSectionBox("Dati clinici", systemImage: "stethoscope") {
            VStack(alignment: .leading, spacing: ClinicalSpacing.m) {
                HStack(alignment: .top, spacing: ClinicalSpacing.m) {
                    LabeledClinicalField("Diagnosi principale") {
                        TextField("", text: Binding(
                            get: { patient.readablePrimaryDiagnosis },
                            set: { if !patient.protectPrimaryDiagnosis($0) { showingEncryptionError = true } }
                        ), prompt: Text("Diagnosi principale"))
                    }
                    LabeledClinicalField("Diagnosi secondaria") {
                        TextField("", text: Binding(
                            get: { patient.readableSecondaryDiagnosis },
                            set: { if !patient.protectSecondaryDiagnosis($0) { showingEncryptionError = true } }
                        ), prompt: Text("Diagnosi secondaria"))
                    }
                }

                LabeledClinicalField("Allergie") {
                    TextField("", text: Binding(
                        get: { patient.readableAllergies },
                        set: { if !patient.protectAllergies($0) { showingEncryptionError = true } }
                    ), prompt: Text("Allergie"))
                }

                LabeledClinicalField("Comorbidità mediche") {
                    ClinicalTextArea(text: Binding(
                        get: { patient.readableMedicalComorbidities },
                        set: { if !patient.protectMedicalComorbidities($0) { showingEncryptionError = true } }
                    ))
                }

                LabeledClinicalField("Anamnesi psichiatrica remota") {
                    ClinicalTextArea(text: Binding(
                        get: { patient.readableRemotePsychiatricHistory },
                        set: { if !patient.protectRemotePsychiatricHistory($0) { showingEncryptionError = true } }
                    ))
                }
            }
            .textFieldStyle(.roundedBorder)
            .alert("Modifica non salvata", isPresented: $showingEncryptionError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Non è stato possibile cifrare la modifica. Il valore precedente è stato conservato: sblocca il Portachiavi e riprova.")
            }
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
