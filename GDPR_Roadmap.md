# Chirone GDPR Roadmap

Stato: bozza operativa iniziale  
Ultimo aggiornamento: 2026-04-28

## P0 (Critico prima del rilascio reale)

- [ ] Ruoli privacy formalizzati
  - Titolare del trattamento
  - Eventuali Responsabili ex art. 28 (fornitori, cloud, PEC/email, assistenza tecnica)
  - Registro nomine e contratti

- [ ] Registro dei trattamenti completato
  - Finalità
  - Basi giuridiche
  - Categorie dati (inclusi dati sanitari)
  - Tempi di conservazione
  - Misure tecniche e organizzative

- [ ] DPIA (Valutazione d'impatto)
  - Analisi rischi su riservatezza, integrità, disponibilità
  - Misure di mitigazione documentate
  - Riesame periodico

- [ ] Informativa privacy e consenso
  - Testi informativa paziente
  - Tracciamento presa visione/consenso quando richiesto
  - Distinzione tra base giuridica contrattuale/professionale e consenso esplicito ove necessario

- [ ] Audit log di sicurezza
  - Log di accessi all'app
  - Log eventi critici: export backup, restore backup, lock/unlock
  - Nessun dato clinico in chiaro nei log
  - Timestamp affidabili

- [ ] Incident response / data breach
  - [x] Procedura interna
  - [x] Flusso decisionale notifica entro 72h (art. 33)
  - [x] Template di comunicazione

## P1 (Alta priorità subito dopo)

- [ ] Gestione diritti dell'interessato
  - Accesso ai dati
  - Rettifica
  - Esportazione strutturata
  - Cancellazione/limitazione nei limiti normativi

- [ ] Policy di retention e cancellazione
  - Regole per conservazione cartelle cliniche
  - Scadenze e revisione periodica
  - Flusso "soft delete" + purge controllata

- [ ] Hardening accessi
  - Utenti separati (se multi-operatore)
  - Principio del minimo privilegio
  - Opzioni sicurezza sessione avanzate

- [ ] Test periodici di ripristino backup
  - Simulazioni restore documentate
  - Verifica integrità backup
  - Procedura DR (disaster recovery)

## P2 (Miglioramenti continui)

- [ ] Security supply-chain
  - Dipendenze minimali
  - Aggiornamenti periodici
  - Scansioni statiche e secret scan

- [ ] Governance trasferimenti dati
  - Mappatura eventuali trasferimenti extra-UE
  - Clausole e tutele applicabili

- [ ] Formazione operativa
  - Istruzioni al personale
  - Buone pratiche su workstation condivise

## Stato tecnico attuale in Chirone

- [x] Schermata di lock con LocalAuthentication
- [x] Chiave simmetrica in Keychain
- [x] Cifratura campi clinici testuali sensibili
- [x] Backup cifrato con password utente
- [x] Restore da backup cifrato
- [x] Timeout ri-autenticazione configurabile nelle Preferenze

## Prossimo sprint consigliato

1. Implementare audit log tecnico minimale (senza PHI).
2. Aggiungere modulo "Consenso/Informativa" nel profilo paziente.
3. Definire struttura export per diritto di accesso (machine-readable).
