# ERP Tax and Financing Accounting Links

Recorded: 2026-07-13
Status: reviewed local rehearsal; no production posting or cash authority

This slice keeps tax and financing lifecycle evidence separate from the
accounting book. It reuses the reviewed synthetic tax-filing and
financing-facility plans, then requires a second reviewed map for each
source-to-journal identity.

## Tax recognition

`scripts/erp_tax_accounting_plan.py` compiles
`tax_obligation:tax-001` and `tax_obligation:tax-002` from the reviewed tax
filing plan. `cmd/tax_accounting_link` reconstructs each native
`TaxObligation`, calculates and reviews it, and calls
`TaxObligation::to_accounting_event`. The two explicit recognition amounts are
CNY 13,000 and CNY 15,000, debiting `tax-expense` and crediting `tax-payable`.

## Financing draw and repayment

`scripts/erp_financing_accounting_plan.py` compiles the reviewed
`facility-001` draw and repayment maps. `cmd/financing_accounting_link`
reconstructs the facility through approval, activation, draw, and repayment,
then calls the native draw and repayment event builders. The explicit links
are a CNY 600,000 draw (`cash` → `financing-liability`) and a CNY 150,000
repayment (`financing-liability` → `cash`).

## Boundary and evidence

`scripts/company_tax_financing_accounting_rehearsal.sh` runs both cohorts
through the reviewed planner, native domain receipt, accounting-link planner,
native accounting-link validator, SQLite/PostgreSQL apply, exact identity
parity, and idempotent replay. The local rehearsal produced four links with
`shadow_verified` parity on both backends; replay inserted zero rows.

The boundary records source, event, journal, account, principal, scope,
amount, and currency identity only. It does not file or pay tax, call a tax
authority or lender, release or settle cash, post the accounting book, close a
period, or mutate the source ERP. The current ERP snapshot has no accepted tax
obligation or financing-facility rows, so production exports, policy review,
and finance-owner acceptance remain required.
