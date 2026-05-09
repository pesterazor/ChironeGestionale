# Incident Response & Data Breach Runbook

Stato documento: operativo interno
Data: 2026-05-08
Ambito: Chirone Gestionale (dati clinici locali)

## Obiettivo
Definire una procedura standard per rilevare, valutare e gestire incidenti sicurezza/privacy, incluse eventuali violazioni dati personali (GDPR art. 33/34).

## Ruoli minimi
- Incident Lead: coordina risposta tecnica/organizzativa.
- Privacy Lead: valuta impatto privacy e obblighi notifica.
- Technical Lead: containment, analisi tecnica, recovery.
- Communication Owner: comunicazioni interne/esterne approvate.

## Classificazione severità
- SEV-1: possibile violazione dati sanitari o indisponibilità critica.
- SEV-2: rischio medio, impatto contenuto ma non trascurabile.
- SEV-3: evento minore senza evidenza impatto dati personali.

## Timeline operativa (72h)
### T0 - Rilevazione
- Aprire ticket incidente con timestamp UTC/locale.
- Congelare evidenze (log, stato sistema, versione app).
- Assegnare Incident Lead.

### T0 + 4h - Triage
- Identificare perimetro: sistemi coinvolti, dati potenzialmente impattati.
- Classificare severità preliminare.
- Avviare containment iniziale.

### T0 + 24h - Valutazione rischio
- Confermare se è violazione dati personali.
- Stimare categorie dati, numero interessati, rischi per i diritti/libertà.
- Decisione preliminare su obbligo notifica all'autorità.

### T0 + 48h - Notifica preparata
- Compilare bozza notifica (art. 33) con informazioni disponibili.
- Definire eventuale piano comunicazione interessati (art. 34).

### T0 + 72h - Decisione finale
- Inviare notifica all'autorità se dovuta.
- Registrare motivazione se non si notifica.
- Aprire piano correttivo post-incident.

## Containment tecnico minimo
- Isolare endpoint/processi compromessi.
- Revocare credenziali/token esposti.
- Forzare re-auth locale se necessario.
- Bloccare export/restore finché il rischio non è qualificato.

## Evidenze da raccogliere
- Timestamp eventi chiave.
- Versione app/build coinvolta.
- Estratti log audit rilevanti (senza PHI in chiaro oltre quanto già presente).
- Azioni effettuate e responsabile.

## Template registro incidente (interno)
- Incident ID:
- Data/ora rilevazione:
- Reporter:
- Severità iniziale/finale:
- Sistemi coinvolti:
- Categorie dati coinvolti:
- Numero interessati stimato:
- Containment applicato:
- Esito valutazione notifica art. 33:
- Esito comunicazione art. 34:
- CAPA (azioni correttive/preventive):

## Template notifica autorità (bozza)
- Titolare del trattamento:
- Contatto DPO/referente privacy:
- Natura violazione:
- Categorie e numero approssimativo interessati:
- Categorie e numero approssimativo record:
- Probabili conseguenze:
- Misure adottate/proposte:
- Data e ora scoperta:
- Data e ora notifica:

## Post-incident review (obbligatoria)
- Root cause analysis documentata.
- Lezioni apprese.
- Aggiornamento roadmap sicurezza/compliance.
- Aggiornamento test/monitoring per prevenire recidive.
