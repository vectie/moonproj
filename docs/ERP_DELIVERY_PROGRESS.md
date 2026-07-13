# ERP Task-Report Delivery-Progress Cohort

Recorded: 2026-07-13  
Source: `jd_task_report`  
Target: `operations/delivery.ProgressReport`

## Semantic boundary

The source report records observed task progress, a report date, an operator,
and a free-text summary. It does not prove that a deliverable was inspected or
accepted, and it does not provide a reliable monetary completion value.

The reviewed cohort therefore creates a target `ProgressReport` in `Draft`
state only. The mapping explicitly supplies a zero completed value until a
business owner supplies an approved value. The source task/project identity,
operator, date, summary, and evidence reference remain in the native receipt
and the typed evidence projection.

The cohort cannot:

- submit or accept delivery progress;
- create revenue, contract-asset, payable, or cash effects;
- consume a budget or cost subject;
- mutate task state or waive dependency invariants.

## Rehearsal

The current fixture maps `rep-001` (`task-003`, `proj-0001`) to one draft
`progress_report` with 6,500 basis points and zero completed value. The native
command validates the local delivery-create authority and emits a normal
domain-promotion receipt. SQLite projection apply, exact parity, and replay
then verify the cohort independently.

This is a target-owned draft intake candidate, not delivery acceptance or
accounting recognition. Acceptance must be performed later by the normal
delivery workflow with evidence and authority.

Once a business owner supplies separately reviewed acceptance evidence and a
positive measured amount, the opt-in
[`ERP_DELIVERY_RECOGNITION.md`](ERP_DELIVERY_RECOGNITION.md) cohort can create a
pending-posting source-to-journal link. It does not upgrade this draft row in
place or perform posting, cash release, tax, or period close.
