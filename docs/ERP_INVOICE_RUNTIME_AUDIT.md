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

The same source-shaped paths now accept bounded native local commands:

- `POST /api/company/source/invoice/in` and `/out` register a local invoice;
- `DELETE /api/company/source/invoice/in/:guid` and `/out/:guid` tombstone a
  local invoice.

The first two preserve the source invoice fields and compatibility fields used
by Rabbita. The tax-ledger response preserves `{ data: { rows } }` with period,
input/output totals, tax, and net-tax fields. Imported rows remain read-only;
local command projections appear with `sourceKind=command`, deterministic
idempotency, aggregate revisions, and audit receipts. Every response carries
source coverage and `authorizing=false`; provider execution remains disabled.

## Current evidence

- `invoice_in` and `invoice_out` both return zero imported rows for `proj-0001`.
- The tax-ledger read returns zero monthly rows while preserving its source
  shape.
- Rabbita `/invoice` loads projects plus incoming, outgoing, and tax-ledger
  reads, supports project switching, mirrors the three source tabs, renders
  live invoice/tax rows, and derives the three headline totals from those
  rows. The source Vue dialog fields and row-level delete/register controls
  remain the next browser slice.
- `scripts/company_postgres_source_read_smoke.sh` verifies all three reads
  without mutating PostgreSQL.
- `scripts/company_postgres_invoice_smoke.sh` verifies authority validation,
  fallback identity, replay/collision, tax-ledger readback, and tombstones;
  the native gateway smoke verifies trusted forwarding for create/delete.
- The parity matrix marks source `GET /in`, `/out`, and `/tax-ledger` as
  `connected_invoice_source_read`, and invoice POST/DELETE actions as
  `connected_invoice_command` with a finance-owner acceptance gate.

## Open gates

OCR/verification, tax filing, accounting posting, cash settlement, production
identity, browser acceptance, and finance-owner reconciliation remain separate
gates. No invoice rows are seeded from fixture data; local command rows are
explicitly separate from imported source rows.
