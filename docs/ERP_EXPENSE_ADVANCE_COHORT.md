# ERP Employee Expense and Advance-Offset Cohort

Recorded: 2026-07-13
Source boundary: `vcb_loan_simple`, `vcb_expense`, and `cb_loan_offset` from
`../erp/erp_new`
Target boundary: `finance/employee_finance` and `operations/expense`

This cohort keeps an employee advance, an expense claim, and an advance offset
as distinct company-owned records. It exercises the economic relationship
without treating an advance balance or approved expense as permission to move
cash or post the book:

```text
employee advance
  + approved expense claim with explicit allocations
  -> separate bounded advance offset
  -> partially repaid advance + approved expense with offset evidence
```

## Executable boundary

- `scripts/erp_expense_advance_cohort_plan.py` validates the reviewed map,
  source table identities, principal/employee relationship, allocation totals,
  currency, amount ceilings, expected balance, and unique identities. It
  rejects secret-shaped keys and refuses an offset above either the advance or
  the expense.
- `cmd/expense_advance_cohort` constructs the advance, drives the expense
  claim through submitted/approved, and calls the native `offset_advance`
  boundary with separate expense and advance grants. It emits three candidates:
  `employee_advance`, `expense_claim`, and `employee_advance_offset`.
- `scripts/company_expense_advance_cohort_rehearsal.sh` applies the receipt to
  isolated SQLite and optional PostgreSQL projection stores, checks exact
  identity parity, and proves zero-insert replay.
- `scripts/fixtures/expense_advance_cohort_mapping.example.json` is reviewed
  and source-shaped. It uses a CNY 500,000 advance, a CNY 300,000 allocated
  expense, and a CNY 150,000 offset, leaving the advance partially repaid.

The receipt carries `cash_released=false`, `accounting_posted=false`, and
`period_closed=false`. Recognition journals, opening advance accounting,
offset accounting, payment, tax, and period close remain separate reviewed
events.

## Verification

The reviewed fixture produces one projection of each type. SQLite and
PostgreSQL both report `shadow_verified`; the first apply inserts three rows
and the second inserts zero. The source snapshot has one real advance and one
offset but no accepted expense rows, so production expense export, owner
acceptance, and accounting/subledger reconciliation remain open.
