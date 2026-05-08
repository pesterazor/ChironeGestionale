# Contributing to Chirone Gestionale

Grazie per il contributo. Questo progetto richiede standard elevati su qualità codice, sicurezza e affidabilità clinica.

## Flusso PR
1. Apri una issue (bug/feature) prima di implementazioni ampie.
2. Crea un branch dedicato.
3. Mantieni commit atomici e descrittivi.
4. Apri una PR con contesto, test e impatti.
5. Attendi review e risolvi i commenti prima del merge.

## Branch strategy
- `main`: branch stabile.
- `feat/<short-name>`: nuove funzionalità.
- `fix/<short-name>`: bugfix.
- `chore/<short-name>`: manutenzione, tooling, docs.

## Convenzioni commit
Formato consigliato:
- `feat: ...`
- `fix: ...`
- `docs: ...`
- `test: ...`
- `refactor: ...`
- `chore: ...`

Esempio: `fix: handle empty latest clinical note in report narrative`

## Standard minimi PR
- Build locale riuscita
- Nessuna regressione funzionale nota
- Test aggiunti/aggiornati quando applicabile
- Documentazione aggiornata (se comportamento utente/tecnico cambia)
- Impatto sicurezza/compliance valutato

## Checklist reviewer
- Correttezza funzionale su casi principali ed edge
- Assenza di regressioni su dati/sicurezza
- Coerenza con stile Swift/SwiftUI del progetto
- Qualità naming/struttura e leggibilità
- Copertura test adeguata al rischio della modifica

## Ambito delle modifiche
Evita PR “miscellanee”: separa refactor, bugfix e feature in PR distinte quando possibile.

## Segnalazione vulnerabilità
Per issue di sicurezza, non aprire issue pubbliche: usa la procedura in `SECURITY.md`.
