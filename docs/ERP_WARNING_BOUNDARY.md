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
