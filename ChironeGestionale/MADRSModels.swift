import Foundation
import SwiftData
import SwiftUI

enum MADRSSeverity: String, CaseIterable {
    case minimal, mild, moderate, severe

    var label: String {
        switch self {
        case .minimal: return "Assente/minima"
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

    static func from(score: Int) -> MADRSSeverity? {
        switch score {
        case 0...6: return .minimal
        case 7...19: return .mild
        case 20...34: return .moderate
        case 35...60: return .severe
        default: return nil
        }
    }
}

enum MADRS {
    static let itemCount = 10
    static let maximumScore = 60
    static let fullName = "Montgomery–Åsberg Depression Rating Scale"
    static let thresholdsText = "0–6 Assente/minima · 7–19 Lieve · 20–34 Moderata · 35–60 Grave"

    static func totalScore(for scores: [Int]) -> Int? {
        guard scores.count == itemCount, scores.allSatisfy({ (0...6).contains($0) }) else { return nil }
        return scores.reduce(0, +)
    }

    static func requiresClinicalReview(scores: [Int]) -> Bool {
        scores.indices.contains(9) && (1...6).contains(scores[9])
    }
}

@Model
final class MADRSAssessment {
    var id: UUID
    var date: Date
    var scores: [Int]
    var raterName: String
    var createdAt: Date
    var patient: Patient?

    init(date: Date = .now, scores: [Int], raterName: String = "", patient: Patient? = nil) {
        self.id = UUID()
        self.date = date
        self.scores = scores
        self.raterName = raterName
        self.createdAt = .now
        self.patient = patient
    }

    var totalScore: Int? { MADRS.totalScore(for: scores) }

    var severity: MADRSSeverity? {
        guard let totalScore else { return nil }
        return MADRSSeverity.from(score: totalScore)
    }

    var requiresClinicalReview: Bool { MADRS.requiresClinicalReview(scores: scores) }
}
