# ERP Dashboard Runtime Audit

Recorded: 2026-07-13
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

The available rows now support the bounded v1 overview/funnel/KPI/anomaly
reads and a scoped v2 KPI/payment-trend/stage/warning read. They cannot
support the full v3 cockpit without sales, funds, invoices, tender, warning,
and CBS data. Empty source tables must remain empty; the target must not
manufacture revenue, cash, health, warning, or risk values.

## Target evidence

- `frontend/main/main.mbt` renders the source-shaped KPI/funnel/risk layout,
  calls `/api/company/summary` for adapter status, then loads the bounded
  dashboard reads for live KPI, funnel, and anomaly values.
- `scripts/company_postgres_service.py` exposes the five bounded v1 routes and
  `/api/company/dashboard/v2/group`, with source coverage and missing-table
  metadata on every response. The v3 aggregate route remains intentionally
  unconnected; the separate development read-model server still exposes only
  the v1 reads.
- Rabbita now loads the group overview, stage funnel, and top-anomaly reads
  sequentially and replaces the designer KPI/funnel/risk fixtures when the
  responses are valid. The v2 source read is service-connected for API parity
  but is not yet mounted in Rabbita; production identity, browser acceptance,
  and owner reconciliation remain pending. The source v3 aggregate handler
  remains unconnected and is not included in that state.
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
   dispositions) before implementing the v3 cross-domain aggregate. The v2
   read is limited to the source rows currently present; the v3 route requires
   sales/fund/invoice/tender/warning/CBS source coverage.
4. Retain a clearly labelled fallback only for offline development, and run
   browser acceptance before counting the dashboard as functional parity.
5. Obtain operations/finance owner reconciliation for KPI definitions and
   anomaly rules before using cockpit values for management, cash, tax, or
   close decisions.
