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
schema version `4`, `120` staged and durable records, `120` unique source
identities, and one migration receipt. Replaying the same staging artifact
inserted `0` rows and did not create a second receipt. Aggregate projections
and accounting-event links remain separate, explicitly reviewed cohorts; the
raw envelope apply does not infer business effects.
