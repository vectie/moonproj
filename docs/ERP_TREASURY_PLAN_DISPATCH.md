# ERP Treasury Plan and Dispatch Boundary

Recorded: 2026-07-13

This is an opt-in migration boundary for liquidity planning and controlled
project-to-project fund dispatch. It preserves reviewed treasury intent and
approval evidence without releasing a bank movement or posting accounting.

## Reviewed input

`scripts/erp_treasury_plan_dispatch_plan.py` accepts a reviewed
`moonproj.erp.treasury-plan-dispatch-map.v1` document. Cash plans must name
principal, project scope, period, category, direction, currency, planned and
actual amounts, and expected state. Actualization must be positive and within
the plan. Fund dispatches must name distinct source/destination projects,
principal, amount, currency, reason, and expected approval state. IDs are
unique and secret-shaped keys are rejected.

## Native lifecycle receipt

`cmd/treasury_plan_dispatch` executes each cash plan through native planned,
confirmed, and optional actualized states. It executes each fund dispatch
through pending, approved, and optional executed states. The fixture preserves
one actualized CNY 10,000 plan, one confirmed CNY 5,000 inflow plan, and one
CNY 3,000 executed inter-project dispatch (minor units).

## Durable parity and exclusions

SQLite and PostgreSQL adapters compare all `cash_plan` and `fund_dispatch`
candidates by target/source identity and make identical replay insert zero
rows. The receipt explicitly sets `cash_released`, `dispatch_settled`,
`accounting_posted`, and `period_closed` to false. Bank-account movement,
liquidity settlement, accounting/tax treatment, and owner acceptance require
separate reviewed gates.
