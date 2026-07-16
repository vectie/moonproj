# ERP Employee-Loan Runtime Audit

Recorded: 2026-07-13  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source loan module exposes a list/detail read boundary plus creation,
approval-submission, offset, workflow-sync, draft update, and draft/rejected
void actions. The target now connects that boundary to the compiled MoonBit
PostgreSQL service, native gateway, and Rabbita `/loans` page. The shell smoke
is the supported execution path; the former Python service is comparison
evidence only.

| Source surface | Target endpoint | Source tables |
|---|---|---|
| Loan list | `/api/company/loans` | `vcb_loan_simple`, `sys_user`, `mu_business_unit`, `ep_project` |
| Loan detail and offsets | `/api/company/loans/:id` | `vcb_loan_simple`, `cb_loan_offset`, identity/project rows |

The read shape preserves the source loan identity, amount/balance/remain
amounts, applicant/department/project labels, workflow state, and offset
evidence. Imported loans are read-only. Local commands use the same
source-shaped transitions but persist as `employee_advance` revisions with
idempotent `company_command` receipts and immutable audit events:

| Source action | Target command | Boundary |
|---|---|---|
| Create draft | `POST /api/company/loans` | Requires an explicit `advance:create` grant with `employee:<id>` scope and amount bound. |
| Submit for approval | `POST /api/company/loans/:id/submit-for-approval` | Applicant-only; moves `Draft` to `Approving`. |
| Offset | `POST /api/company/loans/:id/offset` | Requires `advance:offset`, remains bounded by outstanding minor units, and emits a separate offset projection. |
| Edit draft | `POST /api/company/loans/:id/update` or source-compatible `PUT /api/company/loans/:id` | Applicant-only and `Draft`-only; preserves the source mutable fields. |
| Void | `POST /api/company/loans/:id/void` or source-compatible `DELETE /api/company/loans/:id` | Applicant-only and limited to `Draft`/`Rejected`, represented as `Voided`. |
| Workflow sync | `POST /api/company/loans/:id/sync-from-workflow` | Deliberately rejected until `wf_process_instance` source rows and a local workflow owner are available. |

The service accepts minor-unit amounts for command writes, while the read
shape keeps the source decimal amount/balance/remain fields. No loan command
posts cash, accounting, tax, or approval state implicitly.

## Current evidence

- The available export contains one `vcb_loan_simple` row (`loan-001`) and one
  `cb_loan_offset` row (`off-001`).
- The same backup contains zero `wf_process_instance` rows and zero
  `wf_step_action` rows; `loan-001.process_instance_guid` is empty. The source
  initializer defines those workflow tables, but no workflow instance/action
  evidence is present in the credential-safe payload, so no approval state is
  inferred or synchronized.
- The service and read-model server return the loan list and detail with the
  5,000.00 original amount, 1,500.00 offset, 3,500.00 remaining balance, and
  offset provenance.
- Rabbita `/loans` loads the live list and keeps the designer's existing
  summary/table layout as an offline fallback.
- Loan detail reads `/api/company/source/workflow/instances/:id` when the
  source row carries `process_instance_id`, rendering the source action trail
  (step, decision, assignee, timestamp, comment) without granting approval
  authority; empty workflow source rows remain visibly empty.
- The parity matrix marks the two source loan GET actions and `/loans` as
  connected-read evidence and marks create, submit, offset, update, and void
  as connected command handlers. The workflow-sync handler remains explicitly
  gated.
- `scripts/company_postgres_loan_smoke.sh` proves native create/replay, applicant submit, draft
  update, draft void, amount/state guards, and the workflow-sync gate. A
  temporary approved local projection also proves bounded offset persistence
  and the separate offset read shape; the temporary rows are removed after
  the rehearsal.
- Rabbita `/loans/new` and local loan detail now expose create, submit, draft
  update, and draft/rejected void command states. Imported detail routes are
  rendered read-only; the approval/offset controls are not fabricated without
  workflow approval evidence, and the workflow timeline remains read-only.

## Remaining gate

1. Run browser acceptance through the production identity and verify entity,
   employee, and department scope; imported loan rows must remain read-only.
2. Supply real `wf_process_instance` and `wf_step_action` rows (or obtain an
   owner-approved explicit empty-data disposition) and map their states through
   a named workflow owner before enabling workflow synchronization or local
   approval completion.
3. Attach a named finance/operations owner decision before enabling loan
   mutations in production; the local command boundary is ready for review,
   not a production cutover authorization.
