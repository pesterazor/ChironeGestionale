# Chirone Gestionale - Open-Source Professional Roadmap

Stato documento: operativo
Ultimo aggiornamento: 2026-05-08
Visione: costruire il miglior gestionale clinico macOS open-source per professionisti della salute mentale, unendo eccellenza UX, sicurezza, affidabilità clinica e community tecnica.

## Regole di tracking
- `[ ]` non fatto, `[x]` completato.
- Ogni priorità include: `Stato`, `Owner`, `Target`, `Completamento`, `Gate`.
- Non aprire nuove priorità senza aver superato i gate della priorità corrente.

---

## Snapshot reale (analisi tecnica)

### Fondazioni già solide
- [x] Core app nativa macOS con scheda clinica dedicata.
- [x] Flusso clinico base completo (anagrafica, timeline, terapia, esami, referto).
- [x] Sicurezza tecnica già avanzata (lock, cifratura campi sensibili, backup cifrato, restore).
- [x] Audit trail operativo con viewer interno e log redatti.
- [x] Base OSS pronta (README/CONTRIBUTING/SECURITY/template/CI minima).

### Collo di bottiglia attuali
- [ ] Mancanza di “chiusura” esecutiva delle priorità già avviate (stato/gate non aggiornati).
- [ ] Compliance ancora incompleta su retention/purge e allineamento formale GDPR roadmap.
- [ ] Test strategy sbilanciata: buona su punti specifici, non ancora completa e2e sui flussi clinici critici.
- [ ] UX pro ancora senza strato “velocità” (shortcut, command palette, multi-window resilience).
- [ ] Assenza di benchmark prestazionali su dataset realistici.

---

## Piano esecutivo (prossimi 4 sprint)

### Sprint A (stabilizzazione & coerenza)
- [ ] Chiudere formalmente P0 e P1 con gate di uscita verificabili.
- [ ] Allineare stato/completamento priorità con il lavoro già fatto.
- [ ] Consolidare regressioni note e warning policy.

### Sprint B (compliance operativa)
- [x] Policy retention + purge controllata (audit e dati operativi derivati).
- [x] Mappa di tracciabilità `GDPR_Roadmap.md` -> task codice.
- [x] Report interno “compliance readiness” per release candidate.

### Sprint C (UX pro ad alta produttività)
- [ ] Shortcut principali (nuova nota, salva terapia/esami, export referto).
- [ ] Command palette clinica (azioni frequenti a tastiera).
- [ ] Consolidamento multi-window (ripristino sessione, stato comandi menu coerente).

### Sprint D (qualità e scala)
- [ ] Test e2e UI sui flussi ad alta frequenza (dalla selezione paziente al referto).
- [ ] Benchmark performance con dataset massivo (note/esami).
- [ ] Profiling PDF export + query timeline.

---

## PRIORITÀ P0 - Fondazioni Open-Source Esemplari
Stato: `COMPLETATA (da chiudere formalmente)`
Owner: `____`
Target: `2026-06-10`
Completamento: `95%`
Gate:
- [ ] Verifica finale checklist P0 in PR dedicata di chiusura.

### Sottopunti
- [x] Governance e documentazione core.
- [x] Issue/PR templates.
- [x] Qualità minima automatizzata (CI + warning policy + static checks).
- [x] Release policy esplicita (`versioning`, `branch cut`, `hotfix flow`) formalizzata.

---

## PRIORITÀ P1 - Clinical Core Reliability (senza attrito)
Stato: `QUASI COMPLETATA`
Owner: `____`
Target: `2026-06-30`
Completamento: `90%`
Gate:
- [ ] Esecuzione test manuali guidati su 10 casi edge reali.
- [ ] Verifica completa checklist DoD su flussi clinici core.

### Sottopunti
- [x] Timeline clinica
  - [x] Retrodatazione nuova nota.
  - [x] Retrodatazione modifica nota.
  - [x] Sorting stabile con test su timestamp uguali.
- [x] Inserimento dati critici
  - [x] Stabilizzazione editing tabella esami.
  - [x] UI test cella->cella e commit.
  - [x] Presidi anti-regressione bridge AppKit/SwiftUI.
- [x] Referto clinico
  - [x] Date coerenti.
  - [x] Nessun troncamento note.
  - [x] Narrativa robusta su campi incompleti.
- [ ] Hardening finale P1
  - [x] Test end-to-end core (anagrafica -> note -> terapia -> esami).
  - [x] Estendere test end-to-end con export/anteprima referto.

---

## PRIORITÀ P2 - Sicurezza, Audit e Compliance Operativa
Stato: `IN CORSO`
Owner: `____`
Target: `2026-08-01`
Completamento: `70%`
Gate:
- [ ] Policy retention/purge attiva e verificata.
- [ ] Tracciabilità completa con `GDPR_Roadmap.md`.

### Sottopunti
- [x] Audit trail tecnico/clinico
  - [x] Eventi minimi implementati.
  - [x] Nessuna PHI in chiaro.
  - [x] Viewer interno con filtri.
- [x] Compliance workflow (parziale)
  - [x] Export diritto di accesso/portabilità strutturato.
  - [x] Collegare milestone P0/P1/P2 GDPR a task codice.
  - [x] Policy retention e purge controllata.
  - [x] Baseline retention audit log implementata (finestra temporale + cap record).
- [ ] Hardening crittografia e backup
  - [x] Verifica periodica restore automatizzata (test fixture).
  - [x] Versioning formato backup + migrazioni documentate.
  - [x] Validazione coerenza metadata backup (`schemaVersion`, `recordCounts`) in restore.

---

