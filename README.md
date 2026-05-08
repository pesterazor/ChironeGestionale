# Chirone Gestionale

Gestionale clinico macOS open-source per professionisti della salute mentale.

## Vision
Chirone nasce per offrire un flusso clinico locale, rapido e affidabile, con UX nativa macOS, forte attenzione a privacy/sicurezza e una base tecnica mantenibile dalla community.

## Stato progetto
- Piattaforma: macOS (SwiftUI + SwiftData)
- Maturità: operativo, in evoluzione
- Ambito: psichiatria/psicoterapia (workflow single-patient)

## Funzionalità disponibili
- Anagrafica pazienti con ricerca rapida
- Apertura cartella clinica in finestra dedicata
- Timeline clinica e note
- Terapia psicofarmacologica strutturata
- Sezione esami ematochimici con tabella e calcoli derivati
- Export referto PDF con anteprima e stampa
- Lock applicazione
- Cifratura dati sensibili
- Backup cifrato e restore

## Screenshot
Gli screenshot UI verranno pubblicati nella cartella `docs/images/` con il prossimo aggiornamento della documentazione pubblica.

## Struttura progetto
- `ChironeGestionale/`: sorgenti app (entrypoint, view principali, JSON risorse)
- `ChironeGestionaleTests/`: unit test
- `ChironeGestionaleUITests/`: test UI
- `Chirone_Professional_Roadmap.md`: roadmap prodotto/engineering
- `GDPR_Roadmap.md`: roadmap compliance

## Quick Start
1. Apri `ChironeGestionale.xcodeproj` con Xcode.
2. Seleziona scheme `ChironeGestionale`.
3. Build & Run su macOS.

## Requisiti
- macOS recente
- Xcode recente (consigliata ultima stabile)

## Limiti attuali
- Coverage test ancora parziale sui flussi critici ad alta frequenza
- Audit trail interno ancora da completare
- Workflow OSS (template issue/PR, quality gates CI) in consolidamento

## Sicurezza e dati clinici
- L'app è local-first e non richiede cloud.
- Non usare dati reali in ambienti non protetti.
- Per vulnerabilità: vedi `SECURITY.md`.

## Contribuire
Linee guida in `CONTRIBUTING.md`.

## Licenza
MIT. Vedi `LICENSE`.

## Clinical Use Notice
Chirone non è dichiarato come dispositivo medico certificato. È responsabilità del professionista verificare i dati clinici prima di decisioni diagnostiche o terapeutiche. Dettagli in `CLINICAL_USE_NOTICE.md`.
