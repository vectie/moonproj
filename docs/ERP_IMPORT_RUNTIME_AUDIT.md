# ERP Import Runtime Audit

The source `/api/v1/import/:bizType` route accepts project and contract rows,
validates each row, and commits the batch transactionally. Native PostgreSQL
now recognizes the source-compatible `/api/company/import/project` and
`/api/company/import/contract` POST boundaries after signed actor validation.
The authenticated `GET`/`HEAD` `/api/company/import/:bizType/template` aliases
are native as well: project and contract return the exact UTF-8 BOM, header
order, and download disposition, while unsupported business types return the
source 400 response. No template read persists rows or grants import authority.

Project batches now have a native command path. A signed project batch validates
business-unit ownership, duplicate project codes, row limits, and idempotency,
then commits command and immutable `project_import` projections in one
PostgreSQL transaction. `/api/company/projects` merges those projections into
the existing read model, and replay returns the original result without new
rows. Dry runs validate and normalize without persistence.

Contract batches now use the same native command boundary: project and business
unit references are resolved, contract rows are normalized, and command-owned
contract projections plus audit receipts commit in one transaction. The source
contract list merges these rows and idempotent replay returns the original
result. The remaining acceptance work is production identity and owner review.
Neither import path posts accounting, releases
cash, invokes providers, or calculates tax.
