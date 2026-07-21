# Basic OPC UI Acceptance

Recorded: 2026-07-20

## Product boundary

`frontend/opc` is the standalone, industry-neutral Basic OPC browser product.

The current decision-first redesign and its traceability matrix are documented in
`docs/KIMI_OPC_REDESIGN.md`. Acceptance now covers ten Owner-oriented surfaces,
the optional Moon product-line mode, and the retained detailed company-domain
workflows.
It does not import or embed the designer real-estate ERP surface. The latter
remains in `frontend/main` as the UI of the `real-estate-erp` extension pack.

The base interface starts with an unnamed company and zero invented operating
metrics. MoonSuite siblings appear only as optional integration boundaries;
Moonfish investment agents are presented as a native absorption direction.

## Screen map

| Route | Operating responsibility |
|---|---|
| `/overview` | Setup progress, operating circuits, and truthful blank state |
| `/company` | Company identity, owned resources, roles, and rights |
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
| 1440 × 900 | All eight routes render; 13/13 system-map rows become ready; no horizontal overflow |
| 768 × 1024 | System map and responsive shell render without horizontal overflow |
| 375 × 812 | All eight routes render; drawer opens, navigates, and closes |
| 320 × 700 | Finance and guarded-workflow screens remain within the viewport; controls are at least 44px high |

The browser flow exercised all 21 setup boundaries and both lifecycles through
their success paths. It also proved blank-company validation and a rejected
work transition before workflow setup. Controls use explicit button types so
actions do not accidentally submit or reload enclosing forms. Every editable
field is programmatically associated with its visible label and marked
required, and browser role queries resolve each label exactly once.

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
