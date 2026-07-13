# ERP Invoice and Procurement Accounting-Link Boundary

Recorded: 2026-07-13

This slice extends the operational invoice/subledger and procurement cohorts
through an explicit, non-posting source-to-journal boundary. A single reviewed
accounting map supports target-specific mappings because one source invoice can
emit a receivable or payable aggregate, and one tender can emit a commitment.

```text
invoice/procurement source map
  -> native invoice/procurement receipts
  -> target-specific accounting-link map
  -> cmd/accounting_link
  -> SQLite/PostgreSQL traceability links
```

The checked-in synthetic run produces four links:

- two customer receivable-opening links for CNY 800,000 and CNY 500,000;
- one supplier payable-opening link for CNY 700,000; and
- one performed procurement commitment link for CNY 1,050,000.

The accounting planner now prefers a `source_table:source_id:target_type`
mapping key and falls back to the legacy source key for one-target cohorts.
Every link still requires explicit event, journal, principal, scope, amount,
currency, and balanced debit/credit account fields. SQLite and PostgreSQL
adapters report exact identity parity for the three-invoice-link and
one-commitment-link receipts; replay inserts zero links.

Run the dedicated rehearsal with:

```text
scripts/company_invoice_procurement_accounting_rehearsal.sh \
  scripts/fixtures/invoice_subledger_mapping.example.json \
  scripts/fixtures/procurement_cohort_mapping.example.json \
  scripts/fixtures/invoice_procurement_accounting_mapping.example.json \
  /tmp/invoice-procurement-accounting.sqlite3 moonproj_migration_full2 \
  /tmp/invoice-procurement-accounting
```

This is traceability evidence only. It does not release collection or payment
cash, post the accounting book, settle tax, close a period, or mutate the ERP.
The available snapshot has no accepted invoice, receivable, payable, supplier,
or tender rows, so production source exports, account policy, finance-owner
review, and settlement/period-close acceptance remain open.
