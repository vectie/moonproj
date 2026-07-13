# ERP contract runtime vertical

Status: local PostgreSQL/Rabbita slice verified; production acceptance is open.

This slice connects the designer-built contract surfaces to the company
boundary without replacing the working ERP. It covers the source contract
list/detail routes (`/contracts` and `/contracts/:guid`) and keeps payment
milestones visible as read evidence.

## Source evidence

The reviewed PostgreSQL target currently contains two real `cb_contract` rows,
four `cb_htfkplan` payment milestones, and three `cb_htfk_apply` payment
applications. The target also contains native `commitment` and
`contract_milestone` projections. The read API joins those projections to the
credential-safe raw contract/project rows and exposes paid totals without
releasing cash or posting accounting entries.

## Connected API

`scripts/company_postgres_service.py` exposes:

- `GET /api/company/contracts` — latest contract rows with project, supplier,
  amount, paid amount, state, source kind, and milestone count;
- `GET /api/company/contracts/<id>` — one contract plus its imported payment
  milestones;
- `POST /api/company/contracts` — create a draft contract;
- `POST /api/company/contracts/<id>/{submit,reject,resubmit,approve}` — the
  idempotent approval lifecycle, each with an immutable command receipt and
  audit event.

The loop is forwarded by the loopback-only development gateway. The gateway
requires its in-memory HttpOnly session and signs `rabbita-user` before the
service accepts a command. The Rabbita contracts list is wired to load live
rows; the detail route is wired to load live fields and milestones, and the
local “new contract” form is wired for create → submit → reject → resubmit →
approve.

## Acceptance evidence

The service smoke now exercises contract create, idempotent replay, all four
state transitions, and detail readback. A gateway HTTP probe also verified that
the stored command and audit payloads carry `actor_id: rabbita-user`; probe rows
were deleted after verification.

## Remaining gate

This is a local vertical, not full ERP API parity. The source cost module still
has additional contract, payment-application, milestone, and mutation handlers
that are not connected here; the payment-application slice is documented
separately in `ERP_PAYMENT_APPLICATION_RUNTIME_VERTICAL.md`. The fixed demo contract payload and idempotency
keys remain local evidence only. Production identity/token issuance, persistent
session and actor claims, role-based approval, accounting/tax/cash effects,
managed deployment, browser click-through/screenshot acceptance, and named-owner
acceptance remain required.
