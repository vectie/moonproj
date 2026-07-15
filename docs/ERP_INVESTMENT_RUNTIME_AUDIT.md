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
| Excel import detail/bridge/preview | `/api/company/investment/excel-imports/:id/...` | source-preserving boundary |
| Profit table and plan-line reads | `/api/company/investment/excel-imports/:id/{profit-table,plan-line-preview}` and `/projects/:id/plan-lines` | source-preserving boundary |
| Subject mappings | `/api/company/investment/projects/:id/subject-mappings` | empty-safe source read |
| Profit cockpit | `/api/company/investment/projects/:id/profit-cockpit` | source-style missing-data boundary |
| Actual-vs-plan profit | `/api/company/investment/projects/:id/profit-actual` | bounded imported-real plus explicitly simulated sparse-plan read |

Rows preserve source field names and are marked `sourceKind=imported`. No Excel
import, version creation/activation, index update, valuation, cash movement,
or accounting posting is enabled by this slice.

The Rabbita `/investment` screen now loads the current `proj-0001` version,
flattens the five grouped dimensions and 26 indices into the designer table,
and renders the imported investment, revenue, cost, net-profit, margin, and IRR
summary. It also loads six deterministic sensitivity scenarios and mounts the
source-compatible `profit-actual` response as an explicit non-authorizing
boundary panel; the original project comparison table remains an offline
fallback.

## Evidence

- Native MoonBit PostgreSQL service smoke returns one current version, 26 grouped indices,
  five dimension groups, and the source profit summary (`revenue=18500`,
  `netProfit=2890`, `irr=14.8`).
- The parity matrix marks 13 source investment GET handlers as
  `connected_investment_read`; the Excel boundary smoke covers absent import
  records, empty plan-line/mapping reads, and the covered cockpit 41002.
- The sensitivity read reports one current-version and 26 index rows with no
  provider execution, persistence, or authority effect.
- `scripts/company_postgres_investment_actual_smoke.sh` seeds a credential-safe
  source-shaped cohort and proves real receipt/payment/expense/loan aggregation,
  explicit sparse-plan simulation labels, operating KPIs, coverage, and
  `authorizing=false` without Python.
- The parity matrix marks `/investment` as `connected_investment_read`; the
  project-scope and production-identity scenario remains open.
- Existing native investment valuation, performance, and benchmark boundaries
  remain separate reviewed analytics gates; they do not authorize source-row
  ownership or cash/accounting effects.

## Remaining source routes

The source Excel/import and profit-cockpit routes were re-audited against the
current export. `tzsy_excel_import`, `tzsy_excel_sheet`, `tzsy_profit_table`,
`tzsy_plan_line`, and `tzsy_subject_mapping` are not present in the controlled
PostgreSQL source cohort. The target nevertheless exposes source-preserving
detail, bridge-plan, index-preview, profit-table, plan-line, mapping, and
cockpit boundaries: absent import records return source-style 404s, plan-line
and mapping reads return explicit empty data with coverage, and the cockpit
returns the covered `41002` when no imported profit table exists. No designer
workbook rows are substituted.

The `profit-actual` handler now ports the source comparison when an imported
`tzsy_profit_table` plan exists: receipts, paid applications, expenses,
contracts, and loans are real source rows; sparse subjects use the source
progress/mapping fallbacks and are marked `simulated=true`. With no plan the
current project still returns source-style `41002` and `simulation=false`.
The read never mutates a plan or creates budget, workflow, provider, cash,
accounting, or tax effects. The already connected `profit-actual-v2` read
remains the explicit empty-CBS observation.

## Remaining gate

1. Bind the reads to the full investment browser scenario and production
   identity, including project scope and version ownership.
2. Obtain the missing investment/source export rows and owner-approved formula
   reconciliation before accepting actual-profit values as target-owned.
3. Keep Excel import, activation, index mutation, valuation, cash release,
   accounting, tax, and period-close actions separately authorized.
