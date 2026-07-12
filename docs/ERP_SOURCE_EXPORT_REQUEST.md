# ERP Source-Export Request

Recorded: 2026-07-13  
Status: generated handoff; source export pending

The available artifact is a 26-table snapshot, while the authoritative ERP
schema defines 75 tables. `scripts/erp_source_export_request.py` generates a
machine-readable request for exactly the 49 missing tables, using the seven
ordered schema waves and their capability IDs.

The request requires a read-only, credential-free export with:

- empty tables included;
- primary-key metadata for non-empty tables;
- per-table SHA-256 hashes and a source snapshot hash;
- redacted JSON arrays;
- password, token, secret, credential, private-key, and network fields removed;
- no target promotion or cutover authorization.

Each rehearsal emits `source-export-request.json` with state
`awaiting_source_export`. The resulting bundle can be checked by
`scripts/erp_export_contract.py` before raw staging or domain promotion.
