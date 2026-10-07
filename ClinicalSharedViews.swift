import SwiftUI

enum ClinicalSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}

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
        let payload = BloodTestsSectionViewModel.decodePayload(from: patient.bloodTestsTableJSON)
        var alerts: [ClinicalAlert] = []

        if isOnLithiumTherapy(patient.therapyItems) {
            if let alert = monitoringAlert(title: "Controlli periodici litio",
                                           checks: Self.lithiumMonitoringChecks,
                                           in: payload) { alerts.append(alert) }
        }
        if isOnValproateTherapy(patient.therapyItems) {
            if let alert = monitoringAlert(title: "Controlli periodici acido valproico",
                                           checks: Self.valproateMonitoringChecks,
                                           in: payload) { alerts.append(alert) }
        }
        if isOnClozapineTherapy(patient.therapyItems) {
            if let alert = monitoringAlert(title: "Controlli periodici clozapina",
                                           checks: Self.clozapineMonitoringChecks,
                                           severity: .critical,
                                           in: payload) { alerts.append(alert) }
        }
        if isOnCarbamazepineTherapy(patient.therapyItems) {
            if let alert = monitoringAlert(title: "Controlli periodici carbamazepina",
                                           checks: Self.carbamazepineMonitoringChecks,
                                           in: payload) { alerts.append(alert) }
        }

        return alerts
    }

    // MARK: - Shared infrastructure

    private struct PeriodicBloodTestCheck {
        let canonicalTestName: String
        let displayName: String
        let intervalMonths: Int
    }

    private func normalizedMedicationName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
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

    private func monitoringAlert(
        title: String,
        checks: [PeriodicBloodTestCheck],
        severity: ClinicalAlert.Severity = .warning,
        in payload: BloodTestsTablePayload
    ) -> ClinicalAlert? {
        let now = Date.now
        var overdueLines: [String] = []

        for check in checks {
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
            title: title,
            message: overdueLines.joined(separator: "\n"),
            severity: severity
        )
    }

    // MARK: - Lithium

    private static let lithiumMonitoringChecks: [PeriodicBloodTestCheck] = [
        PeriodicBloodTestCheck(canonicalTestName: "Litiemia (Li)",     displayName: "Litiemia",        intervalMonths: 6),
        PeriodicBloodTestCheck(canonicalTestName: "Creatinina (Crea)", displayName: "Creatinina/eGFR", intervalMonths: 6),
        PeriodicBloodTestCheck(canonicalTestName: "TSH",               displayName: "TSH",             intervalMonths: 6),
        PeriodicBloodTestCheck(canonicalTestName: "Calcio (Ca)",       displayName: "Calcemia",        intervalMonths: 12),
    ]

    private func isOnLithiumTherapy(_ medications: [TherapyMedication]) -> Bool {
        medications.contains { item in
            guard item.isActive else { return false }
            return normalizedMedicationName(item.medicationName).contains("litio")
        }
    }

    // MARK: - Valproate

    private static let valproateMonitoringChecks: [PeriodicBloodTestCheck] = [
        PeriodicBloodTestCheck(canonicalTestName: "Valproatemia (Ac. valproico)", displayName: "Valproatemia",           intervalMonths: 6),
        PeriodicBloodTestCheck(canonicalTestName: "ALT (GPT)",                   displayName: "Transaminasi (ALT/AST)", intervalMonths: 6),
        PeriodicBloodTestCheck(canonicalTestName: "Piastrine (PLT)",             displayName: "Piastrine",              intervalMonths: 6),
        PeriodicBloodTestCheck(canonicalTestName: "Ammonio",                     displayName: "Ammonio",                intervalMonths: 12),
    ]

    private func isOnValproateTherapy(_ medications: [TherapyMedication]) -> Bool {
        medications.contains { item in
            guard item.isActive else { return false }
            return normalizedMedicationName(item.medicationName).contains("valpro")
        }
    }

    // MARK: - Clozapine

    // Intervallo WBC/ANC: 1 mese (≈4 settimane) — programma AIFA fase stabile (>1 anno di terapia).
    // Nelle fasi iniziali il monitoraggio è più frequente e richiede valutazione clinica diretta.
    private static let clozapineMonitoringChecks: [PeriodicBloodTestCheck] = [
        PeriodicBloodTestCheck(canonicalTestName: "Leucociti (WBC)",    displayName: "Emocromo (WBC/ANC)", intervalMonths: 1),
        PeriodicBloodTestCheck(canonicalTestName: "Clozapinemia (Clo)", displayName: "Clozapinemia",       intervalMonths: 6),
        PeriodicBloodTestCheck(canonicalTestName: "Glucosio",           displayName: "Glucosio",           intervalMonths: 6),
        PeriodicBloodTestCheck(canonicalTestName: "Trigliceridi",       displayName: "Trigliceridi",       intervalMonths: 6),
    ]

    private func isOnClozapineTherapy(_ medications: [TherapyMedication]) -> Bool {
        medications.contains { item in
            guard item.isActive else { return false }
            let n = normalizedMedicationName(item.medicationName)
            return n.contains("clozap") || n.contains("leponex")
        }
    }

    // MARK: - Carbamazepine

    private static let carbamazepineMonitoringChecks: [PeriodicBloodTestCheck] = [
        PeriodicBloodTestCheck(canonicalTestName: "Carbamazepinemia (Car)", displayName: "Carbamazepinemia",       intervalMonths: 6),
        PeriodicBloodTestCheck(canonicalTestName: "Leucociti (WBC)",        displayName: "Emocromo (WBC)",         intervalMonths: 6),
        PeriodicBloodTestCheck(canonicalTestName: "ALT (GPT)",              displayName: "Transaminasi (ALT/AST)", intervalMonths: 6),
        PeriodicBloodTestCheck(canonicalTestName: "Sodio (Na)",             displayName: "Sodio",                  intervalMonths: 6),
    ]

    private func isOnCarbamazepineTherapy(_ medications: [TherapyMedication]) -> Bool {
        medications.contains { item in
            guard item.isActive else { return false }
            let n = normalizedMedicationName(item.medicationName)
            return n.contains("carbamazep") || n.contains("tegretol")
        }
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
        .padding(.horizontal, ClinicalSpacing.s + 2)
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
        case .green:  return .green
        case .yellow: return .yellow
        case .red:    return .red
        }
    }

    // SF Symbol provides redundant semantic encoding for colorblind users
    var symbolName: String {
        switch self {
        case .green:  return "checkmark"
        case .yellow: return "exclamationmark"
        case .red:    return "xmark"
        }
    }

    var next: OrganFunctionStatus {
        switch self {
        case .green:  return .yellow
        case .yellow: return .red
        case .red:    return .green
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
    /// When true, renders as a compact horizontal [dot + label] pill suitable for the section header bar.
    var compact: Bool = false
    /// When true, the label uses white so it's legible on a colored header background.
    var onColoredBackground: Bool = false

    @State private var isHovered = false

    private var resolvedStatus: OrganFunctionStatus {
        OrganFunctionStatus.from(status)
    }

    var body: some View {
        Button {
            status = resolvedStatus.next.rawValue
            onChange()
        } label: {
            if compact {
                // Horizontal pill: [colored dot] [organ name] — no extra vertical space
                HStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(resolvedStatus.color)
                            .frame(width: 10, height: 10)
                        Image(systemName: resolvedStatus.symbolName)
                            .font(.system(size: 5.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: resolvedStatus.color.opacity(isHovered ? 0.4 : 0), radius: 3)

                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(onColoredBackground ? Color.white.opacity(0.85) : Color.secondary)
                }
            } else {
                // Full vertical layout: large circle above organ name
                VStack(spacing: ClinicalSpacing.xs) {
                    ZStack {
                        Circle()
                            .fill(resolvedStatus.color.opacity(isHovered ? 0.9 : 0.78))
                            .frame(width: 32, height: 32)
                        Image(systemName: resolvedStatus.symbolName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .overlay(
                        Circle().strokeBorder(resolvedStatus.color.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: resolvedStatus.color.opacity(isHovered ? 0.3 : 0), radius: 5)

                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
                .frame(minWidth: 44)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help("Funzione \(title.lowercased()): \(resolvedStatus.rawValue). Clicca per cambiare.")
    }
}

struct OrganFunctionsSummaryView: View {
    @Binding var heartStatus: String
    @Binding var liverStatus: String
    @Binding var kidneyStatus: String
    let onChange: () -> Void
    var showBackground: Bool = true
    var compact: Bool = false
    var onColoredBackground: Bool = false

    var body: some View {
        HStack(spacing: compact ? ClinicalSpacing.m : ClinicalSpacing.s + 2) {
            OrganFunctionIndicatorView(
                title: "Cuore",  status: $heartStatus,  onChange: onChange,
                compact: compact, onColoredBackground: onColoredBackground
            )
            OrganFunctionIndicatorView(
                title: "Fegato", status: $liverStatus,  onChange: onChange,
                compact: compact, onColoredBackground: onColoredBackground
            )
            OrganFunctionIndicatorView(
                title: "Reni",   status: $kidneyStatus, onChange: onChange,
                compact: compact, onColoredBackground: onColoredBackground
            )
        }
        .padding(.horizontal, showBackground ? ClinicalSpacing.s + 2 : 0)
        .padding(.vertical, showBackground ? 6 : 0)
        .background {
            if showBackground {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
        }
        .overlay {
            if showBackground {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.secondary.opacity(0.15))
            }
        }
    }
}

struct ClinicalAlertsPanelView: View {
    let alerts: [ClinicalAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
            ForEach(alerts) { alert in
                ClinicalAlertBannerView(alert: alert)
            }
        }
    }
}

private struct ClinicalAlertBannerView: View {
    let alert: ClinicalAlert

    @Environment(\.colorScheme) private var colorScheme

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

    private var iconColor: Color {
        switch alert.severity {
        case .info:     return .blue
        case .warning:  return .yellow
        case .critical: return .red
        }
    }

    // Critical alerts get a heavier border to differentiate without relying on color alone
    private var borderWidth: CGFloat {
        alert.severity == .critical ? 1.5 : 1.0
    }

    /// Derives a color keeping the hue and saturation intact while scaling brightness.
    /// This avoids the "muddy brown" effect that opacity mixing produces on dark backgrounds
    /// (opacity blending over near-black desaturates warm colors like orange → brown).
    private func hsb(satFactor: CGFloat, brightFactor: CGFloat) -> Color {
        guard let ns = NSColor(accentColor).usingColorSpace(.deviceRGB) else { return accentColor }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(
            hue: Double(h),
            saturation: Double(min(s * satFactor, 1)),
            brightness: Double(min(b * brightFactor, 1)),
            opacity: 1.0
        )
    }

    // Light mode: light tint via opacity (works on white background).
    // Dark mode: solid HSB-derived fill — high saturation, reduced brightness — so
    // orange stays orange (not brown), red stays red, blue stays blue.
    private var fillColor: Color {
        colorScheme == .dark ? hsb(satFactor: 0.90, brightFactor: 0.62) : accentColor.opacity(0.12)
    }

    private var borderColor: Color {
        colorScheme == .dark ? hsb(satFactor: 0.82, brightFactor: 0.92) : accentColor.opacity(0.45)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
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
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alert.title). \(alert.message)")
    }
}

// MARK: - Reusable clinical layout primitives

struct ClinicalSectionBox<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    /// In dark mode, derives a less saturated and dimmer variant of the accent color
    /// so the header doesn't feel too vivid against a dark background.
    /// Formula: saturation × 0.70, brightness × 0.75 (HSB space).
    private var resolvedHeaderColor: Color {
        guard colorScheme == .dark else { return accentColor }
        guard let ns = NSColor(accentColor).usingColorSpace(.deviceRGB) else { return accentColor }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(s * 0.70), brightness: Double(b * 0.75), opacity: Double(a))
    }

    /// Standard init — no trailing accessory in the header.
    init(
        _ title: String,
        systemImage: String,
        accentColor: Color = Color.accentColor,
        @ViewBuilder content: @escaping () -> Content
    ) where Accessory == EmptyView {
        self.title = title
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.accessory = { EmptyView() }
        self.content = content
    }

    /// Extended init — trailing accessory slot in the header bar (e.g. organ-status indicators).
    init(
        _ title: String,
        systemImage: String,
        accentColor: Color = Color.accentColor,
        @ViewBuilder accessory: @escaping () -> Accessory,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar with colored background — icon and title in white for legibility
            HStack(spacing: ClinicalSpacing.s - 1) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: ClinicalSpacing.s)
                accessory()
            }
            .padding(.horizontal, ClinicalSpacing.m)
            .padding(.vertical, ClinicalSpacing.s + 2)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 12,
                    style: .continuous
                )
                .fill(resolvedHeaderColor)
            )

            content()
                .padding(ClinicalSpacing.m)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(resolvedHeaderColor.opacity(colorScheme == .dark ? 0.35 : 0.2), lineWidth: 1)
        )
    }
}

struct LabeledClinicalField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ClinicalTextArea: View {
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, ClinicalSpacing.xs)
                .padding(.vertical, 6)
        }
        .frame(minHeight: 110)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.25))
        )
    }
}
