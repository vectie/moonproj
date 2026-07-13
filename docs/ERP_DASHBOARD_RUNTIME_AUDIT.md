# ERP Dashboard Runtime Audit

Recorded: 2026-07-13
Source: `../erp/erp_new`
Target: this repository

## Finding

The source cockpit is a seven-handler read surface, not a single summary
query:

| Source surface | Source route | Target state |
|---|---|---|
| Group overview | `GET /dashboard/group/overview` | not connected |
| Stage funnel | `GET /dashboard/group/funnel` | not connected |
| Top anomalies | `GET /dashboard/group/top-anomalies` | not connected |
| Project KPI | `GET /dashboard/project/:projGuid/kpi` | not connected |
| Project anomalies | `GET /dashboard/project/:projGuid/anomalies` | not connected |
| Group cockpit v2 | `GET /dashboard/v2/group` | not connected |
| Group cockpit v3 | `GET /dashboard/v3/group` | not connected |

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

The available rows can support a bounded overview/funnel/KPI read after the
missing-table decision, but they cannot support the source v2/v3 cockpit
without sales, funds, invoices, tender, warning, and CBS data. Empty source
tables must remain empty; the target must not manufacture revenue, cash,
health, warning, or risk values.

## Target evidence

- `frontend/main/main.mbt` renders the source-shaped KPI/funnel/risk layout
  and only calls `/api/company/summary` to show PostgreSQL adapter status.
- `scripts/company_postgres_read_model_server.py` exposes generic summary,
  receipts, projections, and bounded domain/report reads; it does not expose
  `/api/company/dashboard/*` reads.
- `scripts/company_postgres_service.py` has no dashboard route. The parity
  matrix therefore correctly keeps the three dashboard aliases as
  `read_model_only` and all seven source dashboard handlers as
  `not_connected`.
- Core report reads are not dashboard parity. A report overview can provide
  reconciled tables, but it does not reproduce the source cockpit's scoped
  KPIs, month trend, stage distribution, anomaly ranking, or health breakdown.

## Revised gate

1. Obtain the complete redacted export (or owner-approved empty-data
   dispositions) before implementing cross-domain dashboard aggregates.
2. Add an authenticated, bounded dashboard read model in two slices: the
   source-backed overview/funnel/project KPI/anomaly reads first, then v2/v3
   only after sales/fund/invoice/tender/warning/CBS source coverage exists.
3. Make source coverage, scope (`buGuid`/`projGuid`), money units, date basis,
   and missing-data status explicit in every response. Do not use fixture or
   synthetic values in a connected cockpit response.
4. Bind the designer-preserving Rabbita dashboard to that read model, retain a
   clearly labelled fallback only for offline development, and run browser
   acceptance through the production identity/entity scope boundary.
5. Obtain operations/finance owner reconciliation for KPI definitions and
   anomaly rules before using cockpit values for management, cash, tax, or
   close decisions.
