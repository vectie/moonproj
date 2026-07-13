# ERP CBS Budget Control Boundary

Recorded: 2026-07-13

`finance/cbs` now provides a subject-scoped `CbsBudgetLedger` separate from
the CBS configuration and cost-link aggregates. A reviewed cost link can
reserve against its subject target, then transition to consumed or released
under distinct authority capabilities. Reservations and consumed amounts count
toward the subject target, so an overrun fails closed before any downstream
effect.

`cmd/cbs_budget` consumes
`moonproj.company.cbs-budget-plan.v1` and emits a normal domain-promotion
receipt containing a `cbs_budget_ledger` projection. The projection records
reservation state, subject, amount, currency, and control totals while keeping
`accounting_posted=false` and `cash_released=false`.

The twentieth SQLite rehearsal argument (and seventeenth PostgreSQL cohort
argument) accepts a reviewed budget plan and runs projection parity and
idempotent replay. The checked-in example reserves and consumes 60,000 minor
units against a 100,000-unit subject target; it is synthetic evidence until
real ERP budget allocations and owner acceptance are available.
