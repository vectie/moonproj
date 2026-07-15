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

The source-compatible read boundary is now explicit and separate from the
local command projection:

- `GET /api/company/source/cost/payment-applies?view=all` returns all three
  imported applications with source contract/project/supplier/applicant,
  payment-plan, amount, approval, and payment fields.
- The source response reports `cb_htfk_apply=3`, preserves the source shape,
  and marks the read `authorizing=false`, `persisted=false`, and
  `provider_execution=false`. Rabbita `/payment-applies` consumes this source
  read; local create/approval/void commands remain isolated.

## Connected API

The native MoonBit service exposed by `scripts/company_postgres_service.sh`
exposes:

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
- `POST /api/company/source/cost/payment-applies` as a source-field create
  alias; it creates a local draft and immediately submits it so the source
  workflow state is `申请审批中`/`submitted`.
- `PUT /api/company/source/cost/payment-applies/<id>` and `DELETE .../<id>`
  as source-shaped update/void aliases for command-owned applications.
  Imported applications remain read-only.

The native read-only adapter exposes the same GET surface. The native
loopback-only gateway allow-lists the POST family, establishes its in-memory
HttpOnly session, and signs the actor assertion before the service accepts a
command, including the source payment aliases. Rabbita `/payment-applies`
loads live rows, keeps the source-shaped table, and exposes the local command
buttons.

## Acceptance evidence

The shell-only native payment smoke creates a local contract, creates and
replays a source-shaped payment application (auto-submitting it), updates it,
checks imported-row protection, runs reject/resubmit/approve, and voids the
local application. All responses carry explicit no-cash/accounting/tax
markers. The native gateway HTTP smoke repeats source payment creation with a
signed `rabbita-user` assertion.

## Remaining gate

Source cost handlers still include contract/dynamic-cost/milestone mutation,
early-payment execution, attachments, workflow assignment, and payment
execution surfaces that are not yet connected to Rabbita. The source
milestone-check adapter is
connected as a read-only covered boundary, but the current export has no
milestone rows and Rabbita does not invoke the check as a command. The source
read batch is connected, but
production identity, role-based approval,
persistent sessions, cash/accounting/tax effects, managed deployment, browser
click-through/screenshot acceptance, and named-owner acceptance remain open.
