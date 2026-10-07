import SwiftUI
import SwiftData
import Foundation

enum GAD7Severity: String, Sendable {
    case minimal
    case mild
    case moderate
    case severe

    var label: String {
        switch self {
        case .minimal: return "Minima"
        case .mild: return "Lieve"
        case .moderate: return "Moderata"
        case .severe: return "Grave"
        }
    }

    var scoreRange: String {
        switch self {
        case .minimal: return "0–4"
        case .mild: return "5–9"
        case .moderate: return "10–14"
        case .severe: return "15–21"
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

    static func from(score: Int) -> GAD7Severity {
        switch score {
        case ..<5: return .minimal
        case 5..<10: return .mild
        case 10..<15: return .moderate
        default: return .severe
        }
    }
}

enum GAD7 {
    static let questions: [String] = [
        "Sentirsi nervoso, ansioso o sull'orlo di una crisi di nervi",
        "Non riuscire a smettere di preoccuparsi o a controllare le preoccupazioni",
        "Preoccuparsi troppo di cose diverse",
        "Difficoltà a rilassarsi",
        "Essere così agitato da non riuscire a stare fermo",
        "Diventare facilmente irritabile o innervosito",
        "Sentire la paura che possa accadere qualcosa di terribile"
    ]

    static let answerLabels: [String] = [
        "Mai",
        "Alcuni giorni",
        "Più della metà dei giorni",
        "Quasi ogni giorno"
    ]

    static let shortAnswerLabels: [String] = [
        "Mai",
        "Alcuni gg",
        "Metà gg",
        "Quasi ogni gg"
    ]
}

@Model
final class GAD7Assessment {
    var id: UUID
    var date: Date
    var scores: [Int]
    var createdAt: Date
    var patient: Patient?

    init(date: Date = .now, scores: [Int] = Array(repeating: 0, count: 7), patient: Patient? = nil) {
        self.id = UUID()
        self.date = date
        self.scores = scores
        self.createdAt = .now
        self.patient = patient
    }

    var totalScore: Int {
        guard scores.count == 7 else { return 0 }
        return scores.reduce(0, +)
    }

    var severity: GAD7Severity {
        GAD7Severity.from(score: totalScore)
    }
}
