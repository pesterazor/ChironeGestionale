# Revisione del codice — 6 ottobre 2026

Revisione dei flussi di avvio, ricerca, cartella clinica, scale psicometriche, documenti, autenticazione e backup. Le correzioni sono state applicate al codice locale, conservando le modifiche già presenti. I test usano dati sintetici e archivi temporanei; l'archivio clinico dell'utente non è stato modificato.

## Affidabilità e protezione dei dati

| Criticità individuata | Correzione applicata |
| --- | --- |
| Un errore nell'apertura del database poteva attivare silenziosamente un archivio temporaneo. | L'avvio mostra l'errore e consente di riprovare o uscire. Il database in memoria è riservato ai test Debug. |
| Il ripristino poteva lasciare l'archivio incompleto dopo un errore. | Validazione completa prima della sostituzione, un unico salvataggio finale e rollback. Le modifiche precedenti vengono salvate prima della transazione. |
| Alcuni percorsi dichiaravano il successo prima di verificare la persistenza. | Salvataggi espliciti per terapia, note, esami e scale; gestione degli errori con conservazione delle bozze. Terapia e nota automatica sono salvate insieme. |
| Un errore di cifratura poteva produrre testo in chiaro o perdere il valore precedente. | I nuovi salvataggi dei campi protetti e delle note falliscono esplicitamente; mantengono il contenuto precedente. La lettura di contenuti cifrati non genera una chiave sostitutiva. |
| Piccole modifiche alle bozze cliniche potevano sfuggire all'autosalvataggio. | Rilevazione anche delle correzioni a parità di lunghezza, salvataggio periodico e alla chiusura, migrazione delle vecchie bozze verso contenuti cifrati. |
| Finestre secondarie e schede modali richiedevano una protezione coerente durante il blocco. | Stato di autenticazione condiviso, contenuto protetto anche nei questionari e nei documenti, titoli clinici oscurati e controlli sui comandi. Il blocco conserva lo stato delle bozze. |
| Chiusura, sostituzione di un documento e ripristino potevano scartare una bozza. | Conferme prima di scartare modifiche a referti e prescrizioni, controlli all'uscita e prima di chiudere le finestre per il ripristino. |

Il backup controlla UUID duplicati, riferimenti ai pazienti, risposte delle scale, parametri crittografici e metadati autenticati. Derivazione della chiave, cifratura e accesso al file sono eseguiti fuori dal main actor. Compatibilità e limiti dei backup precedenti sono descritti in [BackupReview.md](BackupReview.md).

## Esperienza d'uso

- PHQ-9, GAD-7 e MDQ iniziano senza risposte selezionate: una risposta mancante non equivale più a zero o a «No». Il risultato e il salvataggio richiedono una compilazione completa; lo stato incompleto è visibile.
- Le eliminazioni delle valutazioni vengono salvate esplicitamente e ripristinate in caso di errore. L'eliminazione dei pazienti richiede conferma.
- Storici ordinati una sola volta per aggiornamento, pulsanti di eliminazione sempre disponibili, criteri MDQ leggibili e anno nelle date dei grafici. L'interpolazione lineare evita oscillazioni visive tra valutazioni reali.
- La tabella degli esami conserva l'editor durante gli aggiornamenti e acquisisce anche l'ultima cella ancora in modifica prima del salvataggio.
- Le anteprime PDF mantengono scorrimento e zoom quando il documento non cambia. Una versione già renderizzata viene riutilizzata finché la bozza resta identica.
- Ricerca pazienti tollerante a maiuscole, accenti, spazi aggiuntivi e ordine delle parole. Ordinamento stabile anche a parità di data.
- Confermate le integrazioni BAI, BDI-II e MADRS e la modifica della data delle valutazioni già salvate. Questa revisione non cambia soglie o criteri clinici.

## Prestazioni misurate

Il collo di bottiglia dell'autocompletamento era la ripetizione delle elaborazioni testuali e delle espressioni regolari durante l'ordinamento. Le chiavi di ricerca e ordinamento vengono ora preparate una volta; il caricamento iniziale è fuori dal main actor.

Benchmark isolato: compilazione `swiftc -O`, stesse risorse JSON, cinque processi nuovi per versione, inizializzazione di `ActiveIngredientAutocomplete.shared` e prima ricerca `SE`. Entrambe le versioni restituiscono 12 risultati.

| Versione | Tempi dei cinque campioni (ms) | Mediana |
| --- | --- | --- |
| Prima | 298,609 · 266,544 · 266,684 · 272,961 · 268,680 | 268,680 ms |
| Dopo | 40,919 · 26,893 · 23,068 · 23,514 · 23,003 | 23,514 ms |

Riduzione del tempo mediano del **91,2%**, circa **11,4 volte** più veloce per questa operazione. La misura non rappresenta il tempo di avvio dell'intera applicazione.

Sono stati inoltre rimossi ordinamenti ripetuti delle scale, calcoli delle ultime visite dentro i confronti di ordinamento e rigenerazioni inutili delle anteprime PDF. Questi interventi non hanno un benchmark separato.

## Verifica finale

- **68 test superati**, zero fallimenti, zero test saltati; suite `ChironeGestionaleTests` su macOS arm64.
- Compilazione Debug con test e compilazione Release riuscite, con `CODE_SIGNING_ALLOWED=NO`.
- Nessun warning del compilatore Swift nei log finali. Rimane il messaggio di Xcode sull'estrazione dei metadati AppIntents saltata perché il progetto non dipende da quel framework.
- Copertura aggiunta per rollback, validazione dei backup, errori di cifratura, bozze, persistenza clinica, ricerca, autenticazione, risposte mancanti e protezione delle bozze dei documenti.
- Rendering fuori schermo e controllo visivo di PHQ-9, GAD-7, MDQ e storico MDQ; la suite genera anche le schermate BAI, BDI-II, MADRS e modifica data.
- Rimangono inclusi i test sui PDF multipagina e sulla conservazione del contenuto di referti e prescrizioni.

Comandi di riferimento:

```sh
xcodebuild -project ChironeGestionale.xcodeproj -scheme ChironeGestionale -configuration Debug -destination 'platform=macOS' -only-testing:ChironeGestionaleTests test CODE_SIGNING_ALLOWED=NO
xcodebuild -project ChironeGestionale.xcodeproj -scheme ChironeGestionale -configuration Release -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

## Limiti della verifica e lavoro futuro

La verifica dell'interfaccia è basata sul rendering fuori schermo, non su una sessione interattiva completa. Non sono stati eseguiti i test UI end-to-end né provati Touch ID, stampa e finestre di sistema nell'app in uso. La build verificata non è stata installata come nuova release.

Snapshot e importazione finale SwiftData restano sul main actor e crescono con il numero dei record. Non è stata misurata la fluidità su un grande archivio clinico reale: un'eventuale elaborazione a blocchi richiede una verifica dedicata della consistenza del ripristino.

La cifratura applicativa protegge specifici campi e i backup; non equivale alla cifratura integrale del database SwiftData. Anagrafica, dati strutturati della terapia e punteggi delle scale non diventano cifrati per effetto di questa revisione. Le correzioni non costituiscono una certificazione di sicurezza o conformità.

Le copie PHQ-9 alla radice, estranee al target compilato, sono state conservate insieme alle modifiche locali preesistenti. Il codice attivo delle scale è nella cartella `ChironeGestionale/`.
