# ERP Project Runtime Audit

Recorded: 2026-07-13  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source MDM routes provide project list and lifecycle reads, while the plan
routes provide project task/detail reads and task mutations. The available
credential-safe backup contains two projects, seven lifecycle stages, fourteen
lifecycle instances, nine tasks, and one task report.

The target now connects the source-preserving project master/detail boundary:

| Source surface | Target endpoint | Target state |
|---|---|---|
| Project list | `/api/company/projects` | source-preserving read |
| Project detail/lifecycle/tasks | `/api/company/projects/:id` | source-preserving read |
| Project task list | `/api/company/projects/:id/tasks` | source-compatible read |
| Task detail/report history | `/api/company/tasks/:id` | source-compatible read |
| Project plan summary | `/api/company/projects/:id/plan-summary` | source-compatible read |
| Rabbita project list | `/projects` | connected read with designer fallback |
| Rabbita project detail | `/projects/:guid` | connected read with designer fallback |

The target does not create, edit, delete, or infer project state from local
fixtures in this slice. Delivery task/progress commands remain separate
evidence-gated boundaries.

## Current evidence

- PostgreSQL service smoke returns two projects, fourteen lifecycle rows, and
  nine tasks; `proj-0001` detail returns seven lifecycle stages and seven tasks.
- The source-compatible plan reads return seven tasks, one task report for
  `task-003`, and a five-key-node summary for `proj-0001` (two done, one
  in-progress, and two pending).
- Project, company, lifecycle, task, owner, and report identities remain tied to
  the imported source payload and are marked `source_kind=imported`.
- Rabbita `/projects` and `/projects/:guid` load live PostgreSQL rows while
  retaining the designer-built tables and forms as an explicitly labelled
  fallback/preview.
- The parity matrix marks the two project browser routes and the two MDM GET
  handlers as `connected_project_read`; project mutations and plan route
  mutations remain unconnected.

## Remaining gate

1. Run browser acceptance through production identity and verify BU/entity scope
   and lifecycle/task reconciliation against the source implementation.
2. Bind the source-compatible plan reads to the full project-plan UI scenario
   and preserve task reporting/progress mutation authority as a separate
   evidence-gated boundary.
3. Obtain named project/operations owner acceptance before treating imported
   project state as target-owned.
