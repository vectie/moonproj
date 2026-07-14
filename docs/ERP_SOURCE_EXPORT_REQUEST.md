# ERP Source-Export Request

Recorded: 2026-07-13  
Status: generated handoff; source export pending

The available artifact is a 26-table snapshot, while the authoritative ERP
schema defines 75 tables. `cmd/source_export_request`, invoked through
`scripts/erp_source_export_request.sh`, generates a
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
the MoonBit `cmd/export_contract` through `scripts/erp_export_contract.sh`
before raw staging or domain promotion.

If a source owner confirms that an absent table is genuinely empty, record it
through `scripts/erp_empty_disposition.py` and
`docs/ERP_EMPTY_TABLE_DISPOSITION.md`. That alternate handoff still requires
independent zero-row evidence and owner approval for every table; it never
substitutes for payload where rows exist and does not authorize promotion or
cutover.
