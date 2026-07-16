# Business-Acceptance Packet

Recorded: 2026-07-13  
Status: packet contract implemented; decisions pending

Technical parity is not business acceptance. The migration now requires a
machine-readable owner-decision packet before a bounded shadow period can be
authorized.

Required decisions:

| Decision | Owner | Purpose |
|---|---|---|
| `task-state-proj-0001` | business | Decide whether the dependency-conflicting task state is corrected, deferred, or rejected. |
| `erp-schema-coverage` | migration-owner | Acknowledge that the current artifact covers 26/75 schema tables and defer full scope until a complete export. |
| `production-database-deployment` | operations | Approve the managed database, backup, restore, rollback, and observability contract. |
| `accounting-reconciliation` | finance | Accept the reviewed source-to-journal evidence and its non-posting boundary. |
| `shadow-period` | operations | Approve the owner, duration, comparison reports, and rollback procedure for shadow operation. |

`cmd/business_acceptance_check` with `scripts/company_business_acceptance_check.sh` validates decision IDs, owner
roles, source snapshot identity, evidence references, and decision metadata. It
accepts empty decisions as `acceptance_pending`; it never converts them into
approval. The operations, finance, and shadow-period decisions must explicitly
be `accept_for_shadow`; task-state and schema-scope decisions may be `defer`
for a bounded shadow period. Only then can the packet become
`ready_for_shadow`; `cutover_authorized` remains false.

The checked-in
`scripts/fixtures/business_acceptance_manifest.example.json` intentionally
contains no decisions. Its source snapshot marker binds to the validated
export evidence at rehearsal time. Each rehearsal emits
`business-acceptance.json` and the cutover gate records the packet as an
owner-review exception.
