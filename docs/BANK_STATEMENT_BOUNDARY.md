# Bank Statement Boundary

Recorded: 2026-07-13

The treasury model now distinguishes a bank statement from a cash movement:

- statement import records immutable bank lines, period, opening/closing
  balances, currency, and external references;
- balance validation checks that opening balance plus inflows minus outflows
  equals the supplied closing balance;
- reconciliation matches every statement line exactly once to a released or
  already reconciled cash movement with matching account, principal, scope,
  amount, currency, and direction;
- ledger reconciliation then matches each reconciled statement line to one
  balanced accounting event whose source identity matches the cash movement;
- statement reconciliation does not release cash, alter account balance, or
  post a journal. Ledger reconciliation records traceability evidence only.

`BankStatement::from_statement` and `BankStatement::reconcile` require separate
treasury authority grants. The aggregate persists as `Imported` or
`Reconciled` evidence; `BankStatement::reconcile_to_ledger` requires a third
grant and persists `LedgerReconciled` evidence with line-to-event identities.
External bank connectors, statement file formats, and period-close/subledger
production evidence remain deployment gates.
