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
| Project create | `POST /api/company/source/mdm/projects` | command-owned source alias |
| Project edit/void | `PUT`/`DELETE /api/company/source/mdm/projects/:guid` | command-owned source aliases |

The target returns the source field names (`buGuid`, `buCode`, `buName`,
`legalName`, `hierarchyCode`, `level`, `buType`, and `children`) and marks every
node `sourceKind=imported`. No organization create, edit, delete, role, or
ownership mutation is enabled by this slice. Imported projects remain immutable;
local project aliases are separate PostgreSQL projections.

The source project create/edit/soft-delete handlers are now translated into a
command-owned `project` aggregate. Create preserves `projGuid`, `projCode`,
`projName`, BU identity, level, dates, status, and seven pending lifecycle
stages. Update is limited to command-owned projects, and delete writes a local
tombstone. These commands are explicitly neutral with respect to task state,
workflow, budget/CBS, accounting, cash, and tax.

## Evidence

- PostgreSQL service smoke returns one root, two direct company children, and
  seven total business-unit rows.
- The hierarchy is built from `parent_guid`; missing parents become explicit
  roots rather than silently dropping imported rows.
- The local PostgreSQL read-model endpoint `/api/company/business-units/tree`
  returns the same one-root/seven-node hierarchy used by the service adapter;
  the direct contract check returned HTTP 200 with imported provenance.
- The parity matrix marks the source MDM `GET /business-units/tree` handler as
  `connected_mdm_read`; the three project mutation handlers are now marked
  `connected_mdm_project_command`. Browser identity and scope acceptance remain
  pending.
- PostgreSQL service and trusted-gateway smoke cover project create/replay,
  source-shaped readback, update, imported-project write rejection, and
  command-owned tombstone filtering.

## Remaining gate

1. Reconcile business-unit scope and legal-principal ownership with the source
   owner through production identity.
2. Bind the tree and project command aliases to the full project, cost,
   expense, loan, and administration browser scenarios; keep legal-principal,
   organization, task, workflow, and financial effects separately authorized.
3. Obtain the missing source export before treating seven rows as complete ERP
   organization coverage.
