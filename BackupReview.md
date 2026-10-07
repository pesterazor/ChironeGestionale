# Revisione backup e protezione dei dati — 6 ottobre 2026

## Correzioni

- Il ripristino valida il contenuto completo prima di modificare l'archivio. Le cancellazioni e gli inserimenti vengono salvati insieme; un errore provoca rollback. Eventuali modifiche precedenti nel contesto vengono prima salvate, così il rollback non le annulla.
- Sono controllati UUID duplicati e riferimenti a pazienti inesistenti per tutte le entità, oltre alla cardinalità e ai valori ammessi nelle risposte di tutte le scale. L'importazione senza sostituzione rifiuta record già presenti.
- Il lettore limita PBKDF2 a 100.000–2.000.000 iterazioni, richiede chiavi di 32 byte, salt di 16 byte e nonce di 12 byte, e verifica gli algoritmi dichiarati e la corrispondenza tra nonce esterni e ciphertext. I backup generati dall'app continuano a usare 600.000 iterazioni.
- I nuovi backup autenticano anche tutti i metadati esterni tramite AAD: versione applicativa e schema, conteggi, data, algoritmi, salt, dimensione della chiave e nonce. La lettura verifica il confronto prima della derivazione della chiave. La modifica coordinata di metadati e AAD viene comunque respinta dal tag AES-GCM.
- Restano leggibili i backup degli schemi 2, 3 e 4. Per i backup precedenti, che avevano un AAD più piccolo e due chiamate separate a `Date()`, non si impone l'uguaglianza tra la data esterna e quella nell'AAD. I metadati che allora non erano autenticati non possono essere autenticati retroattivamente; conteggi e relazioni vengono comunque verificati sul payload decifrato.
- La UI crea uno snapshot dei valori sul relativo actor SwiftData e passa soltanto DTO `Sendable` al lavoro in background. PBKDF2, AES-GCM e lettura/scrittura del file sono effettivamente fuori dal main actor. La modifica finale dello store resta sul main actor, in una singola operazione sincrona.
- Password errata, file non valido e annullamento non chiudono più preventivamente le cartelle. Conferma finale e chiusura delle finestre avvengono dopo la validazione. Operazioni backup contemporanee nella stessa istanza del servizio vengono impedite.
- L'export interrompe l'operazione se un campo cifrato non è decifrabile, senza sostituirlo silenziosamente con il fallback vuoto. Il restore verifica che la ricifratura locale dei campi non vuoti sia riuscita.
- La lettura di un ciphertext non crea una nuova chiave quando la chiave originale manca. Sono verificati i 32 byte della chiave Keychain; una creazione concorrente della stessa voce viene gestita rileggendo la chiave effettiva.
- Durante XCTest Debug, il registro audit usa una cartella temporanea dedicata, oltre alla chiave sintetica già prevista per i test.

## Verifica

`BackupIntegrityTests.swift` copre rollback di un ripristino fallito su store temporaneo (comprese modifiche precedenti), parametri KDF fuori limite, manomissione di metadati e nonce, AAD contraffatto, duplicati/relazioni/risposte errati, duplicati in importazione aggiuntiva, contenuto cifrato illeggibile e round trip crittografico su thread secondario. Le fixture legacy esistenti continuano a verificare gli schemi precedenti. Nessun test richiede dati clinici o chiavi dell'utente.

L'esito della compilazione e della suite completa è riportato nella revisione generale; questo documento descrive i controlli implementati, non costituisce una certificazione crittografica. Non sono stati eseguiti benchmark su archivi clinici reali. Snapshot e inserimento finale restano proporzionali al numero di record e possono richiedere tempo su archivi molto grandi.

## Verifica integrativa e correzioni — 7 ottobre 2026

### Problemi riscontrati e risolti

