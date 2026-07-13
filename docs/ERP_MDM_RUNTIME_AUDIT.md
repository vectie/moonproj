# ERP MDM Runtime Audit

Recorded: 2026-07-13  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source MDM route exposes a hierarchical business-unit tree used by project,
cost, expense, loan, and administrative screens. The available credential-safe
export contains seven rows: one group, two companies, and four departments.

The target now exposes the source-compatible read boundary:

| Source surface | Target endpoint | Target state |
|---|---|---|
| Business-unit tree | `/api/company/business-units/tree` | source-compatible read |

The target returns the source field names (`buGuid`, `buCode`, `buName`,
`legalName`, `hierarchyCode`, `level`, `buType`, and `children`) and marks every
node `sourceKind=imported`. No organization create, edit, delete, role, or
ownership mutation is enabled by this slice.

## Evidence

- PostgreSQL service smoke returns one root, two direct company children, and
  seven total business-unit rows.
- The hierarchy is built from `parent_guid`; missing parents become explicit
  roots rather than silently dropping imported rows.
- The local PostgreSQL read-model endpoint `/api/company/business-units/tree`
  returns the same one-root/seven-node hierarchy used by the service adapter;
  the direct contract check returned HTTP 200 with imported provenance.
- The parity matrix marks the source MDM `GET /business-units/tree` handler as
  `connected_mdm_read`; browser identity and scope acceptance remain pending.

## Remaining gate

1. Reconcile business-unit scope and legal-principal ownership with the source
   owner through production identity.
2. Bind the tree to the full project, cost, expense, loan, and administration
   browser scenarios; keep organization mutations separately authorized.
3. Obtain the missing source export before treating seven rows as complete ERP
   organization coverage.
