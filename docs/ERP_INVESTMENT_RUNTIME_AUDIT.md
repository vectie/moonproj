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
| Version/index lifecycle | signed local `POST`/`PUT`/`DELETE` command routes | command-owned candidate projections; imported rows remain read-only |
| Excel index upsert | signed `POST /api/company/investment/excel-imports/:id/index-upsert` and `/source` alias | deterministic dry-run candidate; real insert/update is owner-gated |
| Excel plan-line import | signed `POST /api/company/investment/excel-imports/:id/plan-lines/import` and `/source` alias | deterministic dry-run candidate; durable line insert/replace is owner-gated |
| Subject mappings | signed `PUT /api/company/investment/projects/:id/subject-mappings` and `/source` alias | deterministic dry-run candidate; mapping writes are owner-gated |
| AI explanation | signed `POST /api/company/investment/projects/:id/ai-explain` and `/source` alias | deterministic analytics candidate over the current PostgreSQL version/profit summary; no provider, prompt persistence, or financial effect |

Rows preserve source field names and are marked `sourceKind=imported`. Local
version/index lifecycle commands are explicitly marked `sourceKind=command_candidate`;
they do not mutate imported rows. Excel import, valuation, cash movement, or
accounting posting is not enabled by this slice.

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
- The lifecycle smoke covers signed version create/activate/delete and index
  create/update/delete with idempotent replay and command-owned readback; the
  parity matrix records six `connected_investment_command_candidate` handlers.
- `scripts/company_postgres_ai_explain_smoke.sh` proves the investment
  explanation candidate returns the live `revenue`, `netProfit`, provider/model
  markers, and explicit `provider_execution=false`, `persisted=false`, and
  `authorizing=false` flags without an external model.
- `scripts/company_postgres_investment_smoke.sh` now proves the signed Excel
  index-upsert candidate preserves the source 404 for a missing import and
  rejects `dryRun=false` with an explicit owner-acceptance gate; neither path
  invokes a provider or persists an index.
- The same smoke proves the signed plan-line import candidate preserves the
  source 404 and rejects non-dry-run replacement with no line persistence.
- It also proves the subject-mapping candidate preserves a missing-project 404
  and rejects non-dry-run mapping writes without changing imported mappings.
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
3. Keep Excel upload/import, non-dry-run index/plan-line/mapping writes, valuation,
   cash release, accounting, tax, and period-close actions separately authorized; the
   explanation candidate still
   needs browser/investment-owner acceptance before production enablement and
   any provider-backed explanation requires a separate security/finance gate.
