# Chirone Gestionale - Open-Source Professional Roadmap

Stato documento: operativo
Ultimo aggiornamento: 2026-05-07
Visione: costruire il miglior gestionale clinico macOS open-source per professionisti della salute mentale, unendo eccellenza UX, sicurezza, affidabilità clinica e una community tecnica sana.

## Regole di tracking
- `[ ]` non fatto, `[x]` completato.
- Ogni blocco ha: `Stato`, `Owner`, `Target`, `Completamento`, `Note`.
- Non iniziare priorità inferiori senza baseline solida su priorità superiori.

---

## Snapshot attuale

### Punti già raggiunti
- [x] Core macOS nativo (SwiftUI + SwiftData) con scheda paziente dedicata.
- [x] Timeline clinica, terapia, esami ematochimici con calcoli derivati.
- [x] Sicurezza base avanzata: lock app, cifratura dati sensibili, backup cifrato, restore.
- [x] Referto PDF con anteprima ed esportazione.

### Gap chiave per diventare "eccezionale e desiderabile"
- [ ] Maturità open-source (governance, contribution flow, quality gates, release policy).
- [ ] Affidabilità clinica totale sui flussi ad alta frequenza.
- [ ] Tooling professionale (audit trail, test suite ampia, performance real-world).
- [ ] Funzionalità distintive pro (decision support, automazioni utili, plugin ecosystem).

---

## PRIORITÀ P0 - Fondazioni Open-Source Esemplari
Stato: `DA AVVIARE`
Owner: `____`
Target: `2026-06-10`
Completamento: `____`
Note: `Questa priorità abilita scalabilità del progetto e contributi esterni di qualità.`

### Obiettivo grande
Rendere Chirone un progetto OSS affidabile, trasparente e facile da contribuire, senza compromettere sicurezza e qualità clinica.

### Sottopunti essenziali
- [ ] Governance e documentazione core
  - [x] `README.md` professionale: vision, feature, screenshot, quick start, limiti attuali.
  - [x] `CONTRIBUTING.md` con flusso PR, branch strategy, convenzioni commit, checklist reviewer.
  - [x] `CODE_OF_CONDUCT.md` e `SECURITY.md` (responsible disclosure).
  - [x] `LICENSE` chiara e coerente con obiettivi uso clinico/open-source.
- [ ] Issue/PR templates
  - [x] Bug template con passi riproduzione, expected/actual, log richiesti.
  - [x] Feature template con use-case clinico e criteri accettazione.
  - [x] PR template con test eseguiti, impatto dati, impatto sicurezza.
- [ ] Qualità minima automatizzata
  - [x] CI build + test su push/PR.
  - [x] Regole warning policy (evitare regressioni warning).
  - [x] Job static checks (formattazione, lint ove applicabile).

---

## PRIORITÀ P1 - Clinical Core Reliability (senza attrito)
Stato: `IN CORSO`
Owner: `____`
Target: `2026-06-30`
Completamento: `____`
Note: `Focus: workflow giornaliero psichiatra.`

### Obiettivo grande
Garantire che i flussi clinici principali siano veloci, robusti, prevedibili e senza perdita dati.

### Sottopunti essenziali
- [ ] Timeline clinica
  - [x] Retrodatazione data/ora su nuova nota.
  - [x] Retrodatazione opzionale anche in modifica nota esistente.
  - [x] Sorting stabile e testato su note con timestamp uguali.
- [ ] Inserimento dati critici
  - [x] Stabilizzazione editing tabella esami ematochimici.
  - [x] Copertura test UI su passaggio cella->cella e commit valori.
  - [x] Presidi anti-regressione per focus/editing AppKit-SwiftUI bridge.
- [ ] Referto clinico
  - [x] Date coerenti `dd/MM/yyyy`.
  - [x] Note cliniche senza troncamenti.
  - [x] Coerenza narrativa completa su casi edge (campi vuoti, dati incompleti).

---

## PRIORITÀ P2 - Sicurezza, Audit e Compliance Operativa
Stato: `IN CORSO`
Owner: `____`
Target: `2026-08-01`
Completamento: `____`
Note: `In sinergia con GDPR_Roadmap.md.`

