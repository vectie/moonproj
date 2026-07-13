# ERP Investment Runtime Audit

Recorded: 2026-07-13  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source investment route exposes feasibility versions, grouped plan indices,
profit summary values, and dimension metadata. The available credential-safe
export contains one current version for `proj-0001` and 26 indices across five
dimensions: key points, tax, financing, investment, and carry-over.

The target now exposes source-compatible read boundaries:

| Source surface | Target endpoint | Target state |
|---|---|---|
| Project versions | `/api/company/investment/projects/:id/versions` | source-compatible read |
| Version indices | `/api/company/investment/versions/:id/indices` | source-compatible read |
| Profit summary | `/api/company/investment/projects/:id/profit-summary` | source-compatible read |
| Dimension metadata | `/api/company/investment/meta/dimensions` | source-compatible read |
| Sensitivity scenarios | `/api/company/investment/projects/:id/sensitivity` | deterministic, analytics-only read |

Rows preserve source field names and are marked `sourceKind=imported`. No Excel
import, version creation/activation, index update, valuation, cash movement,
or accounting posting is enabled by this slice.

The Rabbita `/investment` screen now loads the current `proj-0001` version,
flattens the five grouped dimensions and 26 indices into the designer table,
and renders the imported investment, revenue, cost, net-profit, margin, and IRR
summary. It also loads six deterministic sensitivity scenarios and keeps the
original project comparison table as an offline fallback.

## Evidence

- PostgreSQL service smoke returns one current version, 26 grouped indices,
  five dimension groups, and the source profit summary (`revenue=18500`,
  `netProfit=2890`, `irr=14.8`).
- The parity matrix marks the five source investment GET handlers as
  `connected_investment_read`.
- The sensitivity read reports one current-version and 26 index rows with no
  provider execution, persistence, or authority effect.
- The parity matrix marks `/investment` as `connected_investment_read`; the
  project-scope and production-identity scenario remains open.
- Existing native investment valuation, performance, and benchmark boundaries
  remain separate reviewed analytics gates; they do not authorize source-row
  ownership or cash/accounting effects.

## Remaining source routes

The source Excel/import and profit-cockpit routes were re-audited against the
current export. `tzsy_excel_import`, `tzsy_excel_sheet`, `tzsy_profit_table`,
`tzsy_plan_line`, and `tzsy_subject_mapping` are not present in the controlled
PostgreSQL source cohort. Consequently the import list/detail, bridge plan,
index-upsert preview, profit-table, plan-line preview/list, subject-mapping,
and profit-cockpit reads cannot produce source rows yet. The original
`profit-cockpit` handler returns a covered `41002` when no imported profit table
exists, which is the correct boundary to preserve rather than filling the
screen with the designer snapshot.

The original `profit-actual` handler is also deliberately not promoted: it
depends on absent sales, expense, split, change, CBS, and plan-version tables
and simulates values when those tables are sparse. The already connected
`profit-actual-v2` read remains the explicit empty-CBS observation. These
routes stay gated on the missing 49-table export and owner-approved calculation
semantics.

## Remaining gate

1. Bind the reads to the full investment browser scenario and production
   identity, including project scope and version ownership.
2. Obtain the missing investment/source export rows and owner-approved model
   semantics before accepting imported values as target-owned.
3. Keep Excel import, activation, index mutation, valuation, cash release,
   accounting, tax, and period-close actions separately authorized.
