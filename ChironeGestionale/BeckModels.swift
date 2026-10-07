import Foundation
import SwiftData
import SwiftUI

// Calcolo dei punteggi dei moduli italiani forniti dall'utente.
enum BeckScale: String, CaseIterable, Identifiable, Sendable {
    case bai
    case bdiII

    var id: String { rawValue }

    static let itemCount = 21
    static let maximumScore = 63

    var label: String {
        switch self {
        case .bai: return "BAI"
        case .bdiII: return "BDI-II"
        }
    }

    var fullName: String {
        switch self {
        case .bai: return "Beck Anxiety Inventory"
        case .bdiII: return "Beck Depression Inventory – II"
        }
    }

    var summary: String {
        switch self {
        case .bai: return "Valutazione della sintomatologia ansiosa negli adulti."
        case .bdiII: return "Valutazione della sintomatologia depressiva dai 13 anni di età. Seconda edizione."
        }
    }

    var publisherURL: URL {
        switch self {
        case .bai: return URL(string: "https://www.giuntipsy.it/bai")!
        case .bdiII: return URL(string: "https://www.giuntipsy.it/bdi-2")!
        }
    }

    // Fasce descrittive convenzionali del punteggio grezzo, non percentili
    // della taratura italiana. Fonti e limiti: BeckScales.md.
    var severityBands: [(severity: BeckSeverity, range: ClosedRange<Int>)] {
        switch self {
        case .bai:
            return [(.minimal, 0...7), (.mild, 8...15), (.moderate, 16...25), (.severe, 26...63)]
        case .bdiII:
            return [(.minimal, 0...13), (.mild, 14...19), (.moderate, 20...28), (.severe, 29...63)]
        }
    }

    var thresholdsText: String {
        severityBands.map { "\($0.range.lowerBound)–\($0.range.upperBound) \($0.severity.label)" }
            .joined(separator: " · ")
    }

    func severity(for score: Int) -> BeckSeverity? {
        severityBands.first { $0.range.contains(score) }?.severity
    }

    static func totalScore(for scores: [Int]) -> Int? {
        guard scores.count == itemCount, scores.allSatisfy({ (0...3).contains($0) }) else { return nil }
        return scores.reduce(0, +)
    }

    func requiresClinicalReview(answerIndices: [Int]) -> Bool {
        // BDI-II, item 9: segnale da approfondire indipendentemente dal totale.
        self == .bdiII && answerIndices.indices.contains(8) && (1...3).contains(answerIndices[8])
    }
}

enum BeckSeverity: String, Sendable {
    case minimal, mild, moderate, severe

    var label: String {
        switch self {
        case .minimal: return "Minima"
        case .mild: return "Lieve"
        case .moderate: return "Moderata"
        case .severe: return "Grave"
        }
    }

    var color: Color {
        switch self {
        case .minimal: return .green
        case .mild: return Color(hue: 0.14, saturation: 0.85, brightness: 0.80)
        case .moderate: return .orange
        case .severe: return .red
        }
    }
}

@Model
final class BeckAssessment {
    var id: UUID
    var scaleRawValue: String
    var date: Date
    // Indici delle opzioni, non punteggi: preservano le varianti 1a/1b, 2a/2b, 3a/3b.
    var answerIndices: [Int]
    var createdAt: Date
    var patient: Patient?

    init(scale: BeckScale, date: Date = .now, answerIndices: [Int], patient: Patient? = nil) {
        self.id = UUID()
        self.scaleRawValue = scale.rawValue
        self.date = date
        self.answerIndices = answerIndices
        self.createdAt = .now
        self.patient = patient
    }

    var scale: BeckScale? { BeckScale(rawValue: scaleRawValue) }

    var scores: [Int]? { scale?.scores(for: answerIndices) }

    var totalScore: Int? {
        scale?.totalScore(forAnswers: answerIndices)
    }

    var severity: BeckSeverity? {
        guard let totalScore else { return nil }
        return scale?.severity(for: totalScore)
    }

    var requiresClinicalReview: Bool {
        scale?.requiresClinicalReview(answerIndices: answerIndices) ?? false
    }

    static func sorted(_ assessments: [BeckAssessment], for scale: BeckScale) -> [BeckAssessment] {
        assessments.filter { $0.scale == scale }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString > $1.id.uuidString
        }
    }
}
