# Chirone Release Policy

## Obiettivo
Rilasciare versioni stabili, tracciabili e clinicamente affidabili con un processo ripetibile.

## Branch model
- `main`: stato integrato corrente.
- `release/x.y.z`: branch di stabilizzazione per una release specifica.
- `hotfix/x.y.z+1`: fix urgente su release già pubblicata.

## Versioning
Semantic Versioning adattato:
- `MAJOR`: cambi incompatibili o refactor architetturali con impatto migrazione.
- `MINOR`: nuove funzionalità backward compatible.
- `PATCH`: bugfix e hardening senza nuove feature.

Formato tag: `vX.Y.Z`.

## Release flow
1. Freeze feature su `main`.
2. Crea `release/x.y.z`.
3. Esegui quality gate completo:
   - build verde;
   - test unit/UI pass;
   - nessun warning regressivo;
   - verifica manuale flussi clinici core;
   - review sicurezza/compliance.
4. Aggiorna changelog e note di rilascio.
5. Tagga `vX.Y.Z` su commit approvato.
6. Merge `release/x.y.z` in `main`.

## Hotfix flow
1. Crea `hotfix/x.y.z+1` dal tag di produzione.
2. Applica patch minima isolata.
3. Esegui quality gate minimo obbligatorio su area impattata.
4. Tagga nuova patch release.
5. Merge hotfix su `main`.

## Quality gate obbligatorio
- Build Debug/Release riuscita.
- Suite test senza regressioni.
- Nessun warning nuovo in target app.
- Checklist DoD task critici completata.
- Verifica impatto sicurezza/compliance documentata.

## Release notes
Ogni release deve includere:
- Novità funzionali.
- Bugfix.
- Migrazioni o azioni richieste.
- Note sicurezza/compliance rilevanti.

## Rollback
- Conservare tag release precedenti.
- In caso di regressione critica: rollback al tag stabile precedente + hotfix branch dedicato.
