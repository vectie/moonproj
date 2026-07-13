# ERP Receivable and Payable Settlement Accounting Boundary

Recorded: 2026-07-13

The company product keeps operational settlement state separate from accounting
and treasury effects. `Receivable::collect` and `Payable::record_payment`
remain authority-bearing state transitions. Their new
`to_collection_event` and `to_payment_event` adapters create separately
identified, balanced source-to-journal evidence with explicit cash and
subledger accounts.

The accounting planner and native linker recognize `receivable_collection` and
`payable_payment` as distinct source types. The durable SQLite/PostgreSQL
adapters persist event/source/journal/principal identity transactionally and
replay them idempotently. Neither adapter releases cash, posts the accounting
book, closes a period, or infers revenue/payment policy.

The checked-in example fixtures prove two settlement links through the planner,
native validator, durable apply, second-run zero insert, and reconciliation
report. They are synthetic migration evidence only; a real ERP settlement
cohort still requires source completeness, reviewed mappings, and owner
acceptance.
