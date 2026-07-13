# ERP Workflow Assignment Cohort

Recorded: 2026-07-13

The source ERP contains six `wf_step_assignee` rows. They are migrated as
workflow configuration, not as permissions or automatic approval authority.

`scripts/erp_workflow_assignment_plan.py` requires explicit mappings for:

- source user to target actor/user identity;
- process to legal principal and workflow scope;
- every step to a local capability.

The planner also verifies that each assignee references an exported workflow
step and process definition. Missing identities, processes, steps, scopes,
capabilities, or positive weights quarantine the row.

`cmd/workflow_assignment` validates each assignment through the local
`ProcessDefinition::assign_step` and `attach_assignment` boundaries and emits
the normal domain receipt. The receipt records an explicit attached process /
step reference for each assignment.
The resulting `workflow_assignment` projections retain process, step, actor-assignee,
principal, scope, and weight. They also persist the invariant markers
`configuration_only=true`, `grants_authority=false`, and
`approves_instance=false`. The native `WorkflowAssignmentAttachment` evidence
is identity-checked against the attached process and step and carries the same
markers. It does not grant roles, bypass decision-time authority, or approve
workflow instances.

Applications opt into decision enforcement by attaching the assignment to a
`ProcessDefinition`. New instances inherit attached assignments; a configured
step then rejects unassigned actors while preserving the ordinary capability
and principal checks. Definitions with no attached assignments retain the
legacy open-assignment behavior until their cohort is reviewed.

The ninth argument to `scripts/erp_migration_rehearsal.sh` supplies the mapping:

```text
... \
  scripts/fixtures/cbs_cost_link_mapping.json \
  scripts/fixtures/workflow_assignment_mapping.json
```

The fixture produces six exact-parity assignment projections, each with an
explicit attachment reference, and an idempotent replay. The target process
definition remains opt-in; attachment metadata does not mutate permissions or
approval state.
Approval-execution enforcement is still a separate decision-time capability
check; a valid assignee without that capability is rejected. A delegated
decision can now use `AccessDirectory::issue_delegated_grant` through the
workflow boundary; its effective window, revocation, assignee identity, and
delegation ID are retained as decision evidence. Workflow SLA policies now
produce authority-checked due/overdue observation evidence without changing
approval state; notification delivery and segregation of duties remain later
workflow integrations.
