# ERP Sales and Receivables Cohort

Recorded: 2026-07-13
Status: reviewed local rehearsal; no cash or accounting authority

The sales cohort exercises the target's existing native sales domain against a
reviewed synthetic map derived from the ERP sales surface. It preserves one
customer, one subscription conversion, one fulfilled sales agreement, one
opened receivable, one released mortgage-evidence lifecycle, one paid refund
workflow, and one sale-revenue evidence row: seven durable projections.

`scripts/erp_sales_cohort_plan.py` requires explicit customer, project,
contract, amount, currency, mortgage, refund, and revenue identities. It
rejects secret-shaped fields, amount/currency drift, over-refunds, and revenue
rows that are not explicitly marked `source_evidence_only`.

`cmd/sales_cohort` reconstructs customer, reservation, agreement, receivable,
mortgage, and refund state machines through their native authority checks. The
sale-revenue row remains evidence only; it does not recognize revenue or
settle cash. The cohort receipt explicitly keeps collection, refund cash,
accounting posting, and period close false.

`scripts/company_sales_cohort_rehearsal.sh` applies the native receipt to
SQLite and PostgreSQL, compares exact source/target identity and type counts,
and replays it. The local rehearsal reports seven `shadow_verified` items on
both backends; each replay inserts zero projections.

The available ERP snapshot contains no accepted sales rows for this schema-only
surface. Production customer/contract/mortgage/refund/revenue exports,
identity mapping, finance policy, and business-owner acceptance remain open.
