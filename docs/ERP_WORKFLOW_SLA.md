# Workflow SLA and Escalation Evidence

Recorded: 2026-07-13

`operations/workflow` now supports explicit `WorkflowSlaPolicy` records for a
process step. A policy names its process/step, due interval, exact escalation
actor, and scope; adding it requires `workflow:sla:add` authority.

`ProcessInstance::evaluate_sla` takes explicit start and observation epochs and
returns deterministic `Due` or `Overdue` evidence. Recording that evidence
requires `workflow:sla:observe` authority and retains the policy, due time,
observation time, escalation actor, and stable evidence identity.

SLA evidence is observation-only. It records
`notification_requested=true` when overdue, but never grants the escalation
actor authority, approves an instance, changes the current step, or appends an
approval action. Notification delivery, escalation routing, and any delegated
approval remain separate controls.
