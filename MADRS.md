# MADRS e modifica della data delle scale

Nello storico di PHQ-9, GAD-7, MDQ, BAI, BDI-II e MADRS, **Modifica data** apre un selettore della data di somministrazione. **Salva data** salva immediatamente la correzione; **Annulla** la scarta. Le risposte, l’identificativo e la data di creazione della valutazione restano invariati. In caso di errore di salvataggio, la data precedente viene ripristinata senza annullare altre modifiche al paziente.

Lo storico, il grafico e l’ultima valutazione sono riordinati secondo la nuova data. In caso di parità vengono usati data di creazione e identificativo. Le nuove bozze di referto riportano l’ultima valutazione secondo l’ordine aggiornato; le bozze e i PDF già creati non vengono riscritti. BAI, BDI-II e MADRS consentono la correzione anche dalla vista dei dettagli.

## Modulo MADRS di origine

Testi trascritti dal file fornito dall’utente il 6 ottobre 2026: `/Users/stefanop/Desktop/Scale e Test/MADRS.doc`.

SHA-256: `00256f38b1b2a876f9b01437f730b56f4f06b8a2e70c32557eda1c5073829e39`.

Il documento Word contiene tre pagine incorporate come immagini EMF, estratte e ispezionate visivamente. Sono stati normalizzati spazi e interruzioni di riga. Il titolo abbreviato «Pessimistici» è visualizzato come «Pensieri pessimistici»; il refuso che numera nuovamente «9» l’ultimo item è corretto in **10, Idee di suicidio**. Le descrizioni e le ancore di risposta sono conservate. Non è stato aggiunto un periodo di riferimento assente nel modulo.

La scheda è compilata dal clinico e include un campo facoltativo per il valutatore, presente anche nel documento. Non si dichiara una nuova validazione o un’equivalenza certificata della versione digitale. I contenuti della scala conservano i diritti dei rispettivi titolari e non rientrano nella licenza MIT del codice.

## Punteggio e interpretazione

- Dieci item, ciascuno da 0 a 6; totale da 0 a 60.
- Le descrizioni del modulo ancorano i valori 0, 2, 4 e 6. Sono selezionabili anche 1, 3 e 5, indicati come valori intermedi fra le descrizioni adiacenti.
- Le risposte iniziano vuote. Totale e salvataggio richiedono dieci risposte valide; una seconda selezione della stessa risposta la deseleziona.
- Fasce descrittive convenzionali: 0–6 assente/minima, 7–19 lieve, 20–34 moderata, 35–60 grave. Non costituiscono una diagnosi.
- Qualsiasi valore maggiore di zero all’item 10 mantiene visibile un richiamo all’approfondimento clinico anche con totale basso o scheda incompleta. È una scelta prudenziale dell’interfaccia, non un algoritmo di classificazione del rischio.
- Sono disponibili dettagli, storico, andamento e inclusione opzionale nel referto. Il referto può riportare il valutatore e il richiamo relativo all’item 10.

Riferimenti verificati il 6 ottobre 2026: [Montgomery e Åsberg, 1979](https://pubmed.ncbi.nlm.nih.gov/444788/), [strumento presentato dall’APA](https://www.apa.org/depression-guideline/montgomery-asberg-scale.pdf). Le fasce descrittive sono documentate nel [protocollo italiano DeprAir](https://pmc.ncbi.nlm.nih.gov/articles/PMC10049152/) e in questo [studio di validazione](https://pmc.ncbi.nlm.nih.gov/articles/PMC4852448/).

## Persistenza e backup

`MADRSAssessment` conserva punteggi, data, valutatore, identificativo, data di creazione e collegamento al paziente. Totale e fascia vengono calcolati dai punteggi. La cancellazione del paziente elimina anche le sue MADRS.

Il backup cifrato usa envelope 1 e schema 4. I backup schema 2 e 3 rimangono leggibili, con MADRS assenti interpretate come elenco vuoto. Lo schema 4 richiede la collezione e il relativo conteggio anche quando sono vuoti. Risposte incomplete o fuori intervallo, identificativi duplicati e collegamenti a pazienti assenti vengono rifiutati prima di sostituire i dati locali; risposte MADRS non valide impediscono anche l’esportazione.

Le prove automatiche usano solo dati sintetici in memoria o cartelle temporanee. Le fixture JSON cifrate hanno password di test `BeckFixturePassword` e verificano la compatibilità con lo schema 3 e il rifiuto di MADRS malformate nello schema 4. Le date corrette sono incluse nel backup di tutte le scale.

## Verifica

Compilazioni Debug e Release riuscite. Superati 38 test unitari: tutte le fasce di punteggio, valori intermedi, risposte mancanti/non valide, item 10 indipendente dal totale, correzione e persistenza delle date per tutte e sei le scale, gestione dell’errore di salvataggio, ordinamento, referti, cancellazione a cascata, backup/restore e compatibilità con i backup precedenti.

Verificata separatamente la migrazione di un archivio sintetico creato con i sorgenti precedenti all’aggiunta della MADRS: paziente e BDI-II conservati, data BDI-II corretta, MADRS aggiunta, salvataggio e riapertura riusciti. Nessun archivio clinico reale è stato usato. Nei test Debug la cifratura usa una chiave temporanea in memoria, senza accesso alla chiave del Portachiavi; la build ordinaria conserva il comportamento precedente.

Renderizzate fuori schermo e ispezionate la scheda MADRS vuota e compilata, lo storico con grafico, l’editor della data e le viste delle scale esistenti. Non è stata eseguita una prova interattiva dei clic nell’app: il controllo tramite Computer Use per Chirone non era autorizzato.
