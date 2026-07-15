# Managed Production Deployment Gate

Recorded: 2026-07-15
Status: contract implemented; owner approval and real deployment remain open

The repository's SQLite driver is a local production-shaped rehearsal. It is
not the managed production database. Before any ownership transfer, the target
deployment must provide a concrete, reviewed manifest for the selected service.
The supported target runtime is pure MoonBit plus shell orchestration; the
current Python adapters are transitional bridge evidence and cannot be the
managed production service.

## Required controls

The manifest must identify:

- a managed PostgreSQL service;
- a database DSN environment-variable name, never a raw credential or DSN;
- bounded connection pooling and acquisition timeout;
- required TLS with certificate verification;
- encryption at rest and key-management ownership;
- scheduled, encrypted, cross-region backups with retention;
- declared recovery-point and recovery-time objectives;
- a tested restore verification command and rollback runbook;
- migration locking, metrics, administrative audit logging, and alert routing;
- named operations, security, and finance approvals, each with an actor,
  decision timestamp, rationale, and evidence reference.

The former `scripts/company_production_deployment_check.py` and
`scripts/company_production_service_check.py` describe and validate this
contract as frozen comparison evidence. They must not be executed by a
supported build or deployment. Their checks fail closed on raw DSNs,
secret-shaped fields, unsupported engines, missing backup/restore controls,
unsafe TLS, invalid pool bounds, or missing structured approval records. A
native MoonBit deployment-gate command and shell wrapper still have to be
ported; until then managed deployment is blocked. A role-name list alone
cannot authorize deployment.

The checked-in
`scripts/fixtures/production_deployment_manifest.example.json` is intentionally
unapproved. It documents the required shape without containing credentials or
authorizing deployment.

## Run

There is no supported deployment-gate command until the native MoonBit port is
complete. The checked-in manifest is a specification fixture only. The future
shell wrapper must produce a credential-free gate artifact for operational and
cutover review; it will not replace provider-level provisioning, security
review, restore execution, capacity testing, or named business acceptance.

## Production service boundary

The database gate is paired with a separate service manifest. The future
native MoonBit service-gate command must require connection reuse with bounded
in-flight work and
fail-closed exhaustion, schema-matched readiness, private binding behind a TLS
gateway, authenticated requests, explicit HTTPS CORS origins, fixed read-only
endpoints, no arbitrary SQL, no mutation routes, and metrics/audit/alert/trace
destinations. It can report `ready_for_service_review`, but it cannot authorize
the service while the database deployment gate lacks named approvals. The
local command-capable expense service is a separate runtime rehearsal; it is
not silently treated as an approved production command gateway.

The supported local runtime is the native MoonBit service, started through its
shell wrapper:

```text
MOONCOMPANY_SERVICE_TOKEN=<secret-from-the-gateway> \
PGHOST=/tmp PGPORT=5432 PGUSER=moonproj PGDATABASE=moonproj \
scripts/company_postgres_service.sh \
  --token-env MOONCOMPANY_SERVICE_TOKEN \
  --require-forwarded-tls
```

The native MoonBit service keeps bounded reusable PostgreSQL access, requires
`Authorization: Bearer` and `X-Forwarded-Proto: https`, checks schema version 4
before reporting healthy, and exposes the fixed reads plus the locally
rehearsed expense, contract, and payment-application command lifecycles.
Shell-only native smoke checks prove the positive read/command path,
idempotency, audit receipts, missing-token, and missing-TLS behavior. The
managed deployment must still provide the real gateway, issuer/audience
verification, TLS certificates, observability, and approved capacity/restore
controls before commands are enabled in production. Run
`scripts/company_no_python_runtime_gate.sh` as a prerequisite; no Python
fallback or dual-runtime deployment is authorized.
