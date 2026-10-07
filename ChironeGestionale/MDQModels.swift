import SwiftUI
import SwiftData
import Foundation

// Criteri di screening positivo MDQ (Hirschfeld et al., 2000):
// Criterio A: ≥7 risposte Sì nella Parte 1
// Criterio B: Sì nella Parte 2 (sintomi in co-occorrenza)
// Criterio C: impatto moderato o grave nella Parte 3
// Screening POSITIVO = A && B && C

enum MDQImpact: Int, CaseIterable, Identifiable {
    case none = 0
    case minimal = 1
    case moderate = 2
    case severe = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "Per niente"
        case .minimal: return "Minimamente"
        case .moderate: return "Moderatamente"
        case .severe: return "Gravemente"
        }
    }

    var meetsCriterion: Bool { self >= .moderate }
}

extension MDQImpact: Comparable {
    static func < (lhs: MDQImpact, rhs: MDQImpact) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum MDQ {
    static let part1Prefix = "C'è mai stato un periodo della sua vita in cui…"

    static let part1Questions: [String] = [
        "…si sentiva così bene o così su di giri da essere notato dagli altri, oppure era così irritabile da litigare o fare scenate?",
        "…aveva bisogno di meno sonno del solito, ma si sentiva ugualmente riposato?",
        "…parlava più velocemente del solito o in modo talmente rapido da non riuscire a fermarsi?",
        "…i pensieri le correvano nella testa così velocemente che non riusciva a rallentarli?",
        "…si distraeva così facilmente da avere difficoltà a concentrarsi o a portare a termine quello che stava facendo?",
        "…era molto più attivo del solito (al lavoro, a scuola, socialmente o sessualmente)?",
        "…era così pieno di energia o vivace da sembrare un motore che gira a tutto gas?",
        "…era molto più sicuro di sé del solito?",
        "…dormiva molto meno del solito senza sentirsi stanco?",
        "…era molto più loquace del solito o aveva più voglia di socializzare?",
        "…era più interessato al sesso del solito?",
        "…faceva cose insolite, o che apparivano sciocche o rischiose agli altri?",
        "…spendeva soldi in modo da creare problemi a sé stesso o alla sua famiglia?"
    ]

    static let part2Question = "Se ha risposto Sì a una o più domande, ha avuto più di uno di questi comportamenti nello stesso periodo di tempo?"
    static let part3Question = "Se sì, quanto hanno interferito questi comportamenti con la sua vita (lavorativa, familiare, sociale) o hanno causato problemi legali od economici?"
}

@Model
final class MDQAssessment {
    var id: UUID
    var date: Date
    // Stored as Int (0=No, 1=Sì) for SwiftData compatibility with primitive arrays
    var part1Answers: [Int]
    var part2Answer: Bool
    var part3RawValue: Int
    var createdAt: Date
    var patient: Patient?

    init(
        date: Date = .now,
        part1Answers: [Int] = Array(repeating: 0, count: 13),
        part2Answer: Bool = false,
        part3RawValue: Int = 0,
        patient: Patient? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.part1Answers = part1Answers
        self.part2Answer = part2Answer
        self.part3RawValue = part3RawValue
        self.createdAt = .now
        self.patient = patient
    }

    var part1YesCount: Int {
        part1Answers.filter { $0 == 1 }.count
    }

    var impact: MDQImpact {
        MDQImpact(rawValue: part3RawValue) ?? .none
    }

    var criterionA: Bool { part1YesCount >= 7 }
    var criterionB: Bool { part2Answer }
    var criterionC: Bool { impact.meetsCriterion }

    var isScreenPositive: Bool { criterionA && criterionB && criterionC }
}
