# ERP Task-State Observed Evidence Cohort

Recorded: 2026-07-13
Source boundary: `jd_task` from `../erp/erp_new`
Target boundary: `project_task_state_observation` projection only

The source fixture contains two project-1 child states whose parent task is
still `in_progress`. The target dependency invariant correctly refuses to
replay those states as target-owned workflow state. This cohort preserves the
full observed project state and exact dependency conflicts as a company-owned
evidence projection without repairing, coercing, or authorizing the state:

```text
source task rows
  -> dependency-checked exception review
  -> project_task_state_observation (non-authorizing)
  -> named owner decision still required
```

## Executable boundary

- `scripts/erp_task_state_promotion_plan.py` derives the full mixed plan and
  retains the two project-1 dependency conflicts as quarantined items.
- `scripts/erp_task_state_exception_review.py` turns those conflicts into a
  review artifact with observed rows and empty decision fields.
- `cmd/task_state_evidence` accepts only that undecided, cutover-disabled
  review artifact and emits a native domain receipt with one
  `project_task_state_observation` candidate. The candidate carries the
  observed rows, conflict identities, `decision_required=true`, and
  `target_state_mutated=false`.
- `scripts/company_task_state_exception_evidence_rehearsal.sh` applies the
  receipt to isolated SQLite and optional PostgreSQL projection stores, checks
  exact identity parity, and proves zero-insert replay on both backends.

The receipt intentionally uses the normal projection adapters so the evidence
is durable and queryable, but its `observation_policy` is
`quarantined_source_evidence`. It does not grant task authority, repair a
dependency, change project state, release cash, post accounting, or close a
period. A later owner decision remains a separate migration event.

## Verification

The available source produces one quarantined project-1 exception. The native
evidence receipt persists one observation projection; SQLite and PostgreSQL
both report `shadow_verified`, and the second apply inserts zero projections.
The source task rows remain read-only evidence until a named owner supplies a
decision, timestamp, and rationale through the exception-review gate.
