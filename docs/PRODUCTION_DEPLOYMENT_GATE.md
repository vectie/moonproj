# Managed Production Deployment Gate

Recorded: 2026-07-13  
Status: contract implemented; owner approval and real deployment remain open

The repository's SQLite driver is a local production-shaped rehearsal. It is
not the managed production database. Before any ownership transfer, the target
deployment must provide a concrete, reviewed manifest for the selected service.

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

`scripts/company_production_deployment_check.py` validates this PostgreSQL-only
contract and
fails closed on raw DSNs, secret-shaped fields, unsupported engines, missing
backup/restore controls, unsafe TLS, invalid pool bounds, or missing structured
approval records. A role-name list alone cannot authorize deployment. It writes
a credential-free gate artifact. A structurally complete manifest without all
three approvals is `ready_for_owner_review`, not `deployment_authorized`.

The checked-in
`scripts/fixtures/production_deployment_manifest.example.json` is intentionally
unapproved. It documents the required shape without containing credentials or
authorizing deployment.

## Run

```text
scripts/company_production_deployment_check.py \
  scripts/fixtures/production_deployment_manifest.example.json \
  /controlled/production-deployment-gate.json
```

The resulting artifact is an input to the operational and cutover review. It
does not replace provider-level provisioning, security review, restore
execution, capacity testing, or named business acceptance.
