# ERP Task-State Exception Review

Recorded: 2026-07-13  
Status: review required; no automatic state repair

The source fixture reports two child task states for `proj-0001` that depend on
`task-003`, while the parent is still `in_progress`. Replaying those rows as
completed or progressing target tasks would violate the target dependency
invariant.

`scripts/erp_task_state_exception_review.py` consumes the full task-state plan
and emits `task-state-exception-review.json` with the observed rows, exact
dependency conflicts, and empty decision fields. The allowed decisions are:

- `retain_source_evidence`;
- `approve_dependency_repair`;
- `map_state_as_observed_only`;
- `exclude_from_target`.

Every exception requires a named owner, decision timestamp, and decision note.
The review artifact never authorizes a target mutation. Until a decision is
recorded and separately implemented/tested, project-1 state remains quarantined
while the clean project-2 cohort may replay normally.
