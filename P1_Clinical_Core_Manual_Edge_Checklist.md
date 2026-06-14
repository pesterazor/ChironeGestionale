# P1 Clinical Core - Manual Edge Checklist (10 casi)

Stato: 7/10 PASS automatici — 3 richiedono verifica manuale  
Ultimo aggiornamento: 2026-06-14  
Scope: chiusura gate manuale P1 (Clinical Core Reliability)

## Istruzioni esecuzione
- Ambiente: build `Debug` locale, lock disabilitato solo per test.
- Dataset: paziente nuovo + paziente con storico (>=20 note, >=10 date esami).
- Regola: ogni caso è `PASS` solo con evidenza osservabile e senza warning/errori UI.
- Evidenze: annotare esito + note in tabella sotto.

## Tabella esecuzione

| # | Caso edge | Pass/Fail | Evidenza/Note |
|---|---|---|---|
| 1 | Creazione paziente con campi minimi, apertura cartella clinica immediata | `PASS` | Coperto come setup in ogni UI test automatico (`launchAppForClinicalFlow`) |
| 2 | Nuova nota clinica con testo lungo (>=3000 char), salvataggio e riapertura senza troncamenti | `PASS` | `testLongClinicalNoteIsSavedWithoutTruncation` — 2026-06-14 |
| 3 | Retrodatazione nuova nota su data passata, verifica ordinamento timeline | `MANUALE` | DatePicker macOS non accessibile via XCUITest; verificare manualmente: crea nota, apri DatePicker inline, seleziona data passata, salva, verifica ordine timeline |
| 4 | Modifica nota retrodatata con timestamp uguale ad altra nota, verifica ordinamento stabile | `MANUALE` | Algoritmo coperto dal unit test `testClinicalTimelineSortedUsesDeterministicTieBreaker`; verifica UI end-to-end richiede esecuzione manuale |
| 5 | Inserimento terapia con più farmaci, salvataggio, chiusura/ripertura finestra, persistenza completa | `PASS` | `testMultiMedicationTherapyPersistsAfterWindowReopen` — 2026-06-14 |
| 6 | Tabella esami: inserimento multi-cella rapido (cella->cella), save abilitato correttamente | `PASS` | `testBloodTestsCellToCellEditingEnablesSave` — pre-esistente |
| 7 | Tabella esami: aggiunta/rimozione data con dati esistenti, nessuna corruzione valori | `PASS` | `testBloodTestsAddingColumnPreservesExistingCellValues` — 2026-06-14 |
| 8 | Anteprima referto: date coerenti, narrativa completa anche con campi incompleti | `PASS` | `testReportRendersWithMinimalPatientData` — 2026-06-14 |
| 9 | Multi-window: due pazienti aperti, comandi menu coerenti sulla finestra attiva | `MANUALE` | Apertura seconda finestra paziente non gestita dagli argomenti di lancio UI test; verificare manualmente: apri due pazienti, cambia finestra attiva, verifica che ⌘S salvi il paziente corretto |
| 10 | Autosave nota draft: recupero corretto dopo chiusura inattesa (no duplicazioni) | `PASS` | `testClinicalNoteDraftRestoredAfterWindowClosedWithoutSaving` — 2026-06-14 |

## Criterio di chiusura gate P1
- Tutti i 10 casi `PASS`.
- Nessun crash, nessun freeze UI, nessun warning regressivo in build.
- Aggiornare roadmap: P1 `COMPLETATA`.

## Casi manuali residui (3, 4, 9)
Questi casi non sono automatizzabili con l'infrastruttura XCUITest attuale:
- **Caso 3/4**: `NSDatePicker` in modalità `graphical` non espone elementi tappabili via accessibility tree su macOS 15+.
- **Caso 9**: il launcher UI test apre un singolo paziente per design; il multi-window reale richiede interazione manuale con la lista principale.

Una volta eseguiti e verificati manualmente, aggiornare questa tabella e marcare P1 `COMPLETATA` nella roadmap.
