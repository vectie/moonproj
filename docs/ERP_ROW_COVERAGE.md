# ERP Row-Coverage Ledger

Recorded: 2026-07-13  
Status: implemented for the available snapshot

Aggregate projection counts are not enough to prove a migration covered every
source row. `scripts/erp_row_coverage.py` now reads the credential-safe export
and all native promotion/evidence receipts in a rehearsal work directory.

It records, per source table:

- source row count and primary-key identity set;
- direct source identities present in accepted native receipts;
- structurally covered rows for deliberately aggregated importers (workflow
  steps, investment indexes, and grouped parameter options);
- covered and uncovered rows;
- an explicit `covered`, `empty`, or `uncovered` state.

The current fixture produces:

```text
source_tables: 26
source_rows: 120
covered_rows: 120
uncovered_rows: 0
state: row_coverage_verified
promotion_authorized: false
```

This ledger proves disposition coverage, not business acceptance. A covered row
may be typed evidence or a quarantined state exception; each domain still needs
its own parity, authority, accounting, and owner-acceptance gates.
