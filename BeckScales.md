# BAI e BDI-II in italiano

Le schede **BAI** e **BDI-II** si trovano nella sezione **Scale psicometriche** della cartella paziente. Ogni scheda permette di compilare una valutazione datata, rivedere le risposte salvate, correggere la data di somministrazione, consultare lo storico e il grafico, ed eliminare una valutazione dopo conferma. Il referto include l'ultima valutazione di ciascuna scala quando è selezionata l'opzione per le scale psicometriche.

## Moduli di origine

I testi sono trascritti dai PDF indicati dall'utente il 6 ottobre 2026:

- `/Users/stefanop/Desktop/Scale e Test/Beck Anxiety Inventory - BAI.pdf`: 2 pagine; Giunti O.S., sesta ristampa 2016, traduzione italiana copyright 2006 e 2015 Harcourt Assessment. SHA-256: `c50410448048e226ee8e68a353c71a428d298e5f2574d67f7c1c49d880dade7c`.
- `/Users/stefanop/Desktop/Scale e Test/Beck Depression Inventory - BDI II.pdf`: 2 pagine, contenuto del questionario acquisito come immagine, verificato visivamente. SHA-256: `8a02b3366b23c915742b1f805e9f11a93e06c9bb68961eb7b471403bf7f7acb8`.

Sono stati normalizzati spazi, interruzioni di riga e punteggiatura palesemente tipografica. Le istruzioni relative alle crocette sono adattate alla selezione a schermo. Il lessico delle risposte BDI-II è conservato, compresa la formulazione «interessante al sesso» nell'item 21, opzione 2, presente nella scansione. Non viene dichiarata una nuova validazione o un'equivalenza certificata della somministrazione digitale. I contenuti dei test conservano i diritti dei rispettivi titolari e non rientrano nella licenza MIT del codice.

Schede dell'editore italiano: [BAI](https://www.giuntipsy.it/bai), [BDI-2](https://www.giuntipsy.it/bdi-2).

## Risposte e calcolo

- Entrambe le scale hanno 21 item, con punteggio da 0 a 3 e totale da 0 a 63.
- BAI: riferimento all'ultima settimana, incluso oggi, come nel modulo fornito.
- BDI-II: riferimento alle ultime due settimane, incluso oggi. Gli item 16 e 18 presentano le sette opzioni `0, 1a, 1b, 2a, 2b, 3a, 3b`, che valgono rispettivamente `0, 1, 1, 2, 2, 3, 3` punti.
- Le risposte iniziali sono vuote. Il totale e il salvataggio sono disponibili solo dopo aver risposto validamente a tutti gli item; una selezione ripetuta deseleziona la risposta.
- Sono memorizzati gli indici delle opzioni: le varianti a/b restano distinguibili anche dopo backup e ripristino. I punteggi vengono calcolati dalle risposte; non sono memorizzati totali ridondanti.
- Un valore positivo dell'item 9 BDI-II genera un richiamo all'approfondimento clinico, anche se il totale è basso o la compilazione è ancora incompleta. Non viene attribuito automaticamente un livello di rischio suicidario.

## Interpretazione

Le fasce descrittive convenzionali del **punteggio grezzo** sono:

| Scala | Minima | Lieve | Moderata | Grave |
| --- | --- | --- | --- | --- |
| BAI | 0-7 | 8-15 | 16-25 | 26-63 |
| BDI-II | 0-13 | 14-19 | 20-28 | 29-63 |

Riferimenti: [NINDS, scheda BAI](https://cde-fe.ninds.nih.gov/ninds/noc-report/F2703/Beck%20Anxiety%20Inventory%20%28BAI%29), [Socialstyrelsen, scheda Beck Depression Inventory](https://www.socialstyrelsen.se/kunskapsstod-och-regler/omraden/evidensbaserad-praktik/metodguiden/bdi-becks-depression-inventory/). Il [report esemplificativo Pearson BDI-II](https://www.pearsonassessments.com/content/dam/school/global/clinical/us/assets/beck/BDI-II-Sample-Interpretive-Report.pdf) documenta l'attenzione agli item critici oltre al totale. Fonti consultate il 6 ottobre 2026.

Per BAI viene mostrato **separatamente** il percentile della tabella «Norme italiane» alla pagina 2 del modulo fornito (ristampa 2016). Il percentile non è una percentuale di gravità. Le fasce del punteggio grezzo non sono presentate come la classificazione normativa italiana. Non si estrapolano norme di edizioni successive, percentili BDI-II o sottoscale assenti dai moduli forniti.

## Persistenza e backup

`BeckAssessment` è collegato al paziente con cancellazione a cascata e distingue BAI da BDI-II tramite `scaleRawValue`. La nuova relazione è inizializzata come vuota. I test usano archivi isolati in memoria o cartelle temporanee.

Le scale Beck sono state introdotte con envelope `version: 1` e `schemaVersion: 3`, per evitare che le precedenti versioni del gestionale ignorino le nuove valutazioni. L’attuale schema 4 aggiunge la [MADRS](MADRS.md) e conserva `beckAssessments` nel payload e nei conteggi. Il ripristino accetta anche gli schemi 2 e 3: le scale assenti nei vecchi backup vengono decodificate come elenchi vuoti. Schema 1 continua a essere rifiutato, come prima della modifica.

Prima di sostituire i dati locali sono verificati presenza dei campi Beck negli schemi 3 e 4, conteggi, identificativi duplicati, collegamenti ai pazienti, versione della scala e validità di tutte le risposte. I backup con risposte Beck non valide sono rifiutati anche in esportazione.

## Verifica iniziale delle scale Beck

Compilazione Debug riuscita. Superati 26 test unitari, inclusi conteggi, estremi delle fasce, risposte mancanti/non valide, varianti a/b, percentili BAI, persistenza su disco, cancellazione a cascata, referto, backup/restore e compatibilità con schema 2. Verificata separatamente la migrazione di un archivio sintetico creato con i sorgenti precedenti alla modifica: paziente e GAD-7 conservati, BAI e BDI-II aggiunte e rilette dopo riapertura. Nessun archivio clinico reale è stato usato per queste prove.

Le viste nuove e compilate sono state renderizzate fuori schermo e ispezionate. Il controllo interattivo tramite Computer Use non era autorizzato per Chirone, quindi non è stata eseguita una prova manuale dei clic nell'app.
