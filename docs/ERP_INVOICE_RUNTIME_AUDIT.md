# ERP invoice and tax-ledger runtime audit

Recorded: 2026-07-14  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The ERP invoice module has three read families: incoming invoices, outgoing
invoices, and a monthly tax ledger. The controlled export contains no
`invoice_in` or `invoice_out` rows, so the target must show an explicit empty
source result rather than the designer's sample invoices.

## PostgreSQL boundary

The authenticated service and read-model adapter expose:

- `/api/company/source/invoice/in?projGuid=<guid>&contractGuid=<guid>`;
- `/api/company/source/invoice/out?projGuid=<guid>`;
- `/api/company/source/invoice/tax-ledger?projGuid=<guid>`.

The first two preserve the source invoice fields and compatibility fields used
by Rabbita. The tax-ledger response preserves `{ data: { rows } }` with period,
input/output totals, tax, and net-tax fields. Every response carries source
coverage and `authorizing=false`, `persisted=false`, and
`provider_execution=false`.

## Current evidence

- `invoice_in` and `invoice_out` both return zero rows for `proj-0001`.
- The tax-ledger read returns zero monthly rows while preserving its source
  shape.
- Rabbita `/invoice` chains incoming, outgoing, and tax-ledger reads and shows
  the source observation alongside the existing designer layout.
- `scripts/company_postgres_source_read_smoke.py` verifies all three reads
  without mutating PostgreSQL.
- The parity matrix marks source `GET /in`, `/out`, and `/tax-ledger` as
  `connected_invoice_source_read`.

## Open gates

Invoice creation/deletion, OCR/verification, tax filing, accounting posting,
cash settlement, production identity, browser acceptance, and finance-owner
reconciliation remain separate gates. No invoice rows are seeded from fixture
data by this read-only slice.
