import SwiftUI

struct PatientRowView: View {
    let patient: Patient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(patient.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let lastVisitLabel = patient.lastVisitDateLabel {
                    Text(lastVisitLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if !patient.readablePrimaryDiagnosis.isEmpty {
                    Label(patient.readablePrimaryDiagnosis, systemImage: "cross.case")
                        .lineLimit(1)
                }

                if !patient.phoneNumber.isEmpty {
                    Label(patient.phoneNumber, systemImage: "phone")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
