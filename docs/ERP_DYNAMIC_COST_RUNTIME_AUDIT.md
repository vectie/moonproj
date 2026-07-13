# ERP Dynamic-Cost Runtime Audit

Recorded: 2026-07-14
Source: `../erp/erp_new`
Target: this repository

## Finding

The source `/dynamic-cost` route calculates five cost columns from `cb_cost`:

- `A` target cost;
- `B = D + E + F + G` dynamic cost;
- `C = (A - B) / A × 100` deviation percentage;
- `H = A - B` layout spare;
- `D/E/F/G` contract change, actual cost, budget, and estimated change.

The target now exposes the fixed read
`/api/company/cost/dynamic-cost?projGuid=proj-0001`. It preserves seven
imported `cb_cost` rows, six end-cost rows, cost hierarchy, remarks, and source
coverage. The Rabbita `/dynamic-cost` screen renders the source columns and
summary while retaining the designer table as an offline fallback.

## Evidence

- PostgreSQL source read: seven rows, six end-cost rows, target
  `35,900,000`, dynamic `36,350,000`, deviation `-1.2535%`, and coverage
  `cb_cost=7`.
- Authenticated service smoke asserts the formula result and source coverage;
  read-model endpoint probing returns the same values.
- The parity matrix marks the source `GET /dynamic-cost` handler as
  `connected_cost_source_read`.

## Remaining gate

1. Accept project scope and production identity for cost reads.
2. Obtain owner-approved CBS/version semantics before treating imported cost
   rows as target-owned.
3. Keep dynamic-cost create/update/delete, remarks writes, budget consumption,
   accounting, cash, tax, and period-close effects separately authorized.
