import SwiftUI
import Charts

/// Keeps the score and the compact trend together; constructs the full chart only on demand.
struct PsychometricTrendView<Score: View>: View {
    let data: PsychometricTrendData
    let configuration: PsychometricTrendConfiguration
    @ViewBuilder let score: () -> Score
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.m) {
            PsychometricSummaryLayout(spacing: ClinicalSpacing.l) {
                score()
                compact
            }
            .padding(ClinicalSpacing.m)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.12)))

            if data.excludedCount > 0 {
                Label("Valutazioni escluse dall’andamento: \(data.excludedCount). Dati incompleti o non validi; la linea è interrotta in loro corrispondenza.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !data.points.isEmpty {
                DisclosureGroup("Andamento completo", isExpanded: $isExpanded) {
                    if isExpanded {
                        VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
                            PsychometricTrendChart(points: data.points, configuration: configuration, expanded: true)
                            Text(configuration.thresholdsText).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, ClinicalSpacing.s)
                    }
                }
            }
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.s) {
            Text("Ultime \(data.recentPoints.count) valutazioni").font(.subheadline.weight(.medium))
            if data.recentPoints.isEmpty {
                Text("Nessuna valutazione valida").font(.caption).foregroundStyle(.secondary)
            } else {
                PsychometricTrendChart(points: data.recentPoints, configuration: configuration, expanded: false, inspectionPoints: data.points)
            }
            VStack(alignment: .leading, spacing: 4) {
                if data.latestIsInvalid {
                    Text("Ultima valutazione non valida: confronti non disponibili.")
                } else if let delta = data.previousDelta {
                    Text("\(configuration.deltaText(delta)) dalla precedente\(data.previousWasInvalid ? " valida" : "")")
                    if let baseline = data.baselineDelta, let first = data.points.first {
                        Text("\(configuration.deltaText(baseline)) dalla prima · \(PsychometricTrendData.dateText(first.date))")
                            .foregroundStyle(.secondary)
                    }
                } else if !data.points.isEmpty {
                    Text("Prima valutazione")
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }
}

struct PsychometricTrendChart: View {
    let points: [PsychometricTrendPoint]
    let configuration: PsychometricTrendConfiguration
    let expanded: Bool
    var inspectionPoints: [PsychometricTrendPoint]? = nil
    @State private var selectedDate: Date?
    @Environment(\.colorScheme) private var colorScheme

    // Keep Chirone's teal hue, with enough contrast for a thin line on a light surface.
    private var plotColor: Color {
        colorScheme == .dark ? .accentColor : Color.accentColor.mix(with: .black, by: 0.35)
    }

    private var selected: [PsychometricTrendPoint] {
        guard let date = PsychometricTrendData.selection(at: selectedDate, in: points).first?.date else { return [] }
        // Include coincident records even when the twelve-point cutoff falls on this date.
        return (inspectionPoints ?? points).filter { $0.date == date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            chart
                .frame(height: expanded ? 220 : 96)
                .chartXSelection(value: $selectedDate)
                .focusable()
                .onKeyPress(.leftArrow) { moveSelection(-1); return .handled }
                .onKeyPress(.rightArrow) { moveSelection(1); return .handled }
                .onKeyPress(.escape) { selectedDate = nil; return .handled }
                .accessibilityLabel("Andamento \(configuration.label)")
                .accessibilityHint("Usa le frecce sinistra e destra per esplorare le date.")
                .accessibilityValue(selected.map(pointDescription).joined(separator: "; "))
                .accessibilityAdjustableAction { direction in
                    moveSelection(direction == .increment ? 1 : -1)
                }
            HStack {
                if let first = points.first { Text(PsychometricTrendData.dateText(first.date)) }
                Spacer(minLength: 8)
                if let last = points.last, last.date != points.first?.date { Text(PsychometricTrendData.dateText(last.date)) }
            }
            .font(.caption2).foregroundStyle(.secondary)
            if !selected.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(selected) { point in
                        Text(pointDescription(point)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.caption)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                .accessibilityElement(children: .combine)
            }
        }
        .onChange(of: points) { _, _ in selectedDate = nil }
    }

    private var chart: some View {
        Chart {
            if expanded {
                ForEach(configuration.thresholds, id: \.self) { threshold in
                    RuleMark(y: .value("Soglia", threshold))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .accessibilityLabel("Soglia \(threshold)")
                }
            }
            ForEach(points) { point in
                LineMark(x: .value("Data", point.date), y: .value(configuration.label, point.value), series: .value("Intervallo", point.segment))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(plotColor)
                    .accessibilityHidden(true)
                PointMark(x: .value("Data", point.date), y: .value(configuration.label, point.value))
                    .symbolSize(point.id == points.last?.id ? 48 : 20)
                    .foregroundStyle(plotColor)
                    .accessibilityLabel(pointDescription(point))
            }
            if let point = selected.first {
                RuleMark(x: .value("Selezione", point.date))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .accessibilityHidden(true)
            }
        }
        .chartYScale(domain: 0...configuration.maximum, range: .plotDimension(padding: 4))
        .chartXScale(domain: PsychometricTrendData.domain(for: points), range: .plotDimension(padding: 5))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: expanded ? [0] + configuration.thresholds + [configuration.maximum] : [0, configuration.maximum]) {
                AxisValueLabel()
            }
        }
        .chartLegend(.hidden)
    }

    private func pointDescription(_ point: PsychometricTrendPoint) -> String {
        "\(PsychometricTrendData.dateText(point.date)) · \(point.value) \(configuration.countsSymptoms ? "sintomi" : "punti") · \(point.record.classification)"
    }

    private func moveSelection(_ step: Int) {
        selectedDate = PsychometricTrendData.nextSelection(after: selectedDate, step: step, in: points)
    }
}

