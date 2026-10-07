# Fixture dei backup Beck

I tre JSON contengono esclusivamente un paziente sintetico denominato `Legacy Test`.
Password di test: `BeckFixturePassword`.

- `beck-legacy-schema2.json`: envelope v1, schema 2, senza chiavi delle scale psicometriche.
- `beck-invalid-responses-schema3.json`: schema 3 con un'opzione BDI-II fuori intervallo nell'item 21.
- `beck-missing-fields-schema3.json`: schema 3 senza i campi Beck obbligatori.

Sono fixture cifrate fisse, generate con Python `cryptography`, AES-256-GCM, PBKDF2-HMAC-SHA256 (600000 iterazioni), nonce e salt casuali. Permettono di verificare il ripristino di dati legacy e il rifiuto dei dati malformati prima della cancellazione dell'archivio esistente. Non contengono dati clinici reali né chiavi dell'utente.

Le fixture `madrs-*.json` estendono la copertura a schema 3 e schema 4. `madrs-valid-schema4.json` contiene una valutazione Beck e una MADRS valida (risposte `[0,1,2,3,4,5,6,1,3,5]`, valutatore sintetico), date ISO-8601 e AAD legacy. Usa la stessa password di test e chiave, salt e nonce rigenerati; verifica il ripristino e la riesportazione verso lo schema 5 con date numeriche senza perdita di precisione.
