# ERP fund-plan runtime audit

The compiled `cmd/postgres_company_service` binary, started by
`scripts/company_postgres_service.sh`, backs the Rabbita `/fund/plan` route with
both a source-preserving read boundary
and a bounded PostgreSQL-owned planning command boundary.

Source-compatible reads are exposed at:

- `/api/company/fund/plans` — project/period/direction-filtered plans;
- `/api/company/fund/gap-analysis` — period-level planned/actual net and gap;
- `/api/company/fund/dispatches` — inter-project liquidity dispatch evidence.

They preserve imported identities and return `source_coverage`,
`missing_or_empty_source_tables`, `source_kind`, and `authorizing=false`.
Imported rows are read-only. The controlled export has no `fund_plan` or
`fund_dispatch` rows, so successful reads show an explicit empty-source state;
designer liquidity figures are retained only as a transport-failure fallback.

The local command boundary is deliberately a planning projection, not a
treasury integration:

- `POST /api/company/fund/plans` creates a local plan;
- `PUT /api/company/fund/plans/:guid` updates a plan created locally;
- `POST /api/company/fund/plans/:guid/delete` tombstones a local plan;
- `POST /api/company/fund/dispatches` creates a pending local dispatch;
- `POST /api/company/fund/dispatches/:guid/approve` approves that local
  dispatch.

Every command requires a signed actor, exact capability and project scope,
an idempotency key, and a deterministic aggregate identity. The service stores
the command receipt, immutable aggregate revision, and audit event in
PostgreSQL, then merges only `sourceKind=command` projections into the
source-shaped readback. Replaying a key returns the original result. Imported
source rows cannot be edited or deleted, and command results explicitly carry
`cash_effect=false`, `accounting_effect=false`, and `tax_effect=false`.

Service and trusted-gateway smokes cover create/replay/update/delete for a
plan and create/approve for a dispatch, including authority rejection paths and
source-shaped readback. Browser interaction and finance-owner acceptance are
still open. Bank settlement, cash release, accounting, tax, production
identity, managed session operation, and owner sign-off remain separate
migration gates. The native `scripts/company_postgres_fund_smoke.sh` and
`scripts/company_postgres_gateway_smoke.sh` are the supported evidence paths;
the former Python service is comparison evidence only.
