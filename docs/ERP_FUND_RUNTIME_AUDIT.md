# ERP fund-plan runtime audit

The Rabbita `/fund/plan` route now consumes a source-compatible PostgreSQL
read boundary for the ERP fund family:

- `/api/company/fund/plans` — project/period/direction-filtered plans;
- `/api/company/fund/gap-analysis` — period-level planned/actual net and gap;
- `/api/company/fund/dispatches` — inter-project liquidity dispatch evidence.

These reads preserve source identities and return `source_coverage`,
`missing_or_empty_source_tables`, `source_kind`, and `authorizing=false`.
They never create a plan, approve a dispatch, or release cash.

The controlled export has no `fund_plan` or `fund_dispatch` rows, so the page
shows an explicit empty source state instead of the designer's sample
liquidity figures once the read succeeds. The designer table remains only a
transport-failure fallback. Fund-plan writes, dispatch approval, bank
settlement, accounting, tax, production identity, and owner acceptance remain
separate migration gates.
