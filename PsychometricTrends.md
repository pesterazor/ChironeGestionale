# Grafici compatti delle scale psicometriche

Implementazione verificata il 7 ottobre 2026 nella cartella attiva `ChironeGestionale/`.

Le schede PHQ-9, GAD-7, BAI, BDI-II, MADRS e MDQ usano `PsychometricTrendData.swift` e `PsychometricTrendView.swift`. Il riepilogo contiene punteggio e ultime 12 valutazioni valide, con confronto rispetto alla precedente valida e alla prima valida dell’intero storico. Se tra le ultime due valutazioni valide esistono record esclusi, il confronto precisa «precedente valida». Se l’ultimo record è invalido, il riepilogo sospende entrambi i confronti.

Le serie rispettano l’ordinamento già adottato per data, creazione e identificatore. Un record invalido apre un nuovo segmento; i record coincidenti mantengono identità e date, senza media o spostamenti. L’ispezione elenca tutti i record validi alla data selezionata, anche quando il limite di 12 punti cade su una data condivisa. Le risposte vengono validate prima del calcolo; anche lo storico PHQ-9/GAD-7/MDQ segnala i record invalidi.

Il grafico compatto ha altezza 96 punti; «Andamento completo» parte chiuso e costruisce il grafico da 220 punti soltanto quando aperto. Domini fissi, interpolazione lineare, estremi temporali con anno e soglie esistenti nel grafico completo. Il layout riserva almeno 260 punti al grafico nella disposizione affiancata e passa alla disposizione verticale sotto la larghezza necessaria. Percentile, valutatore, dettagli, avvisi clinici e criteri MDQ rimangono visibili.

La selezione usa `chartXSelection`, con hover nativo macOS; frecce sinistra/destra selezionano la data adiacente, Escape annulla la selezione. Sono presenti etichette accessibili dei punti, riepiloghi e azioni incrementa/decrementa. Riferimento dell’API: [Apple, Explore pie charts and interactivity in Swift Charts](https://developer.apple.com/videos/play/wwdc2023/10037/).

## Esiti verificati

- Suite completa `ChironeGestionaleTests`: **77 superati, 0 falliti, 0 saltati** (68 precedenti + 9 nuovi).
- Compilazioni **Debug e Release riuscite**, firma disattivata, macOS arm64. Nessun nuovo avviso Swift; rimane l’avviso del tool Xcode sull’assenza di AppIntents.
- Test dei confronti positivi/negativi/nulli, serie vuote/singole/costanti, limite di 12, baseline completa, invalidità e interruzioni, date coincidenti, separazione Beck, soglie e massimi delle sei scale, aggiunta, modifica della data e cancellazione persistente.
- Test della funzione di navigazione usata da frecce e azioni accessibili: estremi, direzioni, date coincidenti e serie vuota.
- **29 rendering sintetici fuori schermo**, esaminati: sei schede × 820/980 punti × chiaro/scuro, quattro casi limite a 420 punti e grafico completo con interruzione. Valutatore lungo e avvisi clinici inclusi. Nessun troncamento nel riepilogo.
- Contrasto della linea campionata dai rendering: circa **6,1:1** nel tema chiaro e **8,3:1** nel tema scuro rispetto alla superficie della scheda. Punteggi, differenze e classificazioni sono espressi anche come testo.

## Limite della verifica di interazione

Il test di introspezione dell’albero di accessibilità di `NSHostingView` fuori schermo non riceve figli accessibili da macOS, anche esponendo la finestra fuori dall’area visibile. Questo test sperimentale è stato rimosso: non costituiva una verifica affidabile del comportamento VoiceOver. La navigazione è verificata a livello di logica; hover, focus da tastiera, apertura del disclosure e lettura effettiva con VoiceOver richiedono ancora una prova interattiva nell’app. Non si dichiara una certificazione completa dell’accessibilità.

Per la prova manuale: Tab sul grafico, frecce tra le date, Escape; passaggio del puntatore sui punti e sui record coincidenti; apertura/chiusura di «Andamento completo»; lettura dei punti e dei riepiloghi con VoiceOver, anche dopo modifica o cancellazione di una valutazione.

## Evidenze locali

- Risultati: `/tmp/chirone-trends-tests.xcresult`.
- Log: `/tmp/chirone-trends-tests.log`, `/tmp/chirone-trends-debug.log`, `/tmp/chirone-trends-release.log`.
- Rendering finali: `/tmp/chirone-trends-final-review/` (PNG nominati per scala, larghezza e tema, più quattro tavole di contatto).

Nessuna nuova dipendenza, modifica dello schema o intervento sui grafici PDF. Nessun dato clinico reale usato nelle verifiche.
