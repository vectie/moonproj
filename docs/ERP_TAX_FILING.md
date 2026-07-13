# ERP Tax-Filing Boundary

Recorded: 2026-07-13
Source: `../erp/erp_new`
Target: this repository

Tax filing is a reviewed company boundary, not an inferred side effect of an
invoice or payment row. A reviewer must provide source identity, principal and
scope, jurisdiction/category, base amount, tax and withholding rates, filing
period, authority reference, and the accepted/rejected/submitted outcome.

`scripts/erp_tax_filing_plan.py` validates a reviewed
`moonproj.erp.tax-filing-map.v1`, rejects duplicate source/filing identities,
invalid amounts or rates, unreviewed maps, and secret-shaped keys, and emits a
versioned `moonproj.erp.tax-filing-plan.v1`.

`cmd/tax_filing` drives the native `finance/tax` aggregate for every plan item:

```text
Draft → Calculated → Reviewed
     → Prepared → Submitted → Accepted | Rejected
```

The receipt preserves the calculated tax and withholding amounts, rates,
currency, filing state, period, authority reference, and transition-event
counts. It records `tax_payment_recorded=false`, `accounting_posted=false`,
`cash_released=false`, and `period_closed=false`; no tax payment, ledger
posting, or external authority call occurs.

The SQLite rehearsal accepts the twenty-seventh argument and the PostgreSQL
cohort runner accepts the twenty-fifth argument:

```text
scripts/fixtures/tax_filing_mapping.example.json
```

Both wrappers apply the native receipt, compare complete candidates with
`scripts/company_tax_filing_parity.py`, and replay idempotently. The synthetic
fixture contains one accepted VAT filing and one rejected withholding filing;
it proves the local boundary only. The available ERP snapshot has no tax rows,
so production tax-source identity, finance-owner approval, payment adapters,
filing credentials, and tax-authority integration remain open.
