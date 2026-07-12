# ERP Sales-Receivables Schema Cohort

Recorded: 2026-07-13  
Source wave: `sales-receivables` from `../erp/erp_new/server/src/db/index.js`

The fifth schema-only wave maps customer, subscription, sales agreement,
mortgage, refund, revenue, inbound-invoice, and outbound-invoice tables to the
sales, invoice, receivable, payable, and tax boundaries.

The translation preserves the business lifecycle rather than collapsing tables
into a single “revenue” record:

- invoices do not automatically open receivables/payables without authority;
- collection and payment cash remain separate events;
- fulfillment, revenue recognition, tax, refund, and cash reversal are distinct;
- supplier and customer identity mappings are required before import;
- revenue rows are evidence until the target policy and period are accepted.

The machine-readable mapping is
`scripts/fixtures/schema_sales_receivables_mapping.json`; each rehearsal emits
`schema-sales-receivables.json` with eight mapped tables, zero available rows,
and `promotion_authorized=false`.
