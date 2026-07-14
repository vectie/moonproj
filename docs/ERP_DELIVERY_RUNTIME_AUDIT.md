# ERP Delivery and Project-Progress Runtime Audit

Recorded: 2026-07-13  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The target has a real delivery domain and now has a bounded local PostgreSQL
delivery runtime. The native
`operations/delivery` package validates evidence-backed progress,
deliverable acceptance/remediation, cost-forecast input, and a separate
pending-posting recognition link. The `cmd/delivery_progress` and
`cmd/delivery_recognition` cohorts prove SQLite/PostgreSQL projection parity
and idempotent replay for explicitly mapped synthetic evidence. The new
service/read-model slice serves source-preserving task/report reads and
evidence-gated local progress/output/task-report commands without making
acceptance, recognition, cash, tax, or close implicit.

The source ERP exposes two related operational surfaces:

| Source surface | Mounted API | Handlers | Source UI behavior |
|---|---|---:|---|
| Engineering progress and output value | `/api/v1/progress` | 7 | `ProjectProgress.vue` reads progress, outputs, and contracts; creates progress/output rows, reports actual percentage, and confirms output value. |
| Project plan and task reporting | `/api/v1/plan` | 9 | `ProjectPlan.vue` reads tasks, posts task reports, creates tasks, requests AI scheduling, and requests delay impact. |

The source `progress` handlers are:

```text
GET    /progress
POST   /progress
PUT    /progress/:guid/report
DELETE /progress/:guid
GET    /outputs
POST   /outputs
POST   /outputs/:guid/confirm
```

The source `plan` handlers are:

```text
GET    /projects/:projGuid/tasks
GET    /tasks/:guid
POST   /tasks/:guid/report
GET    /projects/:projGuid/plan-summary
POST   /tasks
PUT    /tasks/:guid
DELETE /tasks/:guid
POST   /ai-suggest-plan
GET    /tasks/:guid/delay-impact
```

The source also feeds project detail and dashboards through lifecycle, KPI,
anomaly, and report endpoints. Those consumers must not be treated as
delivery parity until their source joins and calculations are reproduced.

## Current target state

- Rabbita mounts `/project/progress` and `/project-plan`. Before loading the
  combined delivery overview it reads the source-compatible
  `/api/company/source/delivery/progress` and `/outputs` boundaries, then loads
  `/api/company/delivery/overview?project_id=...` for the task/report view. The
  pages show source/command provenance and expose guarded progress, output, and
  task-report commands while retaining the designer layout.
- The local service and read-model adapter expose these fixed reads:
  `/api/company/delivery/progress`, `/outputs`, `/tasks`, `/task-reports`,
  `/plan-summary`, and `/overview`, plus the source-only
  `/api/company/source/delivery/progress` and `/outputs` reads. Commands cover
  progress create/report/accept/reject, output create/confirm, and task
  reporting.
- Imported rows are source-preserving and read-only. Local commands require
  explicit evidence, scope, currency/value, and idempotency keys; each command
  persists an immutable projection revision and audit receipt.
- The parity matrix marks the two browser pages and their command groups as
  `connected_delivery_command_form` / `connected_delivery_command`, and now
  maps source POST `/progress`, PUT `/progress/:guid/report`, POST
  `/outputs`, and POST `/outputs/:guid/confirm` to that evidence-gated command
  boundary. Source DELETE `/progress/:guid` remains intentionally unconnected:
  the target has no progress tombstone command, and imported rows stay
  read-only. The source export still contains no `proj_progress` or
  `proj_output` rows, so the new source reads return an explicit empty
  observation; current progress/output examples remain local command evidence
  rather than a source-row import.
- `scripts/erp_delivery_progress_plan.py` promotes only `jd_task_report` to a
  `Draft` `ProgressReport`; it requires explicit project/principal/scope,
  evidence, currency, and measured-value mapping and never mutates task state.
- `scripts/erp_delivery_recognition_plan.py` is a separate reviewed gate. It
  requires accepted evidence and a positive measured amount before creating a
  `pending_posting` recognition link; posting, cash, tax, and close remain
  separate.
- `scripts/fixtures/schema_delivery_treasury_mapping.json` maps
  `proj_progress` and `proj_output` as typed-import candidates, but the
  available export has no rows for those tables.
Therefore the delivery migration state is:

```text
domain model                  implemented and tested
typed draft/recognition       replayable evidence cohorts
local runtime reads/commands  connected and PostgreSQL-smoke verified
source-row coverage           explicitly observed empty; promotion blocked until a reviewed cohort exists
browser acceptance            pending real session/production identity
production ownership          not authorized
```

## Revised execution slice

The first local runtime slice, including the empty-safe source progress/output
read boundary, is complete. Its remaining acceptance work is:

1. Obtain a credential-safe export containing real `proj_progress` and
   `proj_output` rows (or an explicitly redacted, owner-approved cohort), then
   replay those rows through the source-preserving read boundary. `jd_task` and
   `jd_task_report` reads already retain source IDs and snapshots.
2. Run the browser pages through the real session/actor boundary and capture
   duplicate/replay, rejection/resubmission, acceptance-evidence,
   output-confirmation, and dependency-conflict evidence. The local smoke
   already covers the command transitions and idempotent replay.
3. Obtain a named operations owner decision on imported task-state conflicts
   and on the distinction between observed task reports and command-owned
   projections.
4. Only after named operations and finance owners accept the delivery slice,
   attach cost-forecast, recognition, contract-milestone, treasury, tax, and
   reporting consequences. No delivery report may post revenue, release cash,
   consume a budget, or close a period implicitly.

## Gate evidence required

Completion requires the source route/action parity matrix to remain in an
explicitly connected state, PostgreSQL projection parity and idempotent replay,
browser acceptance with the real session boundary, a source-backed
`proj_progress`/`proj_output` cohort, and a named operations owner decision on
source task-state conflicts. A local synthetic command cohort alone is
insufficient. The current smoke evidence proves the local command/replay gate;
source-row import, browser acceptance, and ownership remain open.
