# ERP Warning and Exception Evidence Boundary

Recorded: 2026-07-13

`intelligence/warning` now persists deterministic warning findings as
source-bound `warning_finding` projections. A finding is still created and
transitioned only through its scoped authority checks; binding a source
snapshot, mapping version, and evidence ID makes the result auditable and
replayable.

`cmd/warning` accepts
`moonproj.company.warning-plan.v1` and emits the normal domain-promotion
receipt. The projection records rule, target, severity, state, lifecycle
events, and provenance while explicitly keeping
`notification_delivered=false`, `workflow_mutated=false`, and
`cash_released=false`. No notification, workflow approval, cash movement, or
accounting post is inferred.

The nineteenth SQLite rehearsal argument (and sixteenth PostgreSQL cohort
argument) accepts a reviewed warning plan and runs the usual projection,
parity, and idempotent replay checks. The checked-in example is synthetic;
real `sys_warning` rows and notification routing still require source and
owner acceptance.

The optional twenty-second SQLite argument (or nineteenth PostgreSQL cohort
argument) accepts `scripts/fixtures/warning_source_mapping.json` and runs
`scripts/erp_warning_plan.py` against the real `cb_cost` export. The mapping
names the exact leaf rows to scan, target/component fields, and project scope;
the planner rejects missing or extra overrun rows so parent/child costs cannot
be double-counted. The fixture produces one `warning_finding` for the two
positive component overruns, with source IDs and minor-unit evidence retained
while notification, workflow, cash, and accounting effects remain false.
