# ERP Workflow Definition Runtime Audit

Recorded: 2026-07-14
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source workflow module exposes both definition/preview reads and instance
task/approval commands. The available credential-safe backup contains the
definition side only: two active process definitions, twelve ordered steps,
and six assignee mappings. It contains no process instances or step actions.

The target therefore connects only non-authorizing definition and observation
boundaries:

| Source surface | Target endpoint | Target state |
|---|---|---|
| Process definition list | `/api/company/workflow/process-defs` | source-preserving read |
| Process preview | `/api/company/workflow/process-defs/:processKey/preview` | source-preserving read |
| Rabbita task page | `/tasks` | definition read plus explicit empty-instance evidence |
| My pending tasks | `/api/company/source/workflow/tasks/mine?userCode=<code>` | empty-safe source observation |
| Initiated tasks | `/api/company/source/workflow/tasks/initiated?userCode=<code>` | empty-safe source observation |
| My task history | `/api/company/source/workflow/tasks/my-history?userCode=<code>` | empty-safe source observation |
| Instance by business key | `/api/company/source/workflow/instances/by-biz` | null-safe source observation |
| Instance detail | `/api/company/source/workflow/instances/:piGuid` | source-compatible 404 |

The target does not create, approve, reject, assign, transfer, or synchronize
workflow instances from this slice.

## Current evidence

- PostgreSQL service smoke returns two process definitions, twelve steps, six
  assignees with imported user labels, and zero instance/action rows.
- The loan preview returns the five source-defined loan approval steps while
  retaining `instances_available=0` and `actions_available=0`.
- Rabbita `/tasks` shows the connected definition rows, imported assignee names,
  and chains pending, initiated, and history source observations. With the
  current export those lists are empty and the page says
  `wf_process_instance=0` instead of presenting the designer cards as source
  approval work.
- The PostgreSQL read-model server now serves the same definition endpoint as
  the authenticated service; a browser recheck rendered both imported
  definitions, twelve steps, six assignee links, and zero instance/action
  rows without a 404 or fixture substitution.
- The read-model preview endpoint returns the source-shaped seven-step
  `expense-approval` preview and a 404 for an unknown process key, preserving
  the service adapter's detail boundary.
- `scripts/company_postgres_source_read_smoke.py` verifies the three empty list
  reads, a null by-business lookup, and the source-compatible 43001 detail 404.
- The parity matrix marks the two definition GET handlers as
  `connected_workflow_definition_read` and the five instance/task GET handlers
  as `connected_workflow_observation_read`; instance/task mutations remain
  unconnected.

## Remaining gate

1. Obtain source `wf_process_instance` and `wf_step_action` rows, or an
   owner-approved explicit empty-data disposition, before enabling task or
   approval behavior. The current read observation is not approval authority.
2. Replace the local gateway session with production identity and verify BU,
   principal, delegation, and separation-of-duties scope for any future
   instance commands.
3. Run browser acceptance for definition/preview parity without treating the
   definitions as approval authority.
