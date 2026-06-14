import SwiftUI

struct QuickClinicalCaptureSheet: View {
    let patientFullName: String
    @Binding var quickCaptureText: String
    @Binding var quickCaptureDate: Date
    @Binding var quickCaptureWellbeing: Int
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Capture Clinico")
                .font(.title3.weight(.semibold))

            Text("Paziente: \(patientFullName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))

                TextEditor(text: $quickCaptureText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
            }
            .frame(minHeight: 140)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.25))
            )

            HStack(spacing: 12) {
                DatePicker(
                    "Data e ora",
                    selection: $quickCaptureDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)

                Stepper(value: $quickCaptureWellbeing, in: 1...10) {
                    Text("Benessere \(quickCaptureWellbeing)/10")
                        .monospacedDigit()
                }
                .frame(minWidth: 170)
            }

            HStack {
                Spacer()

                Button("Annulla") {
                    onCancel()
                }

                Button("Salva nota") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(quickCaptureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 340)
    }
}