struct PsychometricLatestScore: View {
    let record: PsychometricTrendRecord
    let configuration: PsychometricTrendConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: ClinicalSpacing.xs) {
            Text("Ultima valutazione").font(.caption).foregroundStyle(.secondary)
            Text(PsychometricTrendData.dateText(record.date)).font(.caption).foregroundStyle(.secondary)
            if let score = record.score {
                if configuration.countsSymptoms {
                    Text("Sintomi · Parte 1").font(.subheadline.weight(.medium))
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(score)").font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("/ \(configuration.maximum)").font(.title3).foregroundStyle(.secondary)
                }
                if !configuration.countsSymptoms {
                    Text(record.classification).font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label("Punteggi incompleti o non validi", systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Proposes a real column width before measuring wrapping text and clinical notices.
/// ViewThatFits would instead measure their unwrapped ideal width and stack too early.
struct PsychometricSummaryLayout: Layout {
    let spacing: CGFloat

    private func columns(_ width: CGFloat) -> (score: CGFloat, chart: CGFloat)? {
        guard width >= 220 + 260 + spacing else { return nil }
        let score = max(220, (width - spacing) * 0.45)
        return (score, width - spacing - score)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        if let widths = columns(width) {
            let left = subviews[0].sizeThatFits(ProposedViewSize(width: widths.score, height: nil))
            let right = subviews[1].sizeThatFits(ProposedViewSize(width: widths.chart, height: nil))
            return CGSize(width: width, height: max(left.height, right.height))
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if let widths = columns(bounds.width) {
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: widths.score, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX + widths.score + spacing, y: bounds.minY), proposal: ProposedViewSize(width: widths.chart, height: nil))
        } else {
            var y = bounds.minY
            for view in subviews {
                let proposal = ProposedViewSize(width: bounds.width, height: nil)
                view.place(at: CGPoint(x: bounds.minX, y: y), proposal: proposal)
                y += view.sizeThatFits(proposal).height + spacing
            }
        }
    }
}
