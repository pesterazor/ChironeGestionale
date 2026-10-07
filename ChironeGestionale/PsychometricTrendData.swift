import Foundation

struct PsychometricTrendConfiguration {
    let label: String
    let maximum: Int
    let thresholds: [Int]
    let thresholdsText: String
    var countsSymptoms = false

    static let phq9 = Self(label: "PHQ-9", maximum: 27, thresholds: [5, 10, 15, 20], thresholdsText: "0–4 Minimale · 5–9 Lieve · 10–14 Moderata · 15–19 Moderatamente grave · 20–27 Grave")
    static let gad7 = Self(label: "GAD-7", maximum: 21, thresholds: [5, 10, 15], thresholdsText: "0–4 Minima · 5–9 Lieve · 10–14 Moderata · 15–21 Grave")
    static let madrs = Self(label: "MADRS", maximum: 60, thresholds: [7, 20, 35], thresholdsText: MADRS.thresholdsText)
    static let mdq = Self(label: "Sintomi · Parte 1", maximum: 13, thresholds: [7], thresholdsText: "7 sintomi: soglia del criterio A. L’esito dello screening richiede anche i criteri B e C.", countsSymptoms: true)
    static func beck(_ scale: BeckScale) -> Self {
        Self(label: scale.label, maximum: 63, thresholds: scale.severityBands.dropFirst().map { $0.range.lowerBound }, thresholdsText: scale.thresholdsText)
    }

    func deltaText(_ delta: Int) -> String {
        let sign = delta > 0 ? "+" : delta < 0 ? "−" : ""
        let unit = countsSymptoms ? (abs(delta) == 1 ? "sintomo" : "sintomi") : (abs(delta) == 1 ? "punto" : "punti")
        return "\(sign)\(abs(delta)) \(unit)"
    }
}

struct PsychometricTrendRecord: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let score: Int?
    let classification: String

    init(_ assessment: PHQ9Assessment) {
        id = assessment.id; date = assessment.date
        score = PsychometricResponseValidation.isComplete(assessment.scores, itemCount: 9, range: 0...3) ? assessment.totalScore : nil
        classification = score == nil ? "Non valida" : assessment.severity.label
    }
    init(_ assessment: GAD7Assessment) {
        id = assessment.id; date = assessment.date
        score = PsychometricResponseValidation.isComplete(assessment.scores, itemCount: 7, range: 0...3) ? assessment.totalScore : nil
        classification = score == nil ? "Non valida" : assessment.severity.label
    }
    init(_ assessment: MDQAssessment) {
        id = assessment.id; date = assessment.date
        score = PsychometricResponseValidation.isCompleteMDQ(part1: assessment.part1Answers, part2: assessment.part2Answer ? 1 : 0, part3: assessment.part3RawValue) ? assessment.part1YesCount : nil
        classification = score == nil ? "Non valida" : (assessment.isScreenPositive ? "Screening positivo" : "Screening negativo")
    }
    init(_ assessment: BeckAssessment) {
        id = assessment.id; date = assessment.date
        score = assessment.totalScore; classification = assessment.severity?.label ?? "Non valida"
    }
    init(_ assessment: MADRSAssessment) {
        id = assessment.id; date = assessment.date
        score = assessment.totalScore; classification = assessment.severity?.label ?? "Non valida"
    }
    init(id: UUID = UUID(), date: Date, score: Int?, classification: String = "") {
        self.id = id; self.date = date; self.score = score; self.classification = classification
    }
}

struct PsychometricTrendPoint: Identifiable, Equatable {
    let record: PsychometricTrendRecord
    let value: Int
    // A new series after each invalid record prevents interpolation across missing data.
    let segment: Int
    var id: UUID { record.id }
    var date: Date { record.date }
}

struct PsychometricTrendData {
    let points: [PsychometricTrendPoint]
    let recentPoints: [PsychometricTrendPoint]
    let excludedCount: Int
    let latestIsInvalid: Bool
    let previousDelta: Int?
    let baselineDelta: Int?
    let previousWasInvalid: Bool

    /// Input uses the existing descending date / creation / identifier order.
    init(newestFirst records: [PsychometricTrendRecord], maximum: Int) {
        var valid: [PsychometricTrendPoint] = []
        var segment = 0
        var excluded = 0
        for record in records.reversed() {
            guard let score = record.score, (0...maximum).contains(score), record.date.timeIntervalSinceReferenceDate.isFinite else {
                excluded += 1
                segment += 1
                continue
            }
            valid.append(PsychometricTrendPoint(record: record, value: score, segment: segment))
        }
        points = valid
        recentPoints = Array(valid.suffix(12))
        excludedCount = excluded
        latestIsInvalid = records.first.map { $0.id != valid.last?.id } ?? false
        previousWasInvalid = valid.count >= 2 && valid[valid.count - 2].id != records.dropFirst().first?.id
        if !latestIsInvalid, let last = valid.last, valid.count >= 2 {
            previousDelta = last.value - valid[valid.count - 2].value
            baselineDelta = last.value - valid[0].value
        } else {
            previousDelta = nil
            baselineDelta = nil
        }
    }

    static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT")))
    }

    static func domain(for points: [PsychometricTrendPoint]) -> ClosedRange<Date> {
        let first = points.first?.date ?? Date(timeIntervalSince1970: 0)
        let last = points.last?.date ?? first
        // Pad the axis, never the actual assessment dates (including coincident records).
        return first == last ? first.addingTimeInterval(-43200)...last.addingTimeInterval(43200) : first...last
    }

    static func nextSelection(after date: Date?, step: Int, in points: [PsychometricTrendPoint]) -> Date? {
        let dates = points.map(\.date).reduce(into: [Date]()) { if $0.last != $1 { $0.append($1) } }
        guard !dates.isEmpty else { return nil }
        let current = selection(at: date, in: points).first.flatMap { dates.firstIndex(of: $0.date) }
        let next = current.map { min(max($0 + step, 0), dates.count - 1) } ?? (step > 0 ? 0 : dates.count - 1)
        return dates[next]
    }

    static func selection(at date: Date?, in points: [PsychometricTrendPoint]) -> [PsychometricTrendPoint] {
        guard let date, let nearest = points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) else { return [] }
        return points.filter { $0.date == nearest.date }
    }
}
