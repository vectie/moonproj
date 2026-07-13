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

For source-bound planning, `scripts/erp_cbs_budget_plan.py` reads the
credential-safe `cb_cost` export, the reviewed CBS subject mapping, and an
explicit budget mapping. The mapping must name the source amount field and a
consume decision for every positive source amount; no budget state is inferred
from a cost code. The generated plan preserves the source snapshot identity
and can be passed as the twentieth SQLite argument (or seventeenth PostgreSQL
argument). The optional twenty-first SQLite argument (or eighteenth PostgreSQL
argument) runs this planner directly when a CBS cost mapping is also supplied.
The checked-in source mapping reserves the five positive `dfs_budget` amounts
from the real fixture as unconsumed budget-control evidence.
