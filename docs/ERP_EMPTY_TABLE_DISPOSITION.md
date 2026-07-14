# ERP empty-table disposition contract

The current credential-safe SQLite artifact contains 26 of the 75 tables in
the ERP initializer.  The remaining 49 tables must either arrive in the
requested redacted export or be explicitly accepted as empty by a named source
owner.  This contract records the second case without inventing rows or
granting import/cutover authority.

## Generate the owner template

Use the schema-gap and cohort artifacts produced by the source audit:

```sh
python3 scripts/erp_empty_disposition.py \
  /path/to/schema-gap.json \
  /path/to/schema-cohort-plan.json \
  /tmp/erp-empty-disposition.json \
  --template
```

The template contains exactly the 49 schema-only tables, their capability and
wave assignments, and `pending` dispositions.  It is not evidence of emptiness
and remains `awaiting_owner_disposition`.

## Fill and validate

For each table that the source owner confirms is empty, set:

- the top-level `source_snapshot_hash` to the 64-character hash of the
  credential-safe source snapshot;
- `disposition` to `owner_approved_empty`;
- `source_evidence.row_count` to `0`;
- `source_evidence.table_sha256` to the SHA-256 of the exact `[]\n` table file;
- `owner`, `approved_at` (UTC ISO-8601), `rationale`, and `evidence_ref`.

Tables that still need payload must use `source_export_required`; they cannot
be silently treated as empty.  Validate the completed artifact with:

```sh
python3 scripts/erp_empty_disposition.py \
  /path/to/schema-gap.json \
  /path/to/schema-cohort-plan.json \
  /tmp/validated-empty-disposition.json \
  --input /path/to/owner-filled-disposition.json
```

Validation is fail-closed: it rejects duplicate/missing tables, mismatched
cohort metadata, non-zero row counts, wrong empty-table hashes, missing owner
evidence, non-UTC approval times, and credential-like keys or values.  A fully
approved artifact reports `owner_dispositions_complete`, but always keeps
`promotion_authorized=false` and `cutover_authorized=false`; source identity,
domain mapping, browser acceptance, owner reconciliation, and production gates
remain separate.
