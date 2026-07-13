# ERP Asset Lifecycle Boundary

Recorded: 2026-07-13

This is an opt-in migration boundary for fixed-asset ownership evidence. It
preserves a reviewed asset lifecycle and validates depreciation/disposal
journals without posting accounting, releasing disposal cash, or closing a
period.

## Reviewed input

`scripts/erp_asset_lifecycle_plan.py` accepts a reviewed
`moonproj.erp.asset-lifecycle-map.v1` document. Each asset must name its source
row, legal principal, project scope, description, currency, acquisition cost,
residual value, useful life, expected state, depreciation periods, disposal
proceeds, and explicit account identities. IDs and depreciation periods are
unique; values are non-negative and residual value may not exceed acquisition
cost. Secret-shaped keys are rejected. The checked-in fixture is synthetic
because the available ERP snapshot contains no asset rows.

## Native lifecycle receipt

`cmd/asset_lifecycle` executes proposal, capitalization, activation, optional
impairment, each requested monthly depreciation, and optional disposal through
`finance/assets`. It validates each depreciation journal and the final
disposal basis/journal, then records the computed book values, accumulated
depreciation, gain/loss, lifecycle events, and stable journal identities. The
fixture uses a CNY 1,200,000 machine with CNY 200,000 residual value, two
periods of CNY 83,333 depreciation, and CNY 1,000,000 disposal proceeds,
producing a CNY 33,334 disposal loss in minor units.

## Durable parity and exclusions

SQLite and PostgreSQL adapters compare every candidate by target/source
identity and make identical replay insert zero rows. The receipt explicitly
sets `depreciation_posted`, `disposal_posted`, `cash_released`,
`accounting_posted`, and `period_closed` to false. Tax basis, asset-register
owner acceptance, production account mapping, journal posting, disposal cash
settlement, and period close require separate reviewed gates.
