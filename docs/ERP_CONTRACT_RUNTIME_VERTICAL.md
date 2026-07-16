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

The evidence-ready source boundary is now explicit and separate from the local
command projection:

- `GET /api/company/source/cost/contracts` returns the two imported contracts,
  paid totals, source coverage, and compatibility fields used by Rabbita.
- `GET /api/company/source/cost/contracts/<id>` returns source contract,
  payment-plan, application, and milestone collections; the current export has
  four plans and no `cb_contract_milestone` rows, so milestones stay empty with
  missing-table coverage rather than a fixture fallback.
- `GET /api/company/source/cost/contracts/<id>/milestones` exposes that same
  explicit empty milestone boundary.

Local command-owned contracts can additionally carry milestone projections.
Those are merged into the same source-shaped detail response with
`sourceKind=command`; the empty `cb_contract_milestone` coverage above still
describes imported source evidence and is not replaced by a fixture.

These reads are bounded and non-authorizing (`authorizing=false`,
`persisted=false`, `provider_execution=false`).

## Connected API

The native MoonBit service exposed by `scripts/company_postgres_service.sh`
exposes:

- `GET /api/company/contracts` — latest contract rows with project, supplier,
  amount, paid amount, state, source kind, and milestone count;
- `GET /api/company/contracts/<id>` — one contract plus its imported payment
  milestones;
- `POST /api/company/contracts` — create a draft contract;
- `POST /api/company/source/cost/contracts` — translate the ERP
  `contractCode`/`contractName`/BU/project/provider/amount/CBS field family into
  a command-owned draft contract. The alias preserves `rCode`/`l3Code` and
  source-shaped readback, but does not execute the ERP budget/CBS check or any
  accounting, cash, tax, provider, or signature effect;
- `POST /api/company/contracts/<id>/{submit,reject,resubmit,approve}` — the
  idempotent approval lifecycle, each with an immutable command receipt and
  audit event.
- `PUT /api/company/source/cost/contracts/<id>` and `DELETE .../<id>` —
  source-shaped update/void aliases for command-owned contracts. Imported
  ERP contracts remain read-only; local updates are bounded to draft or
  submitted state and deletion is a local tombstone.
- `POST /api/company/source/cost/contracts/<id>/milestones` — create one or a
  bounded batch of local milestones with source field translation;
- `PUT`/`DELETE /api/company/source/cost/milestones/<id>` — update or tombstone
  command-owned milestones; imported milestone projections remain read-only;
- `POST /api/company/source/cost/milestones/<id>/trigger-event` — reach a
  pending event milestone without emitting cash, accounting, or tax effects.

The loop is forwarded by the loopback-only native MoonBit gateway. The gateway
requires its in-memory HttpOnly session and signs `rabbita-user` before the
service accepts a command. The Rabbita contracts list is wired to load live
rows; the detail route is wired to load live fields and milestones, and the
local “new contract” form is wired for create → submit → reject → resubmit →
approve. The detail route also mirrors the source payment-milestone form and
offers trigger-event/delete actions. These controls deliberately stop at the
PostgreSQL command projection and display the no-payment/no-accounting/no-tax
boundary in the page state.

## Acceptance evidence

The shell-only native contract smoke exercises source-field create with
idempotent replay, source update/readback, all four state transitions, and a
separate source contract void alias with tombstone readback. The native gateway
HTTP smoke repeats source contract create and verifies signed forwarding. The
stored command and audit payloads carry the asserted actor identity.

`scripts/company_postgres_milestone_smoke.sh` exercises the native MoonBit
milestone command family: signed source create/replay, source-shaped detail,
mutable update, pending event trigger, and tombstone readback. It uses
PostgreSQL directly through the shell-launched native service; the legacy
Python service is not part of this supported path.

## Remaining gate

This is a local vertical, not full ERP API parity. Source contract creation now
has a bounded command projection, but CBS/budget enforcement, payment
execution, and external effects remain separate. The payment-application slice
is documented separately in `ERP_PAYMENT_APPLICATION_RUNTIME_VERTICAL.md`. The
fixed demo contract payload and idempotency keys remain local evidence only.
Production identity/token issuance, persistent session and actor claims,
role-based approval, accounting/tax/cash effects, managed deployment, browser
click-through/screenshot acceptance, and named-owner acceptance remain
required.
