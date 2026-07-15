# ERP Import Runtime Audit

The source `/api/v1/import/:bizType` route accepts project and contract rows,
validates each row, and commits the batch transactionally. Native PostgreSQL
now recognizes the source-compatible `/api/company/import/project` and
`/api/company/import/contract` POST boundaries after signed actor validation.

Project batches now have a native command path. A signed project batch validates
business-unit ownership, duplicate project codes, row limits, and idempotency,
then commits command and immutable `project_import` projections in one
PostgreSQL transaction. `/api/company/projects` merges those projections into
the existing read model, and replay returns the original result without new
rows. Dry runs validate and normalize without persistence.

Contract batches remain an explicit `409` `import_batch_candidate` gate with
`rowsAccepted=0`, `persisted=false`, and no accounting, cash, tax, provider, or
authorization effect. The next acceptance gate is a contract-row transaction
that can share source validation and an operations owner; template reads remain
separate.
