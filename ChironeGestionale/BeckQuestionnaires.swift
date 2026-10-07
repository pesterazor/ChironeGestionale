import Foundation

struct BeckAnswerOption: Identifiable {
    let code: String
    let score: Int
    let text: String
    var id: String { code }
}

struct BeckQuestion {
    let title: String
    let options: [BeckAnswerOption]
}

// Trascrizione dei due PDF forniti dall'utente in "Desktop/Scale e Test".
// Provenienza, edizione e limiti di interpretazione sono documentati in BeckScales.md.
enum BeckQuestionnaires {
    static let baiOptions: [BeckAnswerOption] = [
        .init(code: "0", score: 0, text: "Per niente"),
        .init(code: "1", score: 1, text: "Un po’ — non mi ha infastidito molto"),
        .init(code: "2", score: 2, text: "Abbastanza — era spiacevole ma potevo sopportarlo"),
        .init(code: "3", score: 3, text: "Molto — potevo appena sopportarlo")
    ]

    static let bai: [BeckQuestion] = [
        "Intorpidimento o formicolio",
        "Vampate di calore",
        "Gambe vacillanti",
        "Incapacità a rilassarsi",
        "Paura che qualcosa di molto brutto possa accadere",
        "Vertigini o sensazioni di stordimento",
        "Batticuore",
        "Barcollare",
        "Sensazione di terrore",
        "Sentirsi tesi/inquieti",
        "Sensazione di soffocamento",
        "Mani che tremano",
        "Agitarsi nervosamente",
        "Paura di perdere il controllo",
        "Respiro affannoso",
        "Paura di morire",
        "Sentirsi impauriti",
        "Disturbi digestivi o di stomaco",
        "Sentirsi svenire",
        "Sentirsi arrossire",
        "Sentirsi sudati (non per il caldo)"
    ].map { BeckQuestion(title: $0, options: baiOptions) }

    static let bdiII: [BeckQuestion] = [
        item("Tristezza", [
            "Non mi sento triste.",
            "Mi sento triste per la maggior parte del tempo.",
            "Mi sento sempre triste.",
            "Mi sento così triste o infelice da non poterlo sopportare."
        ]),
        item("Pessimismo", [
            "Non sono scoraggiato riguardo al mio futuro.",
            "Mi sento più scoraggiato riguardo al mio futuro rispetto al solito.",
            "Non mi aspetto nulla di buono per me.",
            "Sento che il mio futuro è senza speranza e che continuerà a peggiorare."
        ]),
        item("Fallimento", [
            "Non mi sento un fallito.",
            "Ho fallito più di quanto avrei dovuto.",
            "Se ripenso alla mia vita riesco a vedere solo una serie di fallimenti.",
            "Ho la sensazione di essere un fallimento totale come persona."
        ]),
        item("Perdita di piacere", [
            "Traggo lo stesso piacere di sempre dalle cose che faccio.",
            "Non traggo più piacere dalle cose come un tempo.",
            "Traggo molto poco piacere dalle cose che di solito mi divertivano.",
            "Non riesco a trarre alcun piacere dalle cose che una volta mi piacevano."
        ]),
        item("Senso di colpa", [
            "Non mi sento particolarmente in colpa.",
            "Mi sento in colpa per molte cose che ho fatto o che avrei dovuto fare.",
            "Mi sento molto spesso in colpa.",
            "Mi sento sempre in colpa."
        ]),
        item("Sentimenti di punizione", [
            "Non mi sento come se stessi subendo una punizione.",
            "Sento che potrei essere punito.",
            "Mi aspetto di essere punito.",
            "Mi sento come se stessi subendo una punizione."
        ]),
        item("Autostima", [
            "Considero me stesso come ho sempre fatto.",
            "Credo meno in me stesso.",
            "Sono deluso di me stesso.",
            "Mi detesto."
        ]),
        item("Autocritica", [
            "Non mi critico né mi biasimo più del solito.",
            "Mi critico più spesso del solito.",
            "Mi critico per tutte le mie colpe.",
            "Mi biasimo per ogni cosa brutta che mi accade."
        ]),
        item("Suicidio", [
            "Non ho alcun pensiero suicida.",
            "Ho pensieri suicidi ma non li realizzerei.",
            "Sento che starei meglio se morissi.",
            "Se mi si presentasse l’occasione, non esiterei ad uccidermi."
        ]),
        item("Pianto", [
            "Non piango più del solito.",
            "Piango più del solito.",
            "Piango per ogni minima cosa.",
            "Ho spesso voglia di piangere ma non ci riesco."
        ]),
        item("Agitazione", [
            "Non mi sento più agitato o teso del solito.",
            "Mi sento più agitato o teso del solito.",
            "Sono così nervoso o agitato al punto che mi è difficile rimanere fermo.",
            "Sono così nervoso o agitato che devo continuare a muovermi o fare qualcosa."
        ]),
        item("Perdita di interessi", [
            "Non ho perso interesse verso le altre persone o verso le attività.",
            "Sono meno interessato agli altri o alle cose rispetto a prima.",
            "Ho perso la maggior parte dell’interesse verso le altre persone o cose.",
            "Mi risulta difficile interessarmi a qualsiasi cosa."
        ]),
        item("Indecisione", [
            "Prendo decisioni come sempre.",
            "Trovo più difficoltà del solito nel prendere decisioni.",
            "Ho molte più difficoltà nel prendere decisioni rispetto al solito.",
            "Non riesco a prendere nessuna decisione."
        ]),
        item("Senso di inutilità", [
            "Non mi sento inutile.",
            "Non mi sento valido e utile come un tempo.",
            "Mi sento più inutile delle altre persone.",
            "Mi sento completamente inutile, su qualsiasi cosa."
        ]),
        item("Perdita di energia", [
            "Ho la stessa energia di sempre.",
            "Ho meno energia del solito.",
            "Non ho energia sufficiente per fare la maggior parte delle cose.",
            "Ho così poca energia che non riesco a fare nulla."
        ]),
        BeckQuestion(title: "Sonno", options: [
            .init(code: "0", score: 0, text: "Non ho notato alcun cambiamento nel mio modo di dormire."),
            .init(code: "1a", score: 1, text: "Dormo un po’ più del solito."),
            .init(code: "1b", score: 1, text: "Dormo un po’ meno del solito."),
            .init(code: "2a", score: 2, text: "Dormo molto più del solito."),
            .init(code: "2b", score: 2, text: "Dormo molto meno del solito."),
            .init(code: "3a", score: 3, text: "Dormo quasi tutto il giorno."),
            .init(code: "3b", score: 3, text: "Mi sveglio 1-2 ore prima e non riesco a riaddormentarmi.")
        ]),
        item("Irritabilità", [
            "Non sono più irritabile del solito.",
            "Sono più irritabile del solito.",
            "Sono molto più irritabile del solito.",
            "Sono sempre irritabile."
        ]),
        BeckQuestion(title: "Appetito", options: [
            .init(code: "0", score: 0, text: "Non ho notato alcun cambiamento nel mio appetito."),
            .init(code: "1a", score: 1, text: "Il mio appetito è un po’ diminuito rispetto al solito."),
            .init(code: "1b", score: 1, text: "Il mio appetito è un po’ aumentato rispetto al solito."),
            .init(code: "2a", score: 2, text: "Il mio appetito è molto diminuito rispetto al solito."),
            .init(code: "2b", score: 2, text: "Il mio appetito è molto aumentato rispetto al solito."),
            .init(code: "3a", score: 3, text: "Non ho per niente appetito."),
            .init(code: "3b", score: 3, text: "Mangerei in qualsiasi momento.")
        ]),
        item("Concentrazione", [
            "Riesco a concentrarmi come sempre.",
            "Non riesco a concentrarmi come al solito.",
            "Trovo difficile concentrarmi per molto tempo.",
            "Non riesco a concentrarmi su nulla."
        ]),
        item("Fatica", [
            "Non sono più stanco o affaticato del solito.",
            "Mi stanco e mi affatico più facilmente del solito.",
            "Sono così stanco e affaticato che non riesco a fare molte delle cose che facevo prima.",
            "Sono talmente stanco e affaticato che non riesco più a fare nessuna delle cose che facevo prima."
        ]),
        item("Sesso", [
            "Non ho notato alcun cambiamento recente nel mio interesse verso il sesso.",
            "Sono meno interessato al sesso rispetto a prima.",
            "Ora sono molto meno interessante al sesso.",
            "Ho completamente perso l’interesse verso il sesso."
        ])
    ]

