# ERP Dashboard Runtime Audit

Recorded: 2026-07-14
Source: `../erp/erp_new`
Target: this repository

## Finding

The source cockpit is a seven-handler read surface, not a single summary
query:

| Source surface | Source route | Target state |
|---|---|---|
| Group overview | `GET /dashboard/group/overview` | bounded source read |
| Stage funnel | `GET /dashboard/group/funnel` | bounded source read |
| Top anomalies | `GET /dashboard/group/top-anomalies` | bounded source read |
| Project KPI | `GET /dashboard/project/:projGuid/kpi` | bounded source read |
| Project anomalies | `GET /dashboard/project/:projGuid/anomalies` | bounded source read |
| Group cockpit v2 | `GET /dashboard/v2/group` | bounded source read |
| Group cockpit v3 | `GET /dashboard/v3/group` | bounded source observation; full cross-domain parity gated |

The source implementation reads 30 unique tables. The controlled export has
14 of them and 16 are absent:

- Present in the export: `cb_contract`, `cb_cost`, `cb_expense_split`,
  `cb_htfk_apply`, `cb_htfkplan`, `ep_project`, `jd_task`, `mu_business_unit`,
  `proj_lifecycle_instance`, `proj_lifecycle_stage`, `tzsy_plan_index`,
  `tzsy_version`, `vcb_expense`, and `wf_process_instance`.
- Absent from the export: `cb_plan_version`, `cb_r_master`, `cb_subject_dict`,
  `fund_plan`, `invoice_in`, `invoice_out`, `proj_progress`, `sale_contract`,
  `sale_customer`, `sale_mortgage`, `sale_refund`, `sale_revenue`,
  `sale_subscription`, `sys_warning`, `tender_award`, and `tender_plan`.

The available rows now support the bounded v1 overview/funnel/KPI/anomaly
reads and a scoped v2 KPI/payment-trend/stage/warning read. They cannot
support the full v3 cockpit without sales, funds, invoices, tender, warning,
and CBS data. Empty source tables must remain empty; the target must not
manufacture revenue, cash, health, warning, or risk values.

## Target evidence

- `frontend/main/main.mbt` renders the source-shaped KPI/funnel/risk layout,
  calls `/api/company/summary` for adapter status, then loads the bounded
  dashboard reads for live KPI, funnel, anomaly, and scoped v2 values.
- `scripts/company_postgres_service.py` exposes the five bounded v1 routes and
  `/api/company/dashboard/v2/group` plus `/api/company/dashboard/v3/group`,
  with source coverage and missing-table metadata on every response. The v3
  aggregate route now preserves the source
  response shape over imported rows, returns explicit missing/empty-table
  coverage, and remains non-authorizing; the development read-model server
  exposes fixed v1/v2/v3 reads, while Rabbita mounts the v1 and v2 reads and
  keeps v3 API-only.
- Rabbita now loads the group overview, stage funnel, top-anomaly, and v2
  reads sequentially. Valid v1 responses replace the designer
  KPI/funnel/risk fixtures, while valid v2 responses render a separate
  read-only KPI/payment-trend/stage/warning panel. A failed or empty v2 read
  shows an explicit source-gap state and never falls back to management
  fixtures. Production identity, browser acceptance, and owner reconciliation
  remain pending. The v3 aggregate is API-connected as an observation only; it
  is not mounted in Rabbita and is not accepted as full cockpit parity while
  its cross-domain source tables are absent.
- Core report reads are not dashboard parity. A report overview can provide
  reconciled tables, but it does not reproduce the source cockpit's scoped
  KPIs, month trend, stage distribution, anomaly ranking, or health breakdown.

## Revised gate

1. Make source coverage, scope (`buGuid`/`projGuid`), money units, date basis,
   and missing-data status explicit in every response. Do not use fixture or
   synthetic values in a connected cockpit response.
2. Run browser acceptance of the bounded v1 reads through the production
   identity/entity scope boundary, including project KPI/anomaly deep links.
3. Obtain the complete redacted export (or owner-approved empty-data
   dispositions) before accepting the v3 cross-domain aggregate as a
   management KPI surface. The v2 and v3 reads are limited to the source rows
   currently present; full v3 reconciliation requires sales/fund/invoice/
   tender/warning/CBS source coverage.
4. Retain a clearly labelled fallback only for offline development, and run
   browser acceptance before counting the dashboard as functional parity.
5. Obtain operations/finance owner reconciliation for KPI definitions and
   anomaly rules before using cockpit values for management, cash, tax, or
   close decisions.
