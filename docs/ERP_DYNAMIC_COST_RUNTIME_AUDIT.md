# ERP Dynamic-Cost Runtime Audit

Recorded: 2026-07-15
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

The source mutation family now has a native MoonBit command projection as well:
`POST /api/company/cost/dynamic-cost` translates source fields into an
idempotent `dynamic_cost_command` projection, while `PUT` and `DELETE`
`/api/company/source/cost/dynamic-cost/:id` update or tombstone only
command-owned rows. Imported `cb_cost` rows remain read-only; command rows are
merged into the dynamic-cost read with `sourceKind=command`, immutable
revisions, audit receipts, and explicit no-cash/accounting/tax markers.

Rabbita now renders the source create form on `/dynamic-cost` with project
scope `proj-0001`, cost code/name/level/parent, A/D/E/F/G amount fields, and
remarks. Submission uses the same source-shaped native command, then reloads
the live read model so the new command row is visible without a fixture
fallback. The page reports the CBS/budget/financial no-effect boundary next to
the form. It now also loads the PostgreSQL project list for source-style scope
switching, exposes the source remarks read for each cost row, and provides CSV
and XLSX exports of the selected project’s current projection.

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
- The shell-only `scripts/company_postgres_dynamic_cost_smoke.sh` and native
  gateway smoke create, replay, update, read back, protect an imported row,
  and void a source-shaped dynamic-cost command row.
- Service and trusted-gateway smokes also create, replay, update, trigger,
  check, and tombstone command-owned contract milestones; imported milestone
  rows remain read-only.

## Remaining gate

1. Accept project scope and production identity for cost reads.
2. Obtain owner-approved CBS/version semantics before treating imported cost
   rows as target-owned.
3. Keep remarks writes, budget/CBS consumption, accounting, cash, tax, and
   period-close effects separately authorized; milestone command projections
   are currently cash/accounting/tax-neutral and imported dynamic-cost rows
   remain read-only.
