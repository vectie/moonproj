# ERP Employee-Loan Runtime Audit

Recorded: 2026-07-13  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source loan module exposes a list/detail read boundary plus creation,
approval-submission, offset, workflow-sync, draft update, and draft/rejected
void actions. The target now connects the list/detail read boundary to the
PostgreSQL service, read-model adapter, and Rabbita `/loans` page.

| Source surface | Target endpoint | Source tables |
|---|---|---|
| Loan list | `/api/company/loans` | `vcb_loan_simple`, `sys_user`, `mu_business_unit`, `ep_project` |
| Loan detail and offsets | `/api/company/loans/:id` | `vcb_loan_simple`, `cb_loan_offset`, identity/project rows |

The read shape preserves the source loan identity, amount/balance/remain
amounts, applicant/department/project labels, workflow state, and offset
evidence. Imported loans are read-only. Local creation, approval, offset, sync,
update, and void commands remain a separate authority-gated slice; no command
is inferred from the source page merely because it renders.

## Current evidence

- The available export contains one `vcb_loan_simple` row (`loan-001`) and one
  `cb_loan_offset` row (`off-001`).
- The service and read-model server return the loan list and detail with the
  5,000.00 original amount, 1,500.00 offset, 3,500.00 remaining balance, and
  offset provenance.
- Rabbita `/loans` loads the live list and keeps the designer's existing
  summary/table layout as an offline fallback.
- The parity matrix marks the two source loan GET actions and `/loans` as
  connected-read evidence. The five source loan mutations remain open.

## Remaining gate

1. Run browser acceptance through the production identity and verify entity,
   employee, and department scope; imported loan rows must remain read-only.
2. Define and test local advance create/submit/offset commands against the
   native `finance/employee_finance` authority and evidence rules, with
   idempotency and audit receipts. Offset must remain bounded by outstanding
   balance and must not post cash or accounting implicitly.
3. Attach a named finance/operations owner decision before enabling any loan
   mutation or workflow synchronization.

