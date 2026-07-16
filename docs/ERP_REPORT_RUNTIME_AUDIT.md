# ERP Reporting Runtime Audit

Recorded: 2026-07-13  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source `reports.js` module has ten handlers: five core report reads,
template metadata/list/run/create/delete, and report sharing in the separate
`share.js` module. The target now has a bounded PostgreSQL slice for the five
core reports, native report-builder metadata/template commands, and a local
report-share lifecycle. It keeps report computation/share projections separate
from accounting posting, cash, tax filing, and period close.

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
the supplier/approval coverage counts. The report-builder route now has native
metadata/list/run/create/delete behavior. Signed
`/api/company/reports/shares` create/list/revoke commands use command-owned
`report_share` revisions; public `/api/company/share/:token/meta|data` reads
serve only the five allow-listed reports, require forwarded TLS, and record
access revisions. Tokens are deterministic local SHA-256 identifiers for
replayable evidence, not a production credential issuer.

## Current evidence

- The native MoonBit PostgreSQL service returns the five individual report
  endpoints and the bundled overview; the shell-only source-read smoke covers
  those routes without Python.
- Current export produces two cost rows, two contract-payment rows, and two
  project-stage rows.
- Current backup has no `srm_provider` or `srm_category` tables at all, and the
  workflow tables exist but contain zero `wf_process_instance` and
  `wf_step_action` rows. Supplier analysis and approval efficiency therefore
  correctly return empty source-backed results rather than invented data.
- The parity matrix marks `/reports` as `connected_report_read`; share commands
  and public reads are now native but remain bounded by the local token and
  projection model.
- The Rabbita `/ai-stats` action now calls the native XLSX endpoint through the
  PostgreSQL gateway and downloads a bounded AI-summary workbook in the
  browser. Direct and gateway export smokes validate ZIP/XML contents; the
  browser still uses the development session boundary.
- No report endpoint mutates company state or infers accounting, tax, cash, or
  investment results.

## Remaining gate

1. Obtain a complete redacted export (or an owner-approved explicit empty-data
   disposition) for the missing supplier tables and workflow rows, then verify
   supplier and approval calculations against the source implementation.
2. Connect authenticated report access to the production identity and entity/
   scope boundary; run a browser scenario for cost, contract, and stage reports.
3. Preserve the native template field whitelist and report-share
   expiry/revocation/access boundary. Replace the deterministic local token
   with the production credential/identity policy and managed public-serving
   controls before treating public sharing as accepted. Do not expose arbitrary
   SQL or allow report exports to bypass data scope.
4. Only after report owners accept reconciliation to source records should
   reporting be used as evidence for close, tax, treasury, or management
   decisions.
