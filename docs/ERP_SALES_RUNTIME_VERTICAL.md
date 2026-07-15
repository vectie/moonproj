# ERP sales and receivables runtime vertical

Status: local PostgreSQL/Rabbita slice verified; source export, production
identity, browser acceptance, and owner approval remain open.

The ERP sales route family (`/sales/customers`, `/sales/subscriptions`,
`/sales/contracts`, `/sales/mortgages`, and `/sales/revenues`) now has an
authenticated company read boundary. The target keeps customer, reservation,
sales-agreement, mortgage, refund, revenue evidence, and receivable as
separate aggregate types. This preserves the source distinctions without
turning a revenue row into an implicit cash or accounting event.

## Connected API

The native `cmd/postgres_company_service` exposes:

- `GET /api/company/sales/customers[/:id]`;
- `GET /api/company/sales/subscriptions[/:id]`;
- `GET /api/company/sales/contracts[/:id]`;
- `GET /api/company/sales/mortgages[/:id]`;
- `GET /api/company/sales/refunds[/:id]`;
- `GET /api/company/sales/revenues[/:id]`;
- `GET /api/company/receivables[/:id]`;
- `GET /api/company/invoices[/:id]` for reviewed invoice/subledger
  projections when an invoice cohort is present.

Revenue writes are also native and authority-bound:

- `POST /api/company/sales/revenues` creates a local expected/received
  projection;
- `PUT /api/company/sales/revenues/:id` updates mutable revenue fields;
- `POST /api/company/sales/revenues/:id/confirm-received` advances an expected
  revenue to received;
- `DELETE /api/company/sales/revenues/:id` records a local tombstone.

The former Python service remains frozen comparison evidence only. All native
commands require the signed actor assertion, an active principal/scope/
capability grant, and an `Idempotency-Key`.

Local commands use the same idempotent company-command and immutable revision
boundary:

- customer create/update/block/archive;
- reservation create/convert/cancel;
- sales-agreement create/fulfill/cancel;
- fulfilled-agreement receivable opening;
- mortgage create/approve/release;
- refund create/approve/pay/reject.
- revenue create/update/confirm-received/delete through a separate
  authority-checked local command boundary.

Imported projections are read-only. A fulfilled agreement opens a receivable
only through an explicit command; collections, refund cash, revenue
recognition, tax, journal posting, and period close remain separate effects.

The read-only development adapter exposes the same reads. Rabbita loads each
sales page through the gateway and shows the current source-observation count, source
kind, state, and amount while retaining the designer-provided source-shaped
tables as the fallback when PostgreSQL is unavailable.

The source-observation boundary is separate from those target projections:

- `GET /api/company/source/sales/customers` reads `sale_customer`;
- `GET /api/company/source/sales/subscriptions` reads `sale_subscription`;
- `GET /api/company/source/sales/contracts` reads `sale_contract`;
- `GET /api/company/source/sales/mortgages` reads `sale_mortgage`;
- `GET /api/company/source/sales/refunds` reads `sale_refund`;
- `GET /api/company/source/sales/revenues` reads `sale_revenue`.

Each response preserves the source row fields, adds normalized aggregate
identity for the Rabbita table, reports coverage for all six sales tables, and
marks the observation non-authorizing and non-persisting. Revenue source reads
also merge local command projections as `source_kind=command` while keeping
raw-table coverage separate; deleted local projections are filtered out. The
current export has zero rows in every table, so these reads do not seed or
promote source rows.

## Evidence

The native shell smoke covers an authority-checked revenue
create/replay/update/confirm/delete workflow with source-shaped readback. The
trusted gateway smoke covers the same revenue command family through the
session boundary; the broader sales cohort remains a separate projection
rehearsal.

The reviewed synthetic sales cohort contains one customer, converted
subscription, fulfilled agreement, opened receivable, released mortgage, paid
refund, and source-evidence-only revenue row. It produces seven projections;
SQLite/PostgreSQL parity and zero-insert replay report `shadow_verified`. The
temporary cohort is removed after read checks because the available ERP export
has no accepted sales rows.

This is runtime evidence, not production acceptance. Real source rows,
customer/principal identity mapping, collection and tax policy, browser
scenario acceptance, named sales/finance owner sign-off, and production
identity/session deployment remain required.

## Source action reconciliation

The parity matrix now maps the source-equivalent customer create/update,
subscription create/convert, mortgage create/approve/release, refund
create/approve, and revenue create/update/delete/confirm-received actions to
the local command runtime. Revenue commands require authority, idempotency,
and actor/scope matching; they only create local projections and never release
cash or post accounting. The source customer delete action remains gated
because the target deliberately exposes archive rather than destructive
deletion. These command mappings are local evidence only: source identity
mapping, browser acceptance, and sales/finance owner approval remain open.
