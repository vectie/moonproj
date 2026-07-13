# ERP Bank-Statement Boundary

Recorded: 2026-07-13
Source: `../erp/erp_new`
Target: this repository

Bank statements are imported as immutable treasury evidence before any cash or
ledger authority is exercised. A reviewed map names the statement/account,
principal and scope, period, currency, opening and closing balances, and every
line's external reference, booking time, amount, and inflow/outflow direction.

`scripts/erp_bank_statement_plan.py` accepts only a reviewed
`moonproj.erp.bank-statement-map.v1`, rejects duplicate statement or line
identities, invalid amounts/directions, missing scope, unreviewed maps, and
secret-shaped keys, and emits a versioned
`moonproj.erp.bank-statement-plan.v1`.

`cmd/bank_statement` calls native `finance/treasury.BankStatement::from_statement`.
The native boundary checks line uniqueness, account/principal/scope equality,
currency equality, positive line amounts, and that opening balance plus inflows
minus outflows equals closing balance. It emits a normal
`moonproj.erp.domain-promotion.v1` receipt under `bank-statement-v1` with the
complete line set and `state=imported`.

The SQLite rehearsal accepts the twenty-eighth argument and the PostgreSQL
cohort runner accepts the twenty-sixth argument:

```text
scripts/fixtures/bank_statement_mapping.example.json
```

Both wrappers apply the native receipt, compare complete statement candidates
with `scripts/company_bank_statement_parity.py`, and replay idempotently. The
synthetic fixture contains one balanced two-line statement. Import does not
match movements, reconcile to ledger events, release cash, post accounting,
call a bank provider, or close a period; those remain separate reviewed gates.
