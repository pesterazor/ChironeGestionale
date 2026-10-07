import SwiftUI
import SwiftData
import Foundation

enum PHQ9Severity: String, Sendable {
    case minimal
    case mild
    case moderate
    case moderatelySevere
    case severe

    var label: String {
        switch self {
        case .minimal: return "Minimale"
        case .mild: return "Lieve"
        case .moderate: return "Moderata"
        case .moderatelySevere: return "Moderatamente grave"
        case .severe: return "Grave"
        }
    }

    var scoreRange: String {
        switch self {
        case .minimal: return "0–4"
        case .mild: return "5–9"
        case .moderate: return "10–14"
        case .moderatelySevere: return "15–19"
        case .severe: return "20–27"
        }
    }

    var color: Color {
        switch self {
        case .minimal: return .green
        case .mild: return Color(hue: 0.14, saturation: 0.85, brightness: 0.80)
        case .moderate: return .orange
        case .moderatelySevere: return Color(hue: 0.05, saturation: 0.90, brightness: 0.82)
        case .severe: return .red
        }
    }

    static func from(score: Int) -> PHQ9Severity {
        switch score {
        case ..<5: return .minimal
        case 5..<10: return .mild
        case 10..<15: return .moderate
        case 15..<20: return .moderatelySevere
        default: return .severe
        }
    }
}

enum PHQ9 {
    static let questions: [String] = [
        "Scarso interesse o piacere nel fare le cose",
        "Sentirsi giù, depresso o senza speranza",
        "Difficoltà ad addormentarsi, a mantenere il sonno, oppure dormire troppo",
        "Sentirsi stanchi o con poca energia",
        "Scarso appetito o eccesso nel mangiare",
        "Sentirsi un fallimento o provare senso di colpa",
        "Difficoltà a concentrarsi, ad esempio nel leggere o guardare la televisione",
        "Muoversi o parlare così lentamente da essere notato, oppure essere così agitato da non riuscire a stare fermo",
        "Pensieri di essere meglio morti o di farsi del male in qualche modo"
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
final class PHQ9Assessment {
    var id: UUID
    var date: Date
    var scores: [Int]
    var createdAt: Date
    var patient: Patient?

    init(date: Date = .now, scores: [Int] = Array(repeating: 0, count: 9), patient: Patient? = nil) {
        self.id = UUID()
        self.date = date
        self.scores = scores
        self.createdAt = .now
        self.patient = patient
    }

    var totalScore: Int {
        guard scores.count == 9 else { return 0 }
        return scores.reduce(0, +)
    }

    var severity: PHQ9Severity {
        PHQ9Severity.from(score: totalScore)
    }
}
