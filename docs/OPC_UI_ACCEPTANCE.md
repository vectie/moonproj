# Basic OPC UI Acceptance

Recorded: 2026-08-12

## Product boundary

`frontend/opc` is the standalone, industry-neutral Basic OPC browser product.

The current decision-first redesign and its traceability matrix are documented in
`docs/KIMI_OPC_REDESIGN.md`. Acceptance covers 12 primary navigation surfaces,
the optional Moon product-line mode, and six detailed company-domain workflows.
It does not import or embed the designer real-estate ERP surface. The latter
remains in `frontend/main` as the UI of the `real-estate-erp` extension pack.

The base interface starts with an unnamed company and zero invented operating
metrics. MoonSuite siblings appear only as optional integration boundaries;
Moonfish investment agents are presented as a native absorption direction.

## Screen map

| Route | Operating responsibility |
|---|---|
| `/` | Setup progress, operating circuits, and truthful blank state |
| `/fleet` | Read-only Agent-organization layout projection |
| `/dispatch` | Receipt-gated formal task lifecycle |
| `/projects` | Read-only software/hardware stage layout projection |
| `/quality` | Evidence-backed product quality and release rehearsal |
| `/observe` | Read-only SLO and alert layout projection |
| `/operate` | Read-only incident and runbook layout projection |
| `/company` | Company identity, owned resources, roles, and rights |
| `/policy-radar` | Authenticated policy projection and review boundary |
| `/evidence` | Evidence layout plus any real receipt loaded in-session |
| `/guide` | Operating and evidence guidance |
| `/moon` | Optional Moon product-line projection |
| `/market` | Customers, demand, and market evidence |
| `/delivery` | Work, ownership, acceptance, and delivery evidence |
| `/commerce` | Commitments, counterparties, and exchanges |
| `/finance` | Ledger, cash, tax, financing, and investment boundaries |
| `/assurance` | Governance, audit, risk, and continuity |
| `/extensions` | Optional agents, MoonSuite awareness, and extension packs |

The first-session workflow can explicitly create a company profile, customer
signal, work item, commitment, basic ledger, and continuity plan. The broader
system map exposes 21 explicit institutional setup boundaries across every one
of the charter's 13 functional areas. Completing those actions advances initial
setup from 0/6 to 6/6 and system readiness from 0/21 to 21/21.

Two cross-domain lifecycles are executable in the interface:

- work moves through defined → executing → submitted → accepted, and cannot
  start until its workflow boundary exists;
- a commitment moves through draft → approved → signed → performed → settled
  → accounting checkpoint, with company, authority, accepted delivery,
  treasury, and ledger prerequisites checked at the appropriate transitions.

Each creation surface states that the result is local UI-session state, not a
durable PostgreSQL business record. Signing, settlement, and accounting labels
are interface checkpoints only; they do not create a legal signature, move
cash, or post a journal.

## Functional completion matrix

| Charter responsibility | Base UI owner | Interactive boundary |
|---|---|---|
| Identity, constitution, organization, authority, RBAC | Company and rights | Company profile plus constitution and authority registers |
| Resource ownership, custody, budgets, reservations, commitments | Company / Finance | Resource and budget registers |
| Customers, offers, pricing, pipeline, marketing, renewal | Market and customers | Customer signal and offer/renewal register |
| Work, plans, progress, deliverables, acceptance, quality, capacity | Work and delivery | Work record, guarded delivery lifecycle, attention budget |
| Workflow, approvals, thresholds, delegation, duties | Delivery / Assurance | Workflow and control registers |
| Suppliers, procurement, contracts, amendments, milestones | Commerce and exchange | Procurement register and commitment lifecycle |
| Expenses, advances, loans, allocation, reimbursement, repayment | Commerce and exchange | Expense/advance register |
| Invoices, receivables, payables, collections, payments, refunds, settlement | Commerce / Finance | Commitment, treasury, and settlement checkpoints |
| Cash, banking, treasury, financing, contribution economics | Finance and capital | Treasury and financing registers |
| Ledgers, assets, close, statements, consolidation | Finance and capital | Ledger register and accounting checkpoint |
| Tax determination, evidence, filing, payment, reconciliation, risk | Finance and capital | Tax obligation register |
| Investment mandates, scenarios, portfolios, performance, Moonfish agents | Finance / Extensions | Native investment register with no direct trade authority |
| Reports, warnings, controls, audit, learning, continuity, bounded AI | Assurance / Extensions | Control, learning, continuity, and optional-agent boundaries |

## Browser acceptance

The Warren development build was exercised in the in-app browser at these
viewport sizes:

| Viewport | Result |
|---|---|
| 1440 × 900 | All 12 primary pages render; truthful blank overview and company KPIs verified |
| 375 × 812 | Drawer label and `aria-expanded` state update; navigation closes the drawer |
| 320 × 700 | All 12 primary pages render with zero document-level horizontal overflow |

A production-style static bundle was also served without the Warren overlay. It
reported no browser warnings or errors. The Warren-only `MutationObserver`
console error is therefore development-overlay noise, not application code.

The browser flow exercised company creation, customer-signal creation, and the
session-local work lifecycle through defined → executing → submitted →
accepted. It also submitted a complete formal task request without a gateway:
the UI kept the task count at zero and displayed the receipt failure instead of
creating a browser-only success record. Controls have explicit button types,
44px minimum targets, unique accessible setup names, focus styling, truthful
pressed/current/expanded state, a working skip target, and polite result
announcements.

## Current sellability boundary

The UI is smooth enough for onboarding, customer-problem capture, a clearly
marked session-local delivery rehearsal, formal task dispatch, policy review,
and evidence-backed quality rehearsal. It is not yet a complete sellable OPC
product surface:

- Agent, project, monitoring, operations, and most evidence dashboards are
  read-only layout projections; they are now visibly marked as such.
- Durable customer, order, contract, artifact-delivery, invoice, payment, tax,
  and reconciliation lifecycles are not connected end to end in this browser
  product.
- Company onboarding and the generic work/commitment lifecycle still reset on
  reload; only signed gateway responses may claim PostgreSQL durability.
- Policy, engineering, and formal task actions require the authenticated
  MoonProj gateway and their backing services.

## Run and verify

```sh
warren dev frontend/opc --public-dir frontend/opc_public --port 4300
scripts/build_opc_frontend.sh /tmp/moonproj-opc-dist
moon check frontend/opc --target js --warn-list +unnecessary_annotation
moon test frontend/opc --target js
moon build frontend/opc --target js
```

Durable PostgreSQL commands, authenticated company scope, reload persistence,
and operational record reconciliation are the next implementation boundary.
This acceptance record does not claim those runtime effects exist.
