# ERP Financing-Facility Boundary

Recorded: 2026-07-13

This is an opt-in migration boundary for corporate financing facilities. It
preserves reviewed debt evidence without contacting a lender, releasing cash,
posting accounting, or closing a period.

## Reviewed input

`scripts/erp_financing_facility_plan.py` accepts a reviewed
`moonproj.erp.financing-facility-map.v1` document. Each facility must name its
source row, legal principal, project scope, lender identity, currency, limit,
annual rate, draw amount, repayment amount, interest days, and expected state.
Facility IDs are unique; rates are bounded to 0–10,000 basis points; draws may
not exceed the limit; repayments may not exceed the draw amount; and
secret-shaped keys are rejected. The checked-in fixture is synthetic because
the available ERP snapshot contains no facility rows.

## Native lifecycle receipt

`cmd/financing_facility` executes the reviewed candidate through
`finance/financing`: create, approve, activate, draw, repay, interest accrual,
and (when explicitly expected) default. The receipt records limit, drawn and
outstanding principal, rate, currency, lifecycle events, and calculated
interest. The fixture produces a CNY 1,000,000 limit, CNY 600,000 drawn,
CNY 150,000 repaid, CNY 450,000 outstanding, 650 bps, and 30-day interest of
CNY 24.04 in minor units (2,404).

## Durable parity and exclusions

The SQLite and PostgreSQL adapters compare every candidate by target/source
identity and make identical replay insert zero rows. The receipt explicitly
sets `lender_called`, `cash_released`, `accounting_posted`, and `period_closed`
to false. Lender confirmations, covenant schedules, cash disbursement,
repayment settlement, accounting-link posting, tax treatment, and production
owner acceptance require separate reviewed cohorts.
