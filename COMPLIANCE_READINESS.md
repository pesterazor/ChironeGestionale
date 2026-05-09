# Compliance Readiness Report (Internal)

Stato documento: operativo interno
Data: 2026-05-08
Ambito: Chirone Gestionale (build macOS locale)

## Obiettivo
Valutare il livello di prontezza compliance/sicurezza prima di un release candidate.

## Sintesi esecutiva
- Stato attuale: **PARZIALE** (buona base tecnica, completamento documentale/procedurale ancora necessario).
- Rischio principale: gap procedurali e organizzativi (non solo tecnici).
- Go/No-Go release candidate clinico reale: **NO-GO** finché i gap P0/P1 GDPR non sono chiusi.

## Evidenze implementate (tecniche)
- Lock app con LocalAuthentication e timeout ri-autenticazione.
- Cifratura campi clinici sensibili.
- Backup cifrato + restore.
- Audit trail con eventi critici e viewer interno.
- Log audit redatti (no PHI in chiaro) + retention policy configurabile.
- Export strutturato per diritto di accesso/portabilità (JSON paziente).

## Gap bloccanti (pre-RC reale)
- Ruoli privacy formalizzati (Titolare/Responsabili art. 28) non documentati in repo.
- Registro trattamenti non finalizzato.
- DPIA non prodotta.
- Modulo informativa/consenso in app non implementato.
- Incident response/data breach runbook non presente.
- Policy retention clinica completa (non solo audit) da formalizzare.
- Test periodici restore automatizzati mancanti.

## Gate di uscita RC compliance
- [ ] Chiusura attività P0 GDPR documentali.
- [ ] Chiusura attività P1 GDPR minime obbligatorie.
- [ ] Esecuzione checklist DoD sicurezza/compliance in release branch.
- [ ] Evidenza test restore e verifica integrità backup.

## Decisione operativa corrente
- Ambiente demo/sviluppo: **GO** con dati sintetici.
- Ambiente clinico reale: **NO-GO** fino a chiusura gate sopra.

## Azioni prioritarie prossimi 14 giorni
1. Aggiungere `INCIDENT_RESPONSE.md` con flow 72h e template notifica.
2. Definire policy retention/purge estesa ai dati clinici operativi.
3. Implementare sezione consenso/informativa nel profilo paziente.
4. Introdurre test fixture automatizzati restore backup.

## Owner e riesame
- Owner: `____`
- Riesame previsto: `____`
