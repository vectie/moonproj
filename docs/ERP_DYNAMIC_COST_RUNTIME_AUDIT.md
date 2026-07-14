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
coverage. It also exposes the source-compatible
`/api/company/source/cost/dynamic-cost/:id/remarks` observation for an imported
cost subject. The Rabbita `/dynamic-cost` screen renders the source columns and
summary while retaining the designer table as an offline fallback. The
source-compatible `/api/company/source/cost/milestones/:id/check` read also
preserves the early-payment warning contract and returns a covered 404 when
the available export has no `cb_contract_milestone` row.

The source mutation family now has a bounded command projection as well:
`POST /api/company/cost/dynamic-cost` translates source fields into an
idempotent local cost row, while `PUT` and `DELETE`
`/api/company/source/cost/dynamic-cost/:id` update or tombstone only
command-owned rows. Imported `cb_cost` rows remain read-only; command rows are
merged into the dynamic-cost read with `sourceKind=command` and explicit
no-cash/accounting/tax markers.

## Evidence

- PostgreSQL source read: seven rows, six end-cost rows, target
  `35,900,000`, dynamic `36,350,000`, deviation `-1.2535%`, and coverage
  `cb_cost=7`.
- Authenticated service smoke asserts the formula result and source coverage;
  read-model endpoint probing returns the same values.
- The parity matrix marks the source `GET /dynamic-cost`,
  `GET /dynamic-cost/:id/remarks`, and `GET /milestones/:id/check` handlers as
  `connected_cost_source_read`.
- The remarks probe preserves `CB-101`/`建安工程`, `cb_cost=7` coverage, and
  non-authorizing/non-persisting metadata.
- The milestone-check probe returns source-compatible `43001` for a missing
  milestone rather than inventing a payment warning or milestone row.
- Service and trusted-gateway smokes create, replay, update, read back, and
  void a source-shaped dynamic-cost command row.

## Remaining gate

1. Accept project scope and production identity for cost reads.
2. Obtain owner-approved CBS/version semantics before treating imported cost
   rows as target-owned.
3. Keep remarks writes, milestone state/trigger writes, budget consumption,
   accounting, cash, tax, and period-close effects separately authorized;
   imported dynamic-cost rows remain read-only.
