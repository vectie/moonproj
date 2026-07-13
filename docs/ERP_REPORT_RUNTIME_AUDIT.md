# ERP Reporting Runtime Audit

Recorded: 2026-07-13  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source `reports.js` module has ten handlers: five core report reads,
template metadata/list/run/create/delete, and report sharing in the separate
`share.js` module. The target now has a bounded, read-only PostgreSQL slice for
the five core reports. It keeps report computation separate from commands,
accounting posting, cash, tax filing, and period close.

| Source report | Target endpoint | Source-preserving inputs |
|---|---|---|
| `/cost-summary` | `/api/company/reports/cost-summary` | `ep_project`, `mu_business_unit`, `cb_cost` |
| `/contract-payment-ledger` | `/api/company/reports/contract-payment-ledger` | `cb_contract`, `cb_htfkplan`, `cb_htfk_apply`, project/company rows |
| `/supplier-analysis` | `/api/company/reports/supplier-analysis` | `srm_provider`, `srm_category`, `cb_contract` |
| `/approval-efficiency` | `/api/company/reports/approval-efficiency` | `wf_process_instance`, `wf_step_action` |
| `/project-stage-matrix` | `/api/company/reports/project-stage-matrix` | `ep_project`, `mu_business_unit`, `proj_lifecycle_stage`, `proj_lifecycle_instance` |

`/api/company/reports/overview` bundles the five reads and returns source-table
coverage plus missing-table names. The Rabbita `/reports` route loads that
overview and renders connected cost, contract, and stage rows while showing
the supplier/approval coverage counts. The report-builder route, template
queries, and share-link lifecycle remain separate fixture/not-connected
surfaces.

## Current evidence

- PostgreSQL service and read-model server both return the report overview.
- Current export produces two cost rows, two contract-payment rows, and two
  project-stage rows.
- Current export has no `srm_provider`, `srm_category`,
  `wf_process_instance`, or `wf_step_action` rows, so supplier analysis and
  approval efficiency correctly return empty source-backed results rather than
  invented data.
- The parity matrix marks `/reports` as `connected_report_read`; the complete
  source API module is not claimed connected because template and share actions
  remain open.
- No report endpoint mutates company state or infers accounting, tax, cash, or
  investment results.

## Remaining gate

1. Obtain the missing supplier/workflow source rows or an owner-approved
   redacted cohort, then verify supplier and approval calculations against the
   source implementation.
2. Connect authenticated report access to the production identity and entity/
   scope boundary; run a browser scenario for cost, contract, and stage reports.
3. Preserve template field whitelists and the report-share expiry/revocation
   boundary as a separate command/read slice. Do not expose arbitrary SQL or
   allow report exports to bypass data scope.
4. Only after report owners accept reconciliation to source records should
   reporting be used as evidence for close, tax, treasury, or management
   decisions.