- **Date e ordinamento:** il vecchio encoder ISO-8601 eliminava le frazioni di secondo di tutte le date del payload. Due valutazioni create nello stesso secondo potevano quindi cambiare ordine dopo il ripristino. Lo schema 5 conserva il valore numerico esatto delle date; il lettore continua ad accettare gli schemi 2, 3 e 4. I nuovi backup richiedono questa versione aggiornata dell'app.
- **Testo delle note:** il ripristino passava dal metodo di editing, che rimuove gli spazi e le righe vuote iniziali/finali. Ora il contenuto originario viene ricifrato integralmente, anche per le note legacy.
- **Portabilità del singolo paziente:** l'export JSON ometteva tutte le scale, `medicalHistory` e `currentTherapySummary`, e poteva esportare testo vuoto in presenza di ciphertext illeggibili. Ora riutilizza le stesse mappature e la validazione rigorosa del backup, comprende PHQ-9, GAD-7, MDQ, BAI, BDI-II e MADRS, e interrompe l'export se un campo cifrato non è leggibile. Rimane un export in chiaro, dichiarato nel pannello di salvataggio, distinto dal backup cifrato `.chdb`.
- **Chiave locale assente e sovrascrittura:** il preriscaldamento della chiave dopo lo sblocco poteva creare una chiave sostitutiva. Ora legge soltanto. Diagnosi, comorbidità, anamnesi psichiatrica, allergie e note rifiutano anche la cancellazione se il ciphertext preesistente non è decifrabile; il contenuto recuperabile viene conservato.
- **Controlli dei comandi:** accesso clinico verificato anche nei metodi del servizio e dopo i pannelli; operazioni serializzate tra istanze; accesso ai file selezionati gestito con security scope. Le bozze non confermate vengono segnalate prima dell'export. Un blocco dell'app durante la verifica del backup impedisce di proseguire con il ripristino.

### Prove eseguite

- Suite completa `ChironeGestionaleTests`: **94 test superati, 0 fallimenti, 0 saltati**, su macOS arm64 con Xcode 27, Debug e `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`.
- Compilazione **Release superata**, anch'essa con `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` e firma disabilitata; log `/tmp/chirone-backup-release.log`. Nessun warning Swift; soltanto l'avviso del tool AppIntents sull'assenza di una dipendenza da quel framework.
- 17 nuovi test in `EncryptedBackupRoundTripTests.swift` e `SecureDataIntegrityTests.swift`: confronto indipendente di tutti i campi e delle relazioni, sei scale, varianti BDI-II, valutatore MADRS, date esatte e ordine delle valutazioni; scrittura/lettura del `.chdb`, ripristino su store temporaneo e riapertura del database; importazione aggiuntiva, sostituzione e archivio vuoto; password errata, manomissione dei due ciphertext; portabilità; chiave assente, non valida, non disponibile o creata contemporaneamente; conservazione dei campi illeggibili.
- Fixture legacy positiva aggiunta per schema 4 con MADRS e successiva riesportazione nello schema attuale; restano verdi le fixture degli schemi 2 e 3 e i controlli dei backup malformati.
- Confermati dai test esistenti: rollback dopo errore di salvataggio, conservazione delle modifiche già presenti, parametri KDF limitati, autenticazione AAD/metadati, rifiuto di UUID duplicati, riferimenti non validi e risposte fuori intervallo.
- Evidenza XCTest: `/tmp/chirone-backup-full.xcresult`; log `/tmp/chirone-backup-full.log`. `git diff --check` senza errori.

### Ambito della verifica

Solo dati sintetici, chiavi di test e store temporanei: nessun ripristino sull'archivio clinico dell'utente e nessuna modifica ai backup reali. Non è stata eseguita una prova su un secondo Mac né l'interazione manuale con tutti i pannelli del Finder. I test verificano il percorso dati e crittografico effettivo e la persistenza su disco; il flusso dei pannelli è stato revisionato nel codice.

Il backup comprende tutte le entità cliniche, non preferenze, intestazione professionale, audit o bozze. La sostituzione dell'archivio richiede ancora conferma e scarta le bozze indicate nella conferma; il rollback protegge i dati persistiti, non le bozze già scartate. La cifratura locale resta limitata ai campi testuali protetti: non è una cifratura dell'intero database SwiftData.
