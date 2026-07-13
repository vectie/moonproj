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
| Rabbita project list | `/projects` | connected read with designer fallback |
| Rabbita project detail | `/projects/:guid` | connected read with designer fallback |

The target does not create, edit, delete, or infer project state from local
fixtures in this slice. Delivery task/progress commands remain separate
evidence-gated boundaries.

## Current evidence

- PostgreSQL service smoke returns two projects, fourteen lifecycle rows, and
  nine tasks; `proj-0001` detail returns seven lifecycle stages and seven tasks.
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
2. Connect the source plan task/detail reads to the project-plan UI as a
   separate read slice; keep task reporting and progress mutation authority
   separate from project master data.
3. Obtain named project/operations owner acceptance before treating imported
   project state as target-owned.
