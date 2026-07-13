# ERP Invoice and Subledger Boundary

This opt-in cohort is the reviewed bridge from ERP invoice rows to company
invoice, receivable, and payable evidence. It is deliberately separate from
cash release, revenue/expense posting, tax settlement, and period close.

The reviewed map accepts `invoice_out` customer invoices and `invoice_in`
supplier invoices only when source identity, principal, customer/supplier,
project scope, currency, amount, and payment totals are explicit. The native
command issues and accepts each customer invoice, opens its receivable, and
records a bounded partial or full collection. Supplier obligations open and
record bounded partial or full payments through the payable aggregate.

The checked-in fixture contains two customer invoices (CNY 800,000 with
CNY 300,000 collected, and CNY 500,000 fully collected) plus one CNY 700,000
supplier payable with CNY 175,000 paid. It emits five immutable aggregate
candidates: two `invoice`, two `receivable`, and one `payable` projection.

SQLite and PostgreSQL adapters compare complete candidates by target and source
identity and replay the same receipt idempotently. All candidates explicitly
keep `cash_released`, `accounting_posted`, and `period_closed` false. The
available ERP snapshot has no accepted invoice rows in the reviewed export, so
the fixture remains evidence until a redacted source map and business-owner
review are supplied.
