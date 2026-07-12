# ERP Full-Export Contract

Recorded: 2026-07-13  
Status: implemented; waiting for a complete production export

The available ERP artifact is a 26-table SQLite snapshot. The production ERP
uses MySQL, so the migration now has a source-export contract that can validate
a future credential-free MySQL/JSON export without connecting to the database
or receiving credentials.

`scripts/erp_export_contract.py` verifies:

- manifest format and immutable source hash;
- all table names and safe `tables/<name>.json` paths;
- schema coverage against the 75-table ERP initializer;
- per-table row counts and SHA-256 hashes;
- primary-key identity for non-empty tables;
- recursive removal/rejection of password, token, secret, private, credential,
  IP, and raw database-DSN values;
- missing and extra tables as explicit scope findings.

The current rehearsal emits `source-export-contract.json` with:

```text
schema_tables: 75
export_tables: 26
present_tables: 26
missing_tables: 49
verified_rows: 120
state: source_export_incomplete
promotion_authorized: false
```

Once a complete export is supplied, the same contract can report
`ready_for_source_import`; it still does not promote rows. The existing
redacted staging, native domain importers, parity checks, accounting links,
backup/restore, and business-acceptance gates remain mandatory afterward.
