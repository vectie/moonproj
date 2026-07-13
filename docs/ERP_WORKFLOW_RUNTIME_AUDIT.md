# ERP Workflow Definition Runtime Audit

Recorded: 2026-07-13  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source workflow module exposes both definition/preview reads and instance
task/approval commands. The available credential-safe backup contains the
definition side only: two active process definitions, twelve ordered steps,
and six assignee mappings. It contains no process instances or step actions.

The target therefore connects only the non-authorizing definition boundary:

| Source surface | Target endpoint | Target state |
|---|---|---|
| Process definition list | `/api/company/workflow/process-defs` | source-preserving read |
| Process preview | `/api/company/workflow/process-defs/:processKey/preview` | source-preserving read |
| Rabbita task page | `/tasks` | definition read plus explicit empty-instance evidence |

The target does not create, approve, reject, assign, transfer, or synchronize
workflow instances from this slice.

## Current evidence

- PostgreSQL service smoke returns two process definitions, twelve steps, six
  assignees, and zero instance/action rows.
- The loan preview returns the five source-defined loan approval steps while
  retaining `instances_available=0` and `actions_available=0`.
- Rabbita `/tasks` shows the connected definition rows and labels the existing
  task cards as a design snapshot when no source instances exist.
- The parity matrix marks the two source definition GET handlers and `/tasks`
  as `connected_workflow_definition_read`; instance/task reads and all
  workflow mutations remain unconnected.

## Remaining gate

1. Obtain source `wf_process_instance` and `wf_step_action` rows, or an
   owner-approved explicit empty-data disposition, before enabling task or
   approval behavior.
2. Replace the local gateway session with production identity and verify BU,
   principal, delegation, and separation-of-duties scope for any future
   instance commands.
3. Run browser acceptance for definition/preview parity without treating the
   definitions as approval authority.
