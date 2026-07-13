# ERP Investment Performance Cohort

This opt-in reviewed cohort preserves an investment portfolio, explicit market
quotes, deterministic period performance, and an external benchmark observation
as separate analytics evidence. It constructs a bounded active mandate and
portfolio, adds positions only through authority-checked local operations, and
attributes mark-to-market performance without executing trades.

The checked-in fixture contains two CNY positions with CNY 3,000,000 cost basis
and CNY 3,100,000 market value for period `2026-07` (333 basis points return).
The external benchmark observation reports 302 basis points against a 300 basis
point comparison with a two-basis-point tolerance, so reconciliation passes.

The receipt emits three immutable candidates: `investment_portfolio`,
`investment_performance`, and `investment_benchmark_reconciliation`. Exact
SQLite/PostgreSQL parity and idempotent replay preserve source snapshot,
mapping, evidence, quote, position, return, difference, and tolerance identity.
Every candidate is explicitly analytics-only with `position_mutated=false`,
`cash_released=false`, `accounting_posted=false`, and `period_closed=false`.
The available ERP snapshot has no external portfolio or benchmark rows; the
fixture remains synthetic until a redacted source feed and investment-owner
acceptance are supplied.
