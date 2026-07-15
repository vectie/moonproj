# ERP Import Runtime Audit

The source `/api/v1/import/:bizType` route accepts project and contract rows,
validates each row, and commits the batch transactionally. Native PostgreSQL
now recognizes the source-compatible `/api/company/import/project` and
`/api/company/import/contract` POST boundaries after signed actor validation.

The current response is an explicit `409` `import_batch_candidate` gate:
`rowsAccepted=0`, `persisted=false`, and no accounting, cash, tax, provider, or
authorization effect. This keeps import behavior visible without pretending
that the MoonBit service has implemented CSV/row validation and transactional
project/contract writes. The next acceptance gate is reviewed rows plus an
operations owner; template reads remain separate.
