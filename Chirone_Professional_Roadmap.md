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
- [ ] Policy retention + purge controllata (audit e dati operativi derivati).
- [ ] Mappa di tracciabilità `GDPR_Roadmap.md` -> task codice.
- [ ] Report interno “compliance readiness” per release candidate.

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
  - [ ] Test end-to-end “visita completa” (anagrafica -> note -> terapia -> esami -> referto).

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
  - [ ] Collegare milestone P0/P1/P2 GDPR a task codice.
  - [ ] Policy retention e purge controllata.
  - [x] Baseline retention audit log implementata (finestra temporale + cap record).
- [ ] Hardening crittografia e backup
  - [ ] Verifica periodica restore automatizzata (test fixture).
  - [ ] Versioning formato backup + migrazioni documentate.

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
  - [ ] Shortcut azioni principali.
  - [ ] Command palette clinica.
- [ ] Multi-window impeccabile
  - [ ] Stato menu sempre coerente.
  - [ ] Ripristino sessione finestre.
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
  - [ ] Benchmark con migliaia di note/esami.
  - [ ] Profiling memory/CPU su export PDF e timeline.
- [ ] Documentazione tecnica viva
  - [ ] ADR architetturali aggiornati.
  - [ ] Changelog orientato a clinici e contributori OSS.

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
