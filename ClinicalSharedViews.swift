import SwiftUI

struct ClinicalAlert: Identifiable, Equatable {
    enum Severity: String {
        case info
        case warning
        case critical
    }

    let id: UUID
    let title: String
    let message: String
    let severity: Severity

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        severity: Severity
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.severity = severity
    }
}

@MainActor
final class ClinicalAlertService {
    static let shared = ClinicalAlertService()

    private init() {}

    func alertsForPatientOpening(_ patient: Patient) -> [ClinicalAlert] {
        var alerts: [ClinicalAlert] = []

        if isOnLithiumTherapy(patient.therapyItems) {
            if let alert = lithiumMonitoringAlert(bloodTestsJSON: patient.bloodTestsTableJSON) {
                alerts.append(alert)
            }
        }

        return alerts
    }

    // MARK: - Lithium monitoring

    private struct LithiumCheck {
        let canonicalTestName: String
        let displayName: String
        let intervalMonths: Int
    }

    private static let lithiumChecks: [LithiumCheck] = [
        LithiumCheck(canonicalTestName: "Litiemia (Li)",     displayName: "Litiemia",        intervalMonths: 6),
        LithiumCheck(canonicalTestName: "Creatinina (Crea)", displayName: "Creatinina/eGFR", intervalMonths: 6),
        LithiumCheck(canonicalTestName: "TSH",               displayName: "TSH",             intervalMonths: 6),
        LithiumCheck(canonicalTestName: "Calcio (Ca)",       displayName: "Calcemia",        intervalMonths: 12),
    ]

    private func isOnLithiumTherapy(_ medications: [TherapyMedication]) -> Bool {
        medications.contains { item in
            guard item.isActive else { return false }
            let normalized = item.medicationName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
            return normalized.contains("litio")
        }
    }

    private func mostRecentDate(forCanonicalName canonicalName: String, in payload: BloodTestsTablePayload) -> Date? {
        let targetKey = BloodTestsDefaults.normalizedName(canonicalName)
        guard let row = payload.rows.first(where: {
            BloodTestsDefaults.normalizedName(BloodTestsDefaults.canonicalName($0.testName)) == targetKey
        }) else { return nil }

        return payload.columns
            .compactMap { column -> Date? in
                let key = column.id.uuidString
                guard
                    let value = row.values[key],
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    let date = BloodTestsSectionViewModel.parsedDate(from: column.dateText)
                else { return nil }
                return date
            }
            .max()
    }

    private func lithiumMonitoringAlert(bloodTestsJSON: String?) -> ClinicalAlert? {
        let payload = BloodTestsSectionViewModel.decodePayload(from: bloodTestsJSON)
        let now = Date.now

        var overdueLines: [String] = []
        for check in Self.lithiumChecks {
            let cutoff = Calendar.current.date(byAdding: .month, value: -check.intervalMonths, to: now) ?? now
            let lastDate = mostRecentDate(forCanonicalName: check.canonicalTestName, in: payload)

            if let last = lastDate {
                guard last < cutoff else { continue }
                let formatted = last.formatted(
                    .dateTime.day().month(.abbreviated).year()
                    .locale(Locale(identifier: "it_IT"))
                )
                overdueLines.append("• \(check.displayName): ultima rilevazione \(formatted)")
            } else {
                overdueLines.append("• \(check.displayName): nessun valore registrato")
            }
        }

        guard !overdueLines.isEmpty else { return nil }

        return ClinicalAlert(
            title: "Controlli periodici litio",
            message: overdueLines.joined(separator: "\n"),
            severity: .warning
        )
    }
}

struct ClinicalSaveFeedback: Equatable {
    let area: String
    let timestamp: Date
}

struct ClinicalSaveFeedbackBanner: View {
    let feedback: ClinicalSaveFeedback

    var body: some View {
        Label {
            Text("\(feedback.area) salvata alle \(feedback.timestamp, format: .dateTime.hour().minute())")
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.15))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("clinical_save_feedback_banner")
    }
}

private enum OrganFunctionStatus: String {
    case green
    case yellow
    case red

    var color: Color {
        switch self {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    var next: OrganFunctionStatus {
        switch self {
        case .green: return .yellow
        case .yellow: return .red
        case .red: return .green
        }
    }

    static func from(_ rawValue: String) -> OrganFunctionStatus {
        OrganFunctionStatus(rawValue: rawValue.lowercased()) ?? .green
    }
}

private struct OrganFunctionIndicatorView: View {
    let title: String
    @Binding var status: String
    let onChange: () -> Void

    private var resolvedStatus: OrganFunctionStatus {
        OrganFunctionStatus.from(status)
    }

    var body: some View {
        Button {
            status = resolvedStatus.next.rawValue
            onChange()
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(resolvedStatus.color)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .strokeBorder(resolvedStatus.color.opacity(0.35), lineWidth: 1)
                    )
                    .accessibilityHidden(true)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44)
        }
        .buttonStyle(.plain)
    }
}

struct OrganFunctionsSummaryView: View {
    @Binding var heartStatus: String
    @Binding var liverStatus: String
    @Binding var kidneyStatus: String
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            OrganFunctionIndicatorView(title: "Cuore", status: $heartStatus, onChange: onChange)
            OrganFunctionIndicatorView(title: "Fegato", status: $liverStatus, onChange: onChange)
            OrganFunctionIndicatorView(title: "Reni", status: $kidneyStatus, onChange: onChange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

struct ClinicalAlertsPanelView: View {
    let alerts: [ClinicalAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(alerts) { alert in
                ClinicalAlertBannerView(alert: alert)
            }
        }
    }
}

private struct ClinicalAlertBannerView: View {
    let alert: ClinicalAlert

    private var accentColor: Color {
        switch alert.severity {
        case .info:     return .blue
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    private var symbolName: String {
        switch alert.severity {
        case .info:     return "info.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accentColor)
                .font(.system(size: 22, weight: .medium))
                .frame(width: 26, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(accentColor.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alert.title). \(alert.message)")
    }
}
