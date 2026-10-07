import Foundation

struct MADRSQuestion {
    let title: String
    let description: String
    // Il documento descrive le ancore 0, 2, 4 e 6 e lascia liberi i valori intermedi.
    let anchors: [String]

    func answerLabel(for score: Int) -> String {
        guard (0...6).contains(score) else { return "" }
        return score.isMultiple(of: 2)
            ? anchors[score / 2]
            : "Valore intermedio tra \(score - 1) e \(score + 1)"
    }
}

extension MADRS {
    // Trascrizione delle tre immagini incorporate in MADRS.doc, fornito dall'utente.
    // Il secondo item numerato 9 nel documento è l'item 10 (idee di suicidio).
    static let questions: [MADRSQuestion] = [
        .init(
            title: "Tristezza manifesta",
            description: "Scoraggiamento, depressione e disperazione (qualcosa di più di un semplice abbassamento del tono dell’umore) che traspaiono dal linguaggio, dalla mimica e dalla postura.\n\nValutare in base alla profondità e all’incapacità a reagire positivamente.",
            anchors: [
                "Assenza di tristezza",
                "Sembra scoraggiato, ma può rallegrarsi senza difficoltà",
                "Appare triste ed infelice per la maggior parte del tempo",
                "Appare infelice per tutto il tempo. Estremamente scoraggiato"
            ]
        ),
        .init(
            title: "Tristezza riferita",
            description: "Verbalizzazione di umore depresso, indipendentemente dal fatto che sia o meno anche manifesto. Comprende la malinconia, lo scoraggiamento o il sentimento di non poter essere aiutati, di essere senza speranza.\n\nValutare in base all’intensità, alla durata e al grado in cui l’umore, da quanto riferito, viene influenzato dagli eventi.",
            anchors: [
                "Tristezza occasionale in rapporto con le circostanze",
                "Triste o malinconico, ma può rallegrarsi senza difficoltà",
                "Sentimenti pervasivi di tristezza o melanconia. L’umore è ancora influenzato da circostanze esterne",
                "Tristezza, disperazione o scoraggiamento permanenti o senza fluttuazioni"
            ]
        ),
        .init(
            title: "Tensione interna",
            description: "Sentimenti di malessere mal definito, irritabilità, agitazione interiore, tensione nervosa crescente fino al panico, al terrore o all’angoscia.\n\nValutare in base ad intensità, frequenza, durata e grado di rassicurazione richiesta.",
            anchors: [
                "Calmo. Tensione interna solo passeggera",
                "Sensazioni occasionali di irritabilità e di malessere mal definito",
                "Sensazioni continue di tensione interna o panico intermittente che il paziente può controllare con difficoltà",
                "Continuo stato di terrore o angoscia. Panico opprimente."
            ]
        ),
        .init(
            title: "Riduzione del sonno",
            description: "Riduzione della durata o della profondità del sonno rispetto al tipo di sonno del paziente quando stava bene.",
            anchors: [
                "Dorme come al solito",
                "Lieve difficoltà ad addormentarsi o sonno leggermente diminuito, superficiale o agitato",
                "Sonno diminuito o interrotto per almeno 2 ore",
                "Meno di 2 o 3 ore di sonno"
            ]
        ),
        .init(
            title: "Riduzione dell’appetito",
            description: "Perdita dell’appetito rispetto a quello abituale.\n\nValutare in base alla perdita del desiderio di mangiare o al bisogno di sforzarsi a mangiare.",
            anchors: [
                "Appetito normale o aumentato",
                "Appetito leggermente ridotto",
                "Mancanza di appetito. Il cibo non ha sapore",
                "Bisogna insistere perché mangi qualcosa"
            ]
        ),
        .init(
            title: "Difficoltà di concentrazione",
            description: "Difficoltà a raccogliere le idee che può giungere fino all’incapacità a concentrarsi.\n\nValutare in base all’intensità, alla frequenza e al grado di compromissione.",
            anchors: [
                "Nessuna difficoltà di concentrazione",
                "Occasionale difficoltà a raccogliere le idee",
                "Difficoltà a concentrarsi e a mantenere l’attenzione con riduzione della capacità di leggere o di sostenere una conversazione",
                "Incapace di leggere o di conversare se non con grande difficoltà"
            ]
        ),
        .init(
            title: "Stanchezza",
            description: "Difficoltà a cominciare la giornata o lentezza ad iniziare e a compiere le attività quotidiane.",
            anchors: [
                "Praticamente nessuna difficoltà ad iniziare la giornata. Assenza di lentezza",
                "Difficoltà ad iniziare un’attività",
                "Difficoltà ad iniziare attività abituali che vengono eseguite con fatica",
                "Estrema stanchezza. Incapace di fare alcunché senza aiuto"
            ]
        ),
        .init(
            title: "Incapacità di provare sensazioni",
            description: "Esperienza soggettiva di una diminuzione di interesse per l’ambiente circostante o per le attività che normalmente procurano piacere. La capacità di reagire in maniera emotivamente appropriata alle circostanze o alla gente è ridotta.",
            anchors: [
                "Normale interesse per l’ambiente",
                "Ridotta capacità di provare piacere per gli interessi abituali",
                "Perdita di interesse per l’ambiente circostante. Riduzione dei sentimenti verso amici e conoscenti",
                "Sentimento di paralisi emotiva, incapacità di provare collera, dispiacere o piacere, completa incapacità, vissuta anche con dolore, di sentire qualcosa per i parenti e per gli amici più stretti."
            ]
        ),
        .init(
            title: "Pensieri pessimistici",
            description: "Idee di colpa, d’inferiorità, di autoaccusa, di peccato, di rimorso e di rovina.",
            anchors: [
                "Assenza di idee pessimistiche",
                "Idee fluttuanti di insuccesso, di autoaccusa o di autosvalutazione",
                "Persistenti idee di autoaccusa o chiare idee di colpa o di peccato, ma su basi razionali",
                "Idee deliranti di rovina, di rimorso o di colpe imperdonabili. Autoaccuse irremovibili"
            ]
        ),
        .init(
            title: "Idee di suicidio",
            description: "Sentimento che la vita non vale la pena di essere vissuta: che la morte naturale sarebbe benvenuta: idee di suicidio e preparativi di suicidio.\n\nI tentativi di suicidio non devono, di per sé, influenzare la valutazione.",
            anchors: [
                "Si gode la vita o la prende come viene",
                "Stanco della vita. Fugaci idee di suicidio.",
                "Vorrebbe essere morto. Ricorrenti idee di suicidio e il suicidio è considerato come una soluzione possibile, mancano tuttavia progetti o intenzioni precise",
                "Progetti espliciti di suicidio se si presentasse l’occasione. Preparativi di suicidio"
            ]
        )
    ]
}
