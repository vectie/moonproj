# ERP Delivery and Project-Progress Runtime Audit

Recorded: 2026-07-13  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The target has a real delivery domain and repeatable migration evidence, but it
does not yet have a connected delivery runtime. The native
`operations/delivery` package validates evidence-backed progress,
deliverable acceptance/remediation, cost-forecast input, and a separate
pending-posting recognition link. The `cmd/delivery_progress` and
`cmd/delivery_recognition` cohorts prove SQLite/PostgreSQL projection parity
and idempotent replay for explicitly mapped synthetic evidence. They do not
serve the source ERP routes or make a browser page functional.

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

- Rabbita mounts `/project/progress` and `/project-plan`, but both are
  fixture-backed views with no load or command messages.
- The parity matrix correctly marks the seven progress handlers as
  `not_connected` and the two pages as `fixture_backed_read_only`.
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
- `scripts/company_postgres_service.py`, its read-model adapter, gateway, and
  Rabbita state model currently expose no delivery/progress/plan endpoint.

Therefore the delivery migration state is:

```text
domain model                 implemented and tested
typed draft/recognition      replayable evidence cohorts
source-backed runtime reads  not connected
source-faithful commands     not connected
browser acceptance            not started
production ownership          not authorized
```

## Revised execution slice

The next delivery slice must be implemented in this order:

1. Add read-only PostgreSQL projections for `proj_progress`, `proj_output`,
   `jd_task`, and `jd_task_report`, retaining source IDs, source snapshot, and
   imported/read-only status. Add project filtering and detail views before
   any mutation endpoint.
2. Define a target command contract for progress creation/reporting, output
   creation/confirmation, and task reporting. Use the native authority and
   evidence rules; do not mirror legacy deletes or mutate imported rows in
   place. Draft imports remain immutable source evidence.
3. Wire the Rabbita `/project/progress` and `/project-plan` pages to those reads
   and commands, including loading/error/empty states and visible source-vs-
   command provenance. Keep the existing designer layout while replacing
   fixture rows only after the response shape is verified.
4. Rehearse one source-backed or explicitly redacted cohort through PostgreSQL,
   including duplicate/replay, rejection/resubmission, acceptance evidence,
   output confirmation, and task dependency conflict behavior.
5. Only after named operations and finance owners accept the delivery slice,
   attach cost-forecast, recognition, contract-milestone, treasury, tax, and
   reporting consequences. No delivery report may post revenue, release cash,
   consume a budget, or close a period implicitly.

## Gate evidence required

Completion requires the source route/action parity matrix to change the
delivery and plan entries from fixture/not-connected to explicitly connected
states, PostgreSQL projection parity and idempotent replay, browser acceptance
with the real session boundary, and a named operations owner decision on
source task-state conflicts. A synthetic native cohort alone is insufficient.