## PRIORITÀ P3 - Mac UX Pro (desiderabilità reale)
Stato: `DA AVVIARE`
Owner: `____`
Target: `2026-09-15`
Completamento: `10%`
Gate:
- [ ] Riduzione misurabile del tempo medio task (shortcut + palette).
- [ ] Nessuna regressione di chiarezza visiva nelle sezioni cliniche.

### Sottopunti
- [ ] UX di velocità
  - [x] Shortcut azioni principali (referto + salvataggi clinici core).
  - [x] Command palette MVP (`⌘K`) per azioni frequenti di navigazione/operatività.
  - [x] Estendere command palette ai comandi clinici avanzati in finestra paziente.
  - [x] Tracciamento metrica locale command palette (azione + latenza open→execute, no PHI).
  - [x] Mini dashboard KPI in Preferenze (mediana latenza + top azioni ultimi 30 giorni).
- [ ] Multi-window impeccabile
  - [x] Stato menu sempre coerente.
  - [x] Ripristino sessione finestre.
- [ ] Design professionale minimal
  - [ ] Gerarchia visiva uniforme.
  - [ ] Micro-feedback coerente (save/validazioni/warning).

---

## PRIORITÀ P4 - Clinically Smart Features (differenziazione)
Stato: `DA AVVIARE`
Owner: `____`
Target: `2026-11-01`
Completamento: `0%`
Gate:
- [ ] Avvio solo dopo chiusura gate P1-P3.

### Sottopunti
- [ ] Monitoraggi intelligenti farmaco-correlati.
- [ ] Template/automazioni cliniche.
- [ ] Ecosistema modulare (plugin contract stabile).

---

## Priorità trasversali (sempre attive)
- [ ] Test strategy evolutiva
  - [ ] Unit test dominio clinico/sicurezza.
  - [ ] UI test e2e flussi critici.
- [ ] Performance su dataset reali
  - [x] Ottimizzazione lettura audit log (reverse scan + early stop) e riduzione enforcement retention ad alta frequenza.
  - [x] Ottimizzazione hot-path tabella esami (indice rowID→index per lookup O(1)).
  - [x] Cache ordinamenti tabella esami (righe/colonne) con invalidazione mirata su cambi `draft`.
  - [x] Paginazione timeline clinica ottimizzata via fetch con `offset/limit` (niente sort completo in memoria).
  - [ ] Benchmark con migliaia di note/esami.
  - [ ] Profiling memory/CPU su export PDF e timeline.
- [ ] Documentazione tecnica viva
  - [ ] ADR architetturali aggiornati.
  - [ ] Changelog orientato a clinici e contributori OSS.

---

## Matrice Tracciabilità GDPR -> Codice
Questa sezione collega `GDPR_Roadmap.md` ai task implementativi concreti in Chirone.
Riferimento operativo: `COMPLIANCE_READINESS.md`.

| GDPR milestone | Stato | Implementazione corrente | Gap residuo | Prossima azione |
|---|---|---|---|---|
| P0 Audit log di sicurezza | `PARZIALE` | AuditTrailService + eventi critici + viewer interno | Manca policy formale retention completa e incident drill | Chiudere task retention/purge completo in P2 |
| P0 Informativa privacy e consenso | `NON AVVIATO` | Nessun modulo dedicato in profilo paziente | Mancano UI/record consenso/informativa | Progettare `ConsentSection` in anagrafica paziente |
| P0 Incident response / data breach | `PARZIALE` | Runbook operativo e template notifica in `INCIDENT_RESPONSE.md` | Manca simulazione periodica tabletop con evidenze | Pianificare drill trimestrale e checklist esito |
| P1 Gestione diritti interessato - Accesso/Esportazione | `PARZIALE` | Export strutturato JSON paziente attivo implementato | Mancano workflow rettifica/cancellazione tracciata | Definire action set diritti in UI + audit eventi |
| P1 Policy retention e cancellazione | `PARZIALE` | Baseline retention audit log implementata | Manca policy clinica dati e purge governata | Introdurre policy configurabile + dry-run/report |
| P1 Test periodici restore backup | `PARZIALE` | Suite test backup/restore con fixture campione e validazione schema envelope | Manca scheduling periodico in CI e fixture estese multi-versione | Estendere pipeline CI con job periodico restore drill |
| P1 Hardening accessi | `PARZIALE` | Lock app + timeout reauth | Manca modello multi-operatore e privilegi | Pianificare modello ruoli post-v1 |
| P2 Security supply-chain | `NON AVVIATO` | CI minima presente | Mancano SCA/secret scan/aggiornamenti dipendenze | Estendere CI con scanning dedicato |

Legenda stato:
- `NON AVVIATO`: nessun artefatto implementativo.
- `PARZIALE`: implementazione presente ma non chiusa a livello compliance.
- `CHIUSO`: requisito soddisfatto con evidenze tecniche/documentali.

---

## Backlog strategico (post-v1)
- [ ] Integrazione calendario esterno con consenso esplicito.
- [ ] OCR allegati clinici + ricerca full-text.
- [ ] Dashboard outcome longitudinali e aderenza monitoraggi.
- [ ] Multi-professionista con ruoli granulari e segregazione accessi.
- [ ] Sincronizzazione multi-dispositivo zero-knowledge.
- [ ] Export CSV viewer audit (metadati redatti).
- [ ] Rotazione e retention audit log (policy temporale + purge).
- [ ] Audit tamper-evident (hash chain locale).

---

## Definizione di Done (DoD)
Un task è completato solo se:
- [ ] Comportamento verificato manualmente su casi principali + edge.
- [ ] Build verde senza warning regressivi.
- [ ] Test aggiunti/aggiornati dove applicabile.
- [ ] Documentazione utente/tecnica aggiornata.
- [ ] Impatto sicurezza/compliance valutato e annotato.
