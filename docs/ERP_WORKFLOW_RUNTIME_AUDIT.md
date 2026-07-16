# ERP Workflow Definition Runtime Audit

Recorded: 2026-07-14
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source workflow module exposes both definition/preview reads and instance
task/approval commands. The available credential-safe backup contains the
definition side only: two active process definitions, twelve ordered steps,
and six assignee mappings. It contains no process instances or step actions.

The target connects source-preserving definition/observation boundaries plus a
separate signed, command-owned local workflow boundary. Imported workflow rows
remain read-only; local commands never claim to be a source-engine promotion.

| Source surface | Target endpoint | Target state |
|---|---|---|
| Process definition list | `/api/company/workflow/process-defs` | source-preserving read |
| Process preview | `/api/company/workflow/process-defs/:processKey/preview` | source-preserving read |
| Rabbita task page | `/tasks` | source-shaped pending/initiated/history tabs plus explicit empty-instance evidence |
| Rabbita warning tasks | `/api/company/source/warning/tickets/mine` | source-shaped ticket queue; transitions remain local candidates |
| My pending tasks | `/api/company/source/workflow/tasks/mine?userCode=<code>` | empty-safe source observation |
| Initiated tasks | `/api/company/source/workflow/tasks/initiated?userCode=<code>` | empty-safe source observation |
| My task history | `/api/company/source/workflow/tasks/my-history?userCode=<code>` | empty-safe source observation |
| Instance by business key | `/api/company/source/workflow/instances/by-biz` | null-safe source observation |
| Instance detail | `/api/company/source/workflow/instances/:piGuid` | source-compatible 404 |
| Local instance start | `POST /api/company/source/workflow/instances` and `/api/company/workflow/instances` | signed command-owned projection |
| Local approve/reject | `POST .../instances/:piGuid/{approve,reject}` | signed local-owner action projection |
| Local cosign/transfer | `POST .../instances/:piGuid/{cosigners,transfer}` | signed local-owner action projection |
| Canonical aliases | `/api/company/workflow/tasks/*` and `/api/company/workflow/instances/*` | source-compatible read aliases |

Local start/approve/reject/cosign/transfer commands persist immutable `workflow_instance` and
`workflow_action` projections, command receipts, and audit events. They expose
`workflow_effect=true` but keep provider, cash, accounting, and tax effects
false. Full source-engine assignment/delegation, business hooks, and imported
workflow mutation remain gated.

## Current evidence

- Native MoonBit PostgreSQL service smoke returns two process definitions, twelve steps, six
  assignees with imported user labels, and zero instance/action rows.
- The loan preview returns the five source-defined loan approval steps while
  retaining `instances_available=0` and `actions_available=0`.
- Rabbita `/tasks` now renders live pending, initiated, history, and warning-task
  tabs from the PostgreSQL source endpoints. With the current export the workflow
  lists and ticket queue are empty-safe (`source rows=0`) instead of presenting
  designer cards as source approval work; imported workflow fields include current
  step, initiator, completion, and last-action evidence when present.
- The PostgreSQL read-model server now serves the same definition endpoint as
  the authenticated service; a browser recheck rendered both imported
  definitions, twelve steps, six assignee links, and zero instance/action
  rows without a 404 or fixture substitution.
- The read-model preview endpoint returns the source-shaped seven-step
  `expense-approval` preview and a 404 for an unknown process key, preserving
  the service adapter's detail boundary.
- `scripts/company_postgres_source_read_smoke.sh` verifies the three empty list
  reads, a null by-business lookup, and the source-compatible 43001 detail 404.
- `scripts/company_postgres_workflow_smoke.sh` verifies signed local start,
  idempotent replay, pending-task readback, approval, rejection, cosign,
  transfer, canonical aliases, detail actions, and cleanup without Python.
- The parity matrix marks the two definition GET handlers as
  `connected_workflow_definition_read` and the five instance/task GET handlers
  as `connected_workflow_observation_read`; local start/approve/reject/cosign/transfer commands
  are registered as a separate command-owned boundary.

## Remaining gate

1. Obtain source `wf_process_instance` and `wf_step_action` rows, or an
   owner-approved explicit empty-data disposition, before treating local
   command projections as source workflow authority. The current local action
   boundary is intentionally not source-engine synchronization.
2. Replace the local gateway session with production identity and verify BU,
   principal, delegation, and separation-of-duties scope for any future
   instance commands.
3. Run browser acceptance for definition/preview parity without treating the
   definitions as approval authority.
