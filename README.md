# 🧠 Chirone Gestionale

**Chirone Gestionale** è un **software gestionale clinico per macOS** progettato per professionisti della salute mentale che cercano un’app **sicura, veloce, intuitiva e local-first** per gestire pazienti, note cliniche, terapia, esami e referti.

SEO keywords: `gestionale clinico macOS`, `cartella clinica psichiatria`, `software psicoterapia`, `privacy dati sanitari`, `backup cifrato`, `referto PDF`, `SwiftUI medical app`.

## ✨ Perché Chirone
- ⚡ **Workflow rapido**: interfaccia nativa macOS, fluida anche nell’uso quotidiano intensivo.
- 🔒 **Privacy by design**: cifratura dei dati sensibili, lock app, backup cifrato.
- 🧩 **Flusso clinico completo**: anagrafica, aggiornamenti clinici, terapia, esami ematochimici, referto.
- 🖥️ **Local-first**: i dati restano sul dispositivo, senza dipendenze cloud obbligatorie.
- 🛠️ **Open-source**: roadmap pubblica, miglioramenti continui, base tecnica estendibile.

## 💎 Perché è una piattaforma ad alto valore
Chirone nasce con un posizionamento chiaro: offrire ai professionisti clinici un’esperienza premium nativa macOS che unisce velocità operativa, affidabilità e protezione reale del dato sanitario. L’app gira con stack Apple (`SwiftUI + SwiftData`) e integra componenti AppKit dove serve massima precisione, così da garantire interazioni fluide, multi-window efficace e tempi di risposta coerenti anche nei flussi quotidiani ad alta frequenza.

Dal punto di vista infrastrutturale, il modello `local-first` elimina dipendenze cloud non necessarie e riduce attività di background continue: risultato, un software reattivo e tendenzialmente leggero su CPU, memoria e batteria, particolarmente adatto all’uso professionale su MacBook in mobilità.

Sul fronte sicurezza, Chirone implementa una linea di difesa stratificata: lock applicativo, cifratura dei campi sensibili, backup cifrato con envelope versionato (`AES-GCM` + `PBKDF2-HMAC-SHA256`) e controlli anti-manomissione in restore (`version`, `schemaVersion`, `recordCounts`). A questo si aggiunge un audit trail tecnico pensato per tracciabilità operativa senza esposizione di PHI in chiaro. In sintesi: un prodotto progettato per essere clinicamente utile oggi e tecnicamente solido nel lungo periodo.

## 👩‍⚕️ A chi è utile
Chirone è pensato per:
- psichiatri
- psicoterapeuti
- professionisti che gestiscono follow-up clinici longitudinali
- team che cercano un **gestionale sanitario macOS** con focus su affidabilità e sicurezza operativa

## ✅ Funzionalità principali
- 👤 **Anagrafica pazienti** con ricerca rapida e selezione da sidebar.
- 🗂️ **Cartella clinica dedicata** in finestra separata per ogni paziente.
- 📝 **Aggiornamenti clinici / timeline note** con ordinamento stabile e storico leggibile.
- 💊 **Terapia psicofarmacologica** strutturata con inserimento, modifica e salvataggio rapido.
- 🧪 **Esami ematochimici** in tabella avanzata con colonne data, valori e calcoli derivati.
- 📄 **Referto PDF** con anteprima dedicata ed export.
- 🔐 **App Lock** con timeout di ri-autenticazione.
- 🛡️ **Cifratura campi sensibili** e **backup cifrato con restore**.
- 📚 **Audit trail** interno per eventi critici (in evoluzione progressiva).

## 🚀 Guida rapida (Quick Start)
1. Apri `ChironeGestionale.xcodeproj` in Xcode.
2. Seleziona lo scheme `ChironeGestionale`.
3. Build & Run su macOS.

## 🧭 Come usare Chirone (flusso consigliato)

### 1) Creazione paziente
- Clicca su **Nuovo paziente**.
- Compila i campi essenziali (nome, cognome, luogo di nascita).
- Conferma con creazione paziente.

### 2) Apertura cartella clinica
- Seleziona il paziente dalla sidebar.
- Apri **cartella clinica** per lavorare in finestra dedicata.

### 3) Inserimento aggiornamento clinico
- Vai in **Aggiornamenti clinici**.
- Scrivi la nuova nota, imposta data/ora e benessere percepito.
- Salva la nota.

### 4) Gestione terapia
- Nella sezione **Terapia attuale**, aggiungi farmaco, dosaggio, posologia.
- Salva le modifiche terapia.

### 5) Esami ematochimici
- Aggiungi una data di prelievo/controllo.
- Inserisci i valori nelle celle tabellari.
- Salva esami per persistenza dei dati.

### 6) Referto clinico
- Con cartella paziente attiva, usa il comando export referto.
- Verifica anteprima PDF.
- Salva il documento finale.

## ⌨️ Shortcut utili
- `⌘P` Esporta referto (con cartella clinica attiva).
- `⌘⇧S` Salva nuova nota clinica.
- `⌘⌥N` Aggiungi farmaco in terapia.
- `⌘⌥T` Salva terapia.
- `⌘⌥E` Salva esami ematochimici.

## 🏗️ Architettura progetto
- `ChironeGestionale/` codice app (SwiftUI, SwiftData, risorse JSON).
- `ChironeGestionaleTests/` unit test.
- `ChironeGestionaleUITests/` test UI end-to-end.
- `Chirone_Professional_Roadmap.md` roadmap prodotto/engineering.
- `GDPR_Roadmap.md` roadmap compliance/privacy.
- `EncryptedBackupDesign.md` formato e policy backup cifrato.

## 🔒 Sicurezza, privacy e compliance
- Local-first: nessuna dipendenza cloud obbligatoria.
- Cifratura dei contenuti sensibili.
- Backup cifrato con controlli di integrità/versione.
- Ripristino con validazioni anti-manomissione.
- Per segnalazioni sicurezza: `SECURITY.md`.
- Per stato compliance operativo: `COMPLIANCE_READINESS.md`.

## 🧪 Qualità software
- Test unitari su componenti core clinici e backup/restore.
- Test UI su flussi principali (creazione paziente, nota, terapia, esami, anteprima referto).
- Strategia qualità in evoluzione continua secondo roadmap.

## ⚠️ Clinical Use Notice
Chirone non è dichiarato come dispositivo medico certificato.
Il professionista resta responsabile della validazione clinica finale di dati, referti e decisioni terapeutiche.
Dettagli: `CLINICAL_USE_NOTICE.md`.

## 🤝 Contribuire
- Linee guida contributi: `CONTRIBUTING.md`
- Codice di condotta: `CODE_OF_CONDUCT.md`
- Policy release: `RELEASE_POLICY.md`

## 🛣️ Roadmap
Per priorità e piano sviluppo:
- `Chirone_Professional_Roadmap.md`
- `GDPR_Roadmap.md`

## 📄 Licenza
MIT License. Vedi `LICENSE`.