### Obiettivo grande
Portare Chirone da "sicuro tecnicamente" a "compliant e verificabile operativamente".

### Sottopunti essenziali
- [ ] Audit trail tecnico/clinico
  - [ ] Eventi minimi: apertura/chiusura cartella, export referto, backup/restore, lock/unlock.
  - [ ] Nessuna PHI in chiaro nei log.
  - [ ] Viewer interno audit (filtro per data/tipo evento).
- [ ] Compliance workflow
  - [ ] Collegare milestone P0/P1/P2 del file `GDPR_Roadmap.md` a task implementativi nel codice.
  - [ ] Export per diritto di accesso/portabilità (formato strutturato).
  - [ ] Policy retention e purge controllata.
- [ ] Hardening crittografia e backup
  - [ ] Verifica periodica restore automatizzata (test fixture).
  - [ ] Versioning formato backup + migrazioni documentate.

---

## PRIORITÀ P3 - Mac UX Pro (desiderabilità reale)
Stato: `DA AVVIARE`
Owner: `____`
Target: `2026-09-15`
Completamento: `____`
Note: `Obiettivo: piacere d’uso superiore alle alternative generiche.`

### Obiettivo grande
Far percepire Chirone come app "nativa Mac eccellente" per professionisti esigenti.

### Sottopunti essenziali
- [ ] UX di velocità
  - [ ] Shortcuts da tastiera per azioni principali (nuova nota, salva, referto, nuova terapia).
  - [ ] Quick command palette clinica (azioni frequenti).
- [ ] Multi-window impeccabile
  - [ ] Stato comandi menu sempre corretto (già migliorato, da consolidare con test).
  - [ ] Ripristino sessione finestre cliniche.
- [ ] Design professionale minimal
  - [ ] Gerarchia visiva uniforme in tutte le sezioni cliniche.
  - [ ] Miglioramento feedback micro-interazioni (salvataggi, validazioni, warning).

---

## PRIORITÀ P4 - Clinically Smart Features (differenziazione)
Stato: `DA AVVIARE`
Owner: `____`
Target: `2026-11-01`
Completamento: `____`
Note: `Solo dopo P0-P3 solidi.`

### Obiettivo grande
Aggiungere funzioni "wow" realmente utili al lavoro clinico, evitando complessità inutile.

### Sottopunti essenziali
- [ ] Monitoraggi intelligenti farmaco-correlati
  - [ ] Reminder su litio/valproato/carbamazepina/lamotrigina con regole temporali.
  - [ ] Evidenza valori critici e trend longitudinali.
- [ ] Template e automazioni cliniche
  - [ ] Template note per visita di controllo/primo accesso/urgenza.
  - [ ] Bozza relazione clinica guidata con revisione obbligatoria manuale.
- [ ] Ecosistema modulare
  - [ ] Definizione interfacce `PatientCore`.
  - [ ] Primo plugin (Scheduling o Billing) con contratto stabile.

---

## Priorità trasversali (sempre attive)
- [ ] Test strategy evolutiva
  - [ ] Unit test dominio clinico/sicurezza.
  - [ ] UI test flussi critici end-to-end.
- [ ] Performance su dataset reali
  - [ ] Benchmark con migliaia di note/esami.
  - [ ] Profiling memory/CPU su export PDF e query timeline.
- [ ] Documentazione tecnica viva
  - [ ] ADR aggiornati su decisioni architetturali.
  - [ ] Changelog orientato a clinici e contributori OSS.

---

## Backlog strategico (post-v1)
- [ ] Integrazione calendario esterno con consenso esplicito.
- [ ] OCR allegati clinici + ricerca full-text.
- [ ] Dashboard outcome longitudinali e aderenza monitoraggi.
- [ ] Multi-professionista con ruoli granulari e segregazione accessi.
- [ ] Sincronizzazione multi-dispositivo con modello zero-knowledge.

---

## Definizione di Done (DoD)
Un task è completato solo se:
- [ ] comportamento verificato manualmente sui casi principali e edge.
- [ ] build verde senza warning regressivi.
- [ ] test aggiunti/aggiornati dove applicabile.
- [ ] documentazione utente/tecnica aggiornata.
- [ ] impatto sicurezza/compliance valutato e annotato.
