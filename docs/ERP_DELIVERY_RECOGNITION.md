# ERP Reviewed Delivery-Recognition Cohort

Recorded: 2026-07-13

The `jd_task_report` source cohort is draft operational evidence. It cannot
by itself prove acceptance or a monetary completion value. Recognition is
therefore a separate, opt-in cohort driven by
`scripts/erp_delivery_recognition_plan.py` and
`cmd/delivery_recognition`.

The plan must provide a reviewed acceptance state, acceptance ID, acceptance
evidence IDs, accepted actor, positive measured amount/currency, project and
principal scope, an explicit `amount_basis=reviewed_measurement`, and explicit
contract-asset and revenue accounts. Missing or pending review evidence
quarantines the row. The native command reconstructs
the accepted progress state, verifies the acceptance actor and recognition
authority, and emits a `delivery_recognition` projection candidate.

The projection is a source-to-journal link with `recognition_state` set to
`pending_posting`. It persists the acceptance evidence and journal identity but
explicitly records `posted=false`, `cash_released=false`, and
`period_closed=false`. A later accounting-link mapping may reconcile the
explicit journal through the allow-listed `delivery_progress` source type;
posting, cash release, tax treatment, and period close remain independent
controls. Its optional accounting-link reconciliation uses target type
`delivery_recognition` and the governed source type `delivery_progress`, so a
recognition link cannot be mistaken for a second operational report.

The fourteenth argument to `scripts/erp_migration_rehearsal.sh`, or the
twelfth argument to `scripts/company_postgres_cohort_rehearsal.sh`, supplies a
reviewed mapping. A following optional argument supplies the reviewed
accounting-link mapping for the same receipt. No mapping is supplied by the
available fixture because its only task report remains draft evidence with
zero measured value.
