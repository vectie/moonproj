# ERP Project Runtime Audit

Recorded: 2026-07-15
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source MDM routes provide project list and lifecycle reads, while the plan
routes provide project task/detail reads and task mutations. The available
credential-safe backup contains two projects, seven lifecycle stages, fourteen
lifecycle instances, nine tasks, and one task report.

The compiled MoonBit PostgreSQL company service now owns the source-preserving
project master/detail and project-plan task boundary. Shell wrappers are the
supported execution path; Python service/gateway files remain frozen
comparison evidence only:

| Source surface | Target endpoint | Target state |
|---|---|---|
| Project list | `/api/company/projects` | source-preserving read |
| Project detail/lifecycle/tasks | `/api/company/projects/:id` | source-preserving read |
| MDM project create/update/delete | signed `POST /api/company/source/mdm/projects` and `PUT`/`DELETE .../:id` | command-owned source alias with replay, audit, and imported-row protection |
| Project task list | `/api/company/projects/:id/tasks` | source-compatible read |
| Task detail/report history | `/api/company/tasks/:id` | source-compatible read |
| Local task create/update/delete | `/api/company/plan/tasks[/:id]` | authority-bound command projection |
| Evidence-gated task report | `/api/company/plan/tasks/:id/report` | command-owned report projection; imported task remains read-only |
| Project plan summary | `/api/company/projects/:id/plan-summary` | source-compatible read |
| Project lifecycle | `/api/company/projects/:id/lifecycle` | source-compatible read |
| Task delay impact | `/api/company/tasks/:id/delay-impact` | source-compatible read |
| AI plan suggestion | signed `POST /api/company/plan/ai-suggest-plan` and `/source` alias | deterministic seven-node candidate; no provider, persistence, or plan mutation |
| Rabbita project list | `/projects` | connected read with designer fallback |
| Rabbita project detail | `/projects/:guid` | connected lifecycle, KPI, and anomaly reads with designer fallback |
| Rabbita project plan | `/project-plan` | source-shaped project scope picker, Gantt-style task timeline, key-node table, report/create-task forms, AI suggestion form, and delay-impact form backed by native PostgreSQL routes |

The target now keeps imported task rows read-only while exposing a separate
PostgreSQL-owned project-plan task command boundary:

- `POST /api/company/plan/tasks` creates a local task projection;
- `PUT /api/company/plan/tasks/:guid` updates a local task;
- `DELETE /api/company/plan/tasks/:guid` (plus the browser-safe `/delete`
  POST alias) tombstones a local task;
- `POST /api/company/plan/tasks/:guid/report` accepts an evidence-gated task
  report projection without mutating the imported task.

Commands require a signed actor, project-scoped capability, deterministic
idempotency key, immutable revision, and audit receipt. They do not mutate
imported `jd_task` rows or trigger workflow, cash, accounting, tax, or
provider effects. Delivery task/progress commands remain a separate
evidence-gated boundary.

## Current evidence

- `scripts/company_postgres_project_plan_smoke.sh` covers imported project reads,
  MDM project create/replay/update/tombstone, fourteen lifecycle rows, and nine
  tasks; `proj-0001` detail returns seven lifecycle stages and seven tasks.
- The source-compatible plan reads return seven tasks, one task report for
  `task-003`, and a five-key-node summary for `proj-0001` (two done, one
  in-progress, and two pending).
- Lifecycle compatibility returns all seven ordered stages, and delay-impact
  analysis preserves the source rule for downstream tasks without mutating
  imported task state.
- Project, company, lifecycle, task, owner, and report identities remain tied to
  the imported source payload and are marked `source_kind=imported`.
- Rabbita `/projects` and `/projects/:guid` load live PostgreSQL rows while
  retaining the designer-built tables and forms as an explicitly labelled
  fallback/preview. Project detail now also loads the seven-stage lifecycle,
  eight-dimensional KPI response, and project anomaly response from the native
  dashboard endpoints; these observations remain non-authorizing and do not
  invoke providers or notifications.
  Rabbita `/project-plan` now loads the selected project's PostgreSQL task
  rows, renders source-shaped Gantt/table views with task owners/status/dates,
  submits evidence-gated reports, creates/updates/deletes local task
  projections, exposes the seven-node deterministic AI suggestion form, and
  calculates delay impact without mutating the plan. The trusted gateway
  smoke covers the native AI/task routes; browser production acceptance remains
  open.
- The native service and project-plan smoke cover MDM project
  create/replay/update/delete, local task create/replay/update/delete, and an
  evidence-gated report alias; the source-shaped project-plan readback merges
  command projections with `sourceKind=command` while keeping source coverage
  separate.
- `scripts/company_postgres_project_plan_smoke.sh` also proves the seven-node
  plan suggestion candidate, deterministic end dates, and explicit
  `providerExecution=false`, `persisted=false`, and `authorizing=false` markers.
- The parity matrix marks project-plan create/update/delete/report as
  `connected_project_plan_command`; AI scheduling is now a deterministic native
  candidate, while provider execution, production identity, browser acceptance,
  imported source promotion, and owner approval remain open.

## Remaining gate

1. Run browser acceptance through production identity and verify BU/entity scope
   and lifecycle/task reconciliation against the source implementation.
2. Run the full browser project-plan scenario with production identity,
   including evidence capture for reports and responsive Gantt/table behavior.
3. Obtain named project/operations owner acceptance before treating imported
   project state as target-owned.