    private static func item(_ title: String, _ statements: [String]) -> BeckQuestion {
        BeckQuestion(title: title, options: statements.enumerated().map {
            BeckAnswerOption(code: String($0.offset), score: $0.offset, text: $0.element)
        })
    }
}

extension BeckScale {
    var questions: [BeckQuestion] {
        switch self {
        case .bai: return BeckQuestionnaires.bai
        case .bdiII: return BeckQuestionnaires.bdiII
        }
    }

    var instructions: String {
        switch self {
        case .bai:
            return "Di seguito troverà una lista dei più comuni sintomi legati all’ansia. Per favore, legga attentamente ogni frase e indichi quanto fastidio ciascun sintomo le ha causato nella scorsa settimana (incluso oggi)."
        case .bdiII:
            return "Il presente questionario consiste di 21 gruppi di affermazioni. Per favore legga attentamente le affermazioni di ciascun gruppo. Per ogni gruppo scelga quella che meglio descrive come Lei si è sentito nelle ultime due settimane (incluso oggi). Se più di una affermazione dello stesso gruppo descrive ugualmente bene come Lei si sente, scelga il numero più elevato per quel gruppo. Non scelga più di una affermazione per ciascun gruppo, inclusa la domanda 16 (Sonno) e la domanda 18 (Appetito). È importante che non ci sono risposte giuste o sbagliate. Non si soffermi troppo su ogni affermazione: la prima risposta è spesso la più accurata."
        }
    }

    var timeframeLabel: String {
        self == .bai ? "Ultima settimana, incluso oggi" : "Ultime due settimane, incluso oggi"
    }

    func scores(for answerIndices: [Int]) -> [Int]? {
        guard answerIndices.count == Self.itemCount else { return nil }
        var result: [Int] = []
        for (index, answer) in answerIndices.enumerated() {
            guard questions[index].options.indices.contains(answer) else { return nil }
            result.append(questions[index].options[answer].score)
        }
        return result
    }

    func totalScore(forAnswers answerIndices: [Int]) -> Int? {
        guard let scores = scores(for: answerIndices) else { return nil }
        return Self.totalScore(for: scores)
    }

    // Norme italiane, pagina 2 del modulo BAI fornito, sesta ristampa 2016.
    func italianPercentile(for score: Int) -> Int? {
        guard self == .bai, (0...63).contains(score) else { return nil }
        let upperBoundsAndPercentiles = [
            (0, 10), (1, 20), (2, 30), (3, 40), (6, 50), (7, 60),
            (9, 70), (12, 80), (15, 85), (18, 90), (19, 91), (20, 93),
            (21, 94), (23, 95), (25, 96), (26, 97), (28, 98), (63, 99)
        ]
        return upperBoundsAndPercentiles.first { score <= $0.0 }?.1
    }
}
