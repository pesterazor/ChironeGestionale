import SwiftUI

struct PatientSelectionSummaryView: View {
    @Bindable var patient: Patient
    let openAction: () -> Void

    @State private var birthPlaceSuggestions: [ItalianTaxCode.PlaceSuggestion] = []
    @State private var showBirthPlaceSuggestions = false
    @FocusState private var isBirthPlaceFocused: Bool

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { patient.dateOfBirth ?? .now },
            set: {
                patient.dateOfBirth = $0
                patient.updatedAt = .now
            }
        )
    }

    private var patientAgeLabel: String? {
        guard let birthDate = patient.dateOfBirth else { return nil }
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0
        guard years >= 0 else { return nil }
        return "\(years) anni"
    }

    private var canGenerateTaxCode: Bool {
        ItalianTaxCode.generate(
            firstName: patient.firstName,
            lastName: patient.lastName,
            birthDate: patient.dateOfBirth,
            gender: patient.gender,
            placeOfBirth: patient.placeOfBirth,
            birthProvince: patient.birthProvince
        ) != nil
    }

    private func autoFillTaxCodeIfPossible(force: Bool = false) {
        guard let generated = ItalianTaxCode.generate(
            firstName: patient.firstName,
            lastName: patient.lastName,
            birthDate: patient.dateOfBirth,
            gender: patient.gender,
            placeOfBirth: patient.placeOfBirth,
            birthProvince: patient.birthProvince
        ) else {
            return
        }

        let current = patient.taxCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if force || current.isEmpty {
            patient.taxCode = generated
            patient.updatedAt = .now
        }
    }

    private func refreshBirthPlaceSuggestions() {
        birthPlaceSuggestions = ItalianTaxCode.suggestions(
            for: patient.placeOfBirth,
            province: patient.birthProvince
        )
    }

    private func applyBirthPlaceSuggestion(_ suggestion: ItalianTaxCode.PlaceSuggestion) {
        patient.placeOfBirth = suggestion.name
        patient.birthProvince = suggestion.province
        birthPlaceSuggestions = []
        showBirthPlaceSuggestions = false
        autoFillTaxCodeIfPossible(force: true)
        patient.updatedAt = .now
    }

    private func syncResidenceLegacy() {
        let parts = [
            patient.residenceAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            patient.residenceCity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            patient.residenceProvince?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ]
        .filter { !$0.isEmpty }

        patient.residence = parts.joined(separator: ", ")
    }

    private func hydrateResidenceFieldsIfNeeded() {
        guard (patient.residenceAddress ?? "").isEmpty,
              (patient.residenceCity ?? "").isEmpty,
              (patient.residenceProvince ?? "").isEmpty,
              !patient.residence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let chunks = patient.residence.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let first = chunks.first, !first.isEmpty {
            patient.residenceAddress = first
        }
        if chunks.count > 1, !chunks[1].isEmpty {
            patient.residenceCity = chunks[1]
        }
        if chunks.count > 2, !chunks[2].isEmpty {
            patient.residenceProvince = String(chunks[2].prefix(2)).uppercased()
        }
    }

    private func demographicTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(patient.fullName)
                            .font(.title2)
                            .fontWeight(.semibold)

                        if !patient.readablePrimaryDiagnosis.isEmpty {
                            Label(patient.readablePrimaryDiagnosis, systemImage: "cross.case")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(action: openAction) {
                        Label("Apri cartella clinica", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("open_patient_clinical_button")
                }

                if !patient.hasRequiredDemographics {
                    Label("Completa nome, cognome e data di nascita (campi obbligatori)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Nome *")
                                TextField("", text: $patient.firstName, prompt: Text("Nome"))
                                    .onChange(of: patient.firstName) { _, _ in
                                        patient.updatedAt = .now
                                        autoFillTaxCodeIfPossible()
                                    }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Cognome *")
                                TextField("", text: $patient.lastName, prompt: Text("Cognome"))
                                    .onChange(of: patient.lastName) { _, _ in
                                        patient.updatedAt = .now
                                        autoFillTaxCodeIfPossible()
                                    }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Data di nascita *")
                                HStack(spacing: 8) {
                                    DatePicker("", selection: birthDateBinding, displayedComponents: .date)
                                        .labelsHidden()
                                        .fixedSize(horizontal: true, vertical: false)
                                        .onChange(of: patient.dateOfBirth) { _, _ in
                                            autoFillTaxCodeIfPossible()
                                        }

                                    if let patientAgeLabel {
                                        Text(patientAgeLabel)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule()
                                                    .fill(Color.secondary.opacity(0.12))
                                            )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: 260, alignment: .leading)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Genere")
                                    .frame(width: 280, alignment: .leading)
                                Picker("", selection: Binding(
                                    get: { patient.gender ?? "" },
                                    set: { patient.gender = $0.isEmpty ? nil : $0 }
                                )) {
                                    Text("Maschio").tag("Maschio")
                                    Text("Femmina").tag("Femmina")
                                    Text("Altro").tag("Altro")
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 280, alignment: .leading)
                                .onChange(of: patient.gender) { _, _ in
                                    patient.updatedAt = .now
                                    autoFillTaxCodeIfPossible()
                                }
                            }
                            .frame(width: 280, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Codice fiscale")
                                HStack(spacing: 8) {
                                    TextField("", text: $patient.taxCode, prompt: Text("Codice fiscale"))
                                        .onChange(of: patient.taxCode) { _, _ in patient.updatedAt = .now }

                                    Button("Ricalcola") {
                                        autoFillTaxCodeIfPossible(force: true)
                                    }
                                    .disabled(!canGenerateTaxCode)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Luogo di nascita")
                                TextField("", text: $patient.placeOfBirth, prompt: Text("Es. Torino"))
                                    .focused($isBirthPlaceFocused)
                                    .onChange(of: patient.placeOfBirth) { _, _ in
                                        patient.updatedAt = .now
                                        refreshBirthPlaceSuggestions()
                                        showBirthPlaceSuggestions = true
                                        autoFillTaxCodeIfPossible()
                                    }
                                    .onSubmit {
                                        showBirthPlaceSuggestions = false
                                    }
                                    .onChange(of: isBirthPlaceFocused) { _, focused in
                                        if !focused {
                                            showBirthPlaceSuggestions = false
                                        }
                                    }

                                if showBirthPlaceSuggestions && isBirthPlaceFocused && !birthPlaceSuggestions.isEmpty && !patient.placeOfBirth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(birthPlaceSuggestions) { suggestion in
                                            Button {
                                                applyBirthPlaceSuggestion(suggestion)
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
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(nsColor: .controlBackgroundColor))
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Provincia")
                                TextField("", text: Binding(
                                    get: { patient.birthProvince ?? "" },
                                    set: { patient.birthProvince = $0.isEmpty ? nil : String($0.prefix(2)).uppercased() }
                                ), prompt: Text("TO"))
                                .onChange(of: patient.birthProvince) { _, _ in
                                    patient.updatedAt = .now
                                    autoFillTaxCodeIfPossible()
                                }
                            }
                            .frame(width: 90)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Indirizzo")
                                TextField("", text: Binding(
                                    get: { patient.residenceAddress ?? "" },
                                    set: { patient.residenceAddress = $0.isEmpty ? nil : $0 }
                                ), prompt: Text("Via/Piazza e numero civico"))
                                .onChange(of: patient.residenceAddress) { _, _ in
                                    patient.updatedAt = .now
                                    syncResidenceLegacy()
                                }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Città")
                                TextField("", text: Binding(
                                    get: { patient.residenceCity ?? "" },
                                    set: { patient.residenceCity = $0.isEmpty ? nil : $0 }
                                ), prompt: Text("Città"))
                                .onChange(of: patient.residenceCity) { _, _ in
                                    patient.updatedAt = .now
                                    syncResidenceLegacy()
                                }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Provincia")
                                TextField("", text: Binding(
                                    get: { patient.residenceProvince ?? "" },
                                    set: { patient.residenceProvince = $0.isEmpty ? nil : String($0.prefix(2)).uppercased() }
                                ), prompt: Text("TO"))
                                .onChange(of: patient.residenceProvince) { _, _ in
                                    patient.updatedAt = .now
                                    syncResidenceLegacy()
                                }
                            }
                            .frame(width: 90)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Telefono")
                                TextField("", text: $patient.phoneNumber, prompt: Text("Numero di telefono"))
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Emergenza")
                                TextField("", text: $patient.emergencyContact, prompt: Text("Contatto di emergenza"))
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Esenzioni")
                                TextField("", text: $patient.exemptions, prompt: Text("Esenzioni"))
                                    .onChange(of: patient.exemptions) { _, _ in patient.updatedAt = .now }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Medico di famiglia (MMG)")
                                TextField("", text: $patient.generalPractitioner, prompt: Text("MMG"))
                                    .onChange(of: patient.generalPractitioner) { _, _ in patient.updatedAt = .now }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("CSM di riferimento")
                                TextField("", text: $patient.referenceCSM, prompt: Text("CSM"))
                                    .onChange(of: patient.referenceCSM) { _, _ in patient.updatedAt = .now }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Curante di riferimento")
                                TextField("", text: $patient.referringClinician, prompt: Text("Curante"))
                                    .onChange(of: patient.referringClinician) { _, _ in patient.updatedAt = .now }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Diagnosi principale")
                                TextField(
                                    "",
                                    text: Binding(
                                        get: { patient.readablePrimaryDiagnosis },
                                        set: { patient.protectPrimaryDiagnosis($0) }
                                    ),
                                    prompt: Text("Diagnosi principale")
                                )
                                .onChange(of: patient.primaryDiagnosis) { _, _ in patient.updatedAt = .now }
                                .onChange(of: patient.encryptedPrimaryDiagnosis) { _, _ in patient.updatedAt = .now }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Diagnosi secondaria")
                                TextField(
                                    "",
                                    text: Binding(
                                        get: { patient.readableSecondaryDiagnosis },
                                        set: { patient.protectSecondaryDiagnosis($0) }
                                    ),
                                    prompt: Text("Diagnosi secondaria")
                                )
                                .onChange(of: patient.secondaryDiagnosis) { _, _ in patient.updatedAt = .now }
                                .onChange(of: patient.encryptedSecondaryDiagnosis) { _, _ in patient.updatedAt = .now }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                demographicTitle("Privacy")
                                Toggle("Consenso firmato", isOn: $patient.privacyConsentSigned)
                                    .toggleStyle(.switch)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Spacer(minLength: 0)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                    .clipped()
                } label: {
                    Label("Anagrafica", systemImage: "person.text.rectangle")
                        .font(.headline)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear {
            hydrateResidenceFieldsIfNeeded()
            autoFillTaxCodeIfPossible()
        }
    }
}
