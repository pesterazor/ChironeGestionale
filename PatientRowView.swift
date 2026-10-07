import SwiftUI

struct PatientRowView: View {
    let patient: Patient

    private var initials: String {
        let f = patient.firstName.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        let l = patient.lastName.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        return (f + l).uppercased()
    }

    var body: some View {
        let primaryDiagnosis = patient.readablePrimaryDiagnosis
        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                Text(initials)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(patient.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let lastVisitLabel = patient.lastVisitDateLabel {
                        Text(lastVisitLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    if !primaryDiagnosis.isEmpty {
                        Label(primaryDiagnosis, systemImage: "cross.case")
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
        }
        .padding(.vertical, 3)
    }
}
