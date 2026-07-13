# PostgreSQL Target Setup

Recorded: 2026-07-13  
Target: local PostgreSQL 18 for Moonproj

Moonproj now uses PostgreSQL as its only production target. The ERP's MySQL
database is source-only and is never used as a Moonproj target.

The local PostgreSQL service is running on `/tmp:5432`. A dedicated local role
and database were created:

```text
PGHOST=/tmp
PGPORT=5432
PGUSER=moonproj
PGDATABASE=moonproj
```

The password is not stored in this repository. Supply it through `PGPASSWORD`,
`.pgpass`, a secret manager, or the service environment when running a target
adapter.

The PostgreSQL-only production gate rejects `mysql` as a target engine. The
SQLite driver remains a deterministic local rehearsal adapter for tests and
backup/replay checks; it is not the production target.

## Target apply

The credential-free raw staging artifact can be applied to this target with
`scripts/company_postgres_target_apply.py`. It validates the staging manifest,
applies the version-4 catalog, inserts opaque `company_record` envelopes in a
transaction, and finalizes an idempotent migration receipt. Supply the
password through PostgreSQL's normal secret mechanism; it is not a script
argument or repository value:

```text
PGHOST=/tmp PGPORT=5432 PGUSER=moonproj PGDATABASE=moonproj \
  scripts/company_postgres_target_apply.py /path/to/raw-staging.ndjson
```

The local target was verified on the available redacted ERP snapshot with
schema version `4`, `120` staged and durable raw records, `109` aggregate
projections, `7` reviewed accounting-event links, and `19` cohort receipts.
Replaying the same staging artifact and reviewed receipts inserted `0` rows
and did not create duplicate receipts. Native aggregate
promotion receipts can now be persisted through
`scripts/company_postgres_projection_apply.py`; reviewed accounting-link
receipts use `scripts/company_postgres_accounting_link_apply.py`. Both adapters
lock their target table, reject event/source/journal conflicts, preserve
immutable revisions or links, write a cohort-scoped migration receipt, and
make an identical replay insert `0` rows. They do not infer business effects,
release cash, or post journals.

For local browser verification, `scripts/company_postgres_read_model_server.py`
serves the same target through fixed read-only endpoints (`/api/health`,
`/api/company/summary`, `/api/company/receipts`, and
`/api/company/projections`). It is a development adapter only; production
authentication, pooling, TLS, observability, and command endpoints remain
deployment gates.
The authenticated bounded runtime is `scripts/company_postgres_service.py`.
It keeps reusable PostgreSQL sessions behind a fail-closed pool, requires a
bearer token from an environment variable and forwarded TLS, and exposes the
same four GET endpoints without mutation or arbitrary SQL. Run
`scripts/company_postgres_service_smoke.py` against the local target to verify
the runtime contract; managed provider deployment and token issuer/audience
validation remain separate gates.
The credential-free `company_production_service_check.py` now validates the
service boundary separately: bounded reusable pool, schema-matched readiness,
private TLS-terminated binding, authentication, fixed read endpoints, and no
arbitrary SQL or mutation routes. Its example remains owner-review evidence,
not a live deployment.

For a reviewed receipt, use the same PostgreSQL credential mechanism:

```text
PGHOST=/tmp PGPORT=5432 PGUSER=moonproj PGDATABASE=moonproj \
  scripts/company_postgres_projection_apply.py /path/to/domain-promotion.json

PGHOST=/tmp PGPORT=5432 PGUSER=moonproj PGDATABASE=moonproj \
  scripts/company_postgres_accounting_link_apply.py /path/to/accounting-link-receipt.json
```

The repeatable cohort runner accepts the reviewed optional maps after the
core arguments. Supplying the CBS, workflow-assignment, delivery-progress,
advance-offset, and payment-accounting maps runs those cohorts through native
promotion, PostgreSQL parity, and replay as well:

```text
PGHOST=/tmp PGPORT=5432 PGUSER=moonproj PGDATABASE=moonproj \
  scripts/company_postgres_cohort_rehearsal.sh \
  /path/to/export scripts/fixtures/typed_cohort_mapping.json \
  /path/to/raw-staging.ndjson moonproj /tmp/moonproj-pg-rehearsal \
  scripts/fixtures/cbs_cost_link_mapping.json \
  scripts/fixtures/workflow_assignment_mapping.json \
  scripts/fixtures/delivery_progress_mapping.json \
  scripts/fixtures/advance_offset_mapping.json \
  scripts/fixtures/payment_accounting_link_mapping.json \
  "" "" "" "" "" "" \
  scripts/fixtures/cbs_budget_source_mapping.json \
  scripts/fixtures/warning_source_mapping.json \
  scripts/fixtures/accounting_link_mapping.json \
  scripts/fixtures/notification_plan.example.json \
  scripts/fixtures/access_plan.example.json
```

The seventeenth argument accepts the reviewed synthetic CBS budget plan. The
eighteenth argument can instead supply
`scripts/fixtures/cbs_budget_source_mapping.json`; when present, the CBS cost
mapping argument is also required and the runner derives a source-bound budget
plan from explicit positive `cb_cost.dfs_budget` values. These projections
remain budget-control evidence and do not post accounting or release cash.
The nineteenth argument can instead supply
`scripts/fixtures/warning_source_mapping.json`; the runner then derives a
source-bound warning from explicitly named positive `cb_cost` component
overruns. It preserves scan evidence but does not deliver notifications,
mutate workflows, release cash, or post accounting.

The twentieth argument supplies the reviewed base accounting-link map. When it
is present, the PostgreSQL cohort runner promotes the 19-item base domain
receipt, persists its exact parity/replay evidence, and applies the three base
source-to-journal links through the PostgreSQL accounting adapter. With all
reviewed options, the fresh target rehearsal reaches 113 aggregate projections,
7 accounting links, and 22 migration receipts; replay remains idempotent.
The twenty-first argument supplies the reviewed notification plan. It adds one
source-bound `notification_outbox` projection and receipt, so the complete
rehearsal reaches 114 projections, 7 accounting links, and 23 receipts. The
notification boundary records queue intent only; provider delivery,
workflow mutation, cash release, and accounting posting remain separate gates.
The twenty-second argument supplies the reviewed access plan. It adds one
native `access_directory` projection and receipt, so the complete rehearsal
reaches 115 projections, 7 accounting links, and 24 receipts. Role migration
is authority-reviewed and exact-scope; passwords, super-user privilege, and
workflow/cash/accounting effects remain excluded.
