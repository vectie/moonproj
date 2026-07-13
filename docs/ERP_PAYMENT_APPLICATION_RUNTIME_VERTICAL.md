# ERP payment-application runtime vertical

Status: local PostgreSQL/Rabbita slice verified; production acceptance is open.

This slice connects the ERP's `/payment-applies` cost screen to the company
boundary. It preserves the source distinction between an approval/payment
application and cash release: imported source payment flags are displayed as
evidence, while local commands create an auditable requested application and
do not post cash or accounting entries.

## Source evidence

The reviewed PostgreSQL target contains three real `cb_htfk_apply` rows and
three native `payment_application` projections. Two applications are fully
paid and one remains in approval. Each row is joined to its contract, project,
supplier, applicant, payment plan, amount, currency, and dual source/payment
state. The native promotion remains a requested settlement boundary rather
than an implicit cash authorization.

## Connected API

`scripts/company_postgres_service.py` exposes:

- `GET /api/company/payment-applies` with `all`, `approving`, `approved`, and
  `fullpaid` views;
- `GET /api/company/payment-applies/eligibility?plan_id=<id>&amount_minor=<n>`
  for early-payment and over-payment checks against native milestones and
  real payment applications;
- `GET /api/company/payment-applies/<id>` for one application;
- `POST /api/company/payment-applies` to create a local draft;
- `POST /api/company/payment-applies/<id>/{submit,reject,resubmit,approve}`
  for the idempotent local approval lifecycle;
- `POST /api/company/payment-applies/<id>/update` and `/void` for the
  source-aligned edit/void controls on local command-owned applications.

The read-only development adapter exposes the same GET surface. The
loopback-only gateway allow-lists the POST family, establishes its in-memory
HttpOnly session, and signs the actor assertion before the service accepts a
command. Rabbita `/payment-applies` loads live rows, keeps the source-shaped
table, and exposes the local command buttons.

## Acceptance evidence

The local service probe read all three imported rows, checked a real payment
plan for early-payment and over-payment conditions, created a temporary
payment application, replayed the idempotency key, ran submit/update/reject/
resubmit/approve/void, and read the result back. A gateway HTTP probe created
a second temporary application as `rabbita-user`; temporary command
projections, records, and audit rows were removed after verification.

## Remaining gate

Source cost handlers still include edit/void, milestone checks, early-payment
rules, attachments, workflow assignment, and payment execution surfaces that
are not yet connected to Rabbita. Production identity, role-based approval,
persistent sessions, cash/accounting/tax effects, managed deployment, browser
click-through/screenshot acceptance, and named-owner acceptance remain open.
