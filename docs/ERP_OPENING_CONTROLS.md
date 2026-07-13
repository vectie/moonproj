# ERP Opening-Control Boundary

Recorded: 2026-07-13
Source: `../erp/erp_new`
Target: this repository

Opening controls are an explicit company-owned reconciliation boundary. They
are not balances inferred from operational rows, and they do not post a
ledger, release cash, file tax, or close a period.

`scripts/erp_opening_control_plan.py` accepts only a reviewed
`moonproj.erp.opening-control-map.v1`. Each control names a metric, domain,
dimension, non-negative integer value, tolerance, and unit. Duplicate metrics,
negative values, missing identity, unreviewed maps, and secret-shaped keys fail
closed. The planner emits a versioned
`moonproj.erp.opening-control-plan.v1` while retaining the source snapshot,
mapping version, and run identifier.

`cmd/opening_control` feeds that plan to the native `migration/control`
`OpeningControlSet`. The native set rejects duplicate or negative controls and
compiles a deterministic shadow expectation set. The command emits the normal
`moonproj.erp.domain-promotion.v1` receipt under cohort
`opening-control-v1`; every candidate preserves the exact value, tolerance,
unit, dimension, and control state. Its accounting, cash, and period flags are
false.

The durable adapters are opt-in. The SQLite rehearsal accepts the twenty-sixth
argument, and the PostgreSQL cohort runner accepts the twenty-fourth argument:

```text
scripts/fixtures/opening_control_mapping.example.json
```

The wrappers run native promotion, projection apply, exact candidate parity,
and an identical replay. `scripts/company_opening_control_parity.py` compares
the complete candidate, not only source identity, so a changed amount,
tolerance, unit, or dimension is a mismatch. The synthetic fixture contains
five reviewed controls (trial balance, cash, receivable, payable, and tax),
and is evidence of the boundary only; no production opening workbook or
business-owner acceptance is claimed.

Production acceptance still requires a named finance owner, an approved
opening workbook by entity/book/currency/account/dimension, reconciliation to
the source export, and an explicit decision about which opening journal or
subledger events—if any—may follow the control gate.
