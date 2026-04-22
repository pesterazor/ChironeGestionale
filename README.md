# 🧠 Chirone Gestionale

Gestionale pazienti minimalista, locale e orientato alla pratica psichiatrica. Il nome è scelto in onore a Chirone (Chéiron), una figura della mitologia greca associata alla medicina e alla conoscenza.

Sviluppato per macOS. Basato su SwiftUI. Costruito in modo incrementale.

---

## Panoramica

Chirone Gestionale è uno strumento leggero per la gestione clinica, progettato con focus su:

- accesso rapido ai dati del paziente
- riduzione del carico cognitivo
- persistenza locale dei dati
- architettura modulare e scalabile

Il progetto privilegia l’utilizzabilità reale in ambito clinico rispetto alla completezza funzionale.

---

## Principi di progettazione

- **Local-first**  
  Tutti i dati sono salvati in locale. Non sono richiesti servizi cloud.

- **Privacy by design**  
  L’architettura è pensata per supportare cifratura e gestione sicura dei dati.

- **Sviluppo incrementale**  
  Ogni funzionalità viene implementata come unità minima funzionante, poi estesa.

- **UI minimalista**  
  L’interfaccia evita elementi superflui e mostra solo informazioni clinicamente rilevanti.

- **Focus su un singolo paziente**  
  Il flusso di lavoro riduce il contesto attivo a un paziente alla volta.

---

## Architettura

- **Linguaggio:** Swift  
- **UI Framework:** SwiftUI  
- **Persistenza:** SwiftData  
- **Pattern:** MVVM (in evoluzione modulare)

Moduli previsti:

- Scheduling
- Fatturazione
- Questionari psicometrici
- Export e reportistica

---

## Funzionalità attuali

- Creazione ed eliminazione pazienti
- Ricerca dinamica (nome, cognome, codice fiscale, telefono)
- Selezione paziente con riepilogo clinico
- Apertura cartella clinica in finestra dedicata
- Struttura base per dati clinici
- Interfaccia macOS nativa (senza sidebar persistente)

---

## In sviluppo

- Timeline delle note cliniche
- Modello strutturato della terapia farmacologica
- Editor completo anagrafica + dati clinici
- Esportazione PDF

---

## Pianificato

- Cifratura AES dei dati sensibili
- Backup locale cifrato
- Logging minimale (audit)
- Eventuale sincronizzazione multi-dispositivo

---

## Modello di utilizzo

L’applicazione è organizzata in due contesti principali:

### 1. Finestra indice
- ricerca pazienti
- elenco
- riepilogo sintetico

### 2. Finestra clinica
- spazio dedicato al singolo paziente
- accesso completo ai dati
- futura integrazione timeline e moduli clinici

Questa separazione riduce la complessità dell’interfaccia e minimizza il rischio di errori di contesto.

---

## Requisiti

- macOS (da versione 26.0 in poi)
- Xcode (ultima versione stabile consigliata)

---

## Installazione

```bash
git clone https://github.com/<tuo-username>/ChironeGestionale.git
```  

⸻

## Stato del progetto

Prototipo in fase iniziale.

Il codice è attivamente sviluppato e soggetto a modifiche e refactor.

⸻

## Contributi

I contributi sono benvenuti, in particolare su:

* architettura SwiftUI
* modellazione dati clinici
* ottimizzazione del flusso di lavoro
* UX su macOS

⸻

## ⚠️ Disclaimer

Questo software è sperimentale e non sostituisce:

* sistemi certificati di cartella clinica
* obblighi normativi nazionali o regionali
* software medicali validati

L’utilizzo è a discrezione dell’utente.

⸻

## Licenza

Open-source. Vedi file LICENSE.
