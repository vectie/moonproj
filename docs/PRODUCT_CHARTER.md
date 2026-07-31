# MoonProj Basic OPC Product Charter

Status: agreed direction, implementation underway  
Recorded: 2026-07-13  
Working repository: `vectie/moonproj`  
Product name: MoonProj

## Purpose

This document records the product direction agreed during the initial design
discussion. It is a decision record, not a transcript.

The current Moon Suite is strong as a person's workspace. It gives a person or
agent knowledge, memory, conversations, goals, tools, execution, evidence,
scheduling, and operator visibility. A company needs those capabilities, but it
also needs durable institutional identity and an economic existence:

- it owns and controls resources;
- people and agents act on its behalf under delegated authority;
- it enters agreements and incurs obligations;
- it buys, sells, delivers, receives, settles, and disputes;
- it accounts for economic consequences;
- it finances operations and investments;
- it has tax, regulatory, reporting, and governance obligations.

The product will provide that company-wide operating environment.

## Product thesis

Build a standalone, industry-neutral OPC operating system, strengthened by
explicit models for institutional
identity, authority, ownership, obligations, accounting, treasury, financing,
tax, and investment. Preserve the functional breadth of the existing production
ERP as the acceptance floor of the real-estate extension pack.

The product must support the complete business cycle:

```text
organize the company
  -> allocate authority and resources
  -> plan and finance activity
  -> buy, sell, contract, and deliver
  -> recognize obligations and economic events
  -> invoice, pay, collect, and reconcile
  -> account, tax, report, control, and audit
  -> invest capital and evaluate outcomes
```

The basic OPC profile is the default product. The existing ERP is the minimum
capability baseline for its extension. A narrow workflow or accounting kernel
is neither a complete OPC product nor real-estate extension parity.

## Agreed decisions

### D0. The default product is a general OPC operating system

The product models the functions a company still needs when one accountable
person holds several roles: principal, market, delivery, control, learning, and
continuity. It maintains economic, operating, and governance circuits without
assuming a real-estate company, construction project, CBS hierarchy, property
reservation, or mortgage process.

Industry behavior is delivered through explicit extension packs. The core may
not depend on an extension.

### D1. This is a separate product

The product is not a new layer inside Moon Suite and is not a feature of
Moontown, MoonBook, MoonFlow, or Moondesk. It owns its identity, data model,
database, UI, API, authorization, workflows, audit trail, and release lifecycle.

It may be Moon Suite-aware, but Moon Suite is not required for normal company
operations.

### D2. Broad ERP capability is a real-estate extension release requirement

The supplied ERP works at a real site and demonstrates the required operational
breadth of the `real-estate-erp` extension. Its business capabilities,
workflows, reports, controls, and user journeys form that extension's parity
floor and may not be dropped during the product pivot.

Internal implementation milestones may be narrow. The declared product scope
and production replacement gate are broad.

### D3. The company model is locally authoritative

The product owns:

- legal entities, business units, departments, projects, and counterparties;
- users, positions, roles, data scope, and delegated authority;
- resources, custody, ownership, budgets, and reservations;
- commitments, contracts, orders, delivery, acceptance, and settlement;
- receivables, payables, journals, treasury, financing, and tax;
- operational workflow, internal control, evidence, and audit;
- investment mandates, proposals, positions, valuation, and performance.

No external agent runtime may bypass these rules or become the system of record.

### D4. Integration stays deliberately shallow

The initial product has no required runtime dependency on MoonBook, MoonFlow,
Moontown, Moondesk, MoonChat, MoonGate, or MoonLib.

Future adapters may be added only when a concrete use case justifies them. An
adapter's absence may reduce automation or convenience, but cannot prevent core
business operation or access to institutional records.

### D5. MoonClaw is an optional agent executor

The product defines a local agent port. MoonClaw may implement that port for
bounded research, extraction, reconciliation assistance, anomaly analysis,
contract review, and proposal preparation.

MoonClaw results are advisory or proposed commands. Every mutation is validated
again by local authority, workflow, budget, accounting, tax, and control rules.
An agent may not directly post a journal, release payment, execute an investment,
or approve its own proposal.

### D6. Moonfish is absorbed into the investment domain

Moonfish is the one planned product absorption rather than an optional adapter.
Its reusable investment capabilities become native packages:

- market evidence and data readiness;
- deterministic analytics and indicators;
- strategy routing and validation;
- risk and safety policies;
- research and investment agents;
- replay, review, comparison, and evidence.

Legacy migration, parity, rollback, and decommission artifacts remain archived
as migration evidence. They do not define the permanent package architecture.

### D7. Start as one product and one repository

Organization, operations, finance, accounting, tax, investment, reporting, and
intelligence are internal bounded contexts, not separate products or repositories
at the outset.

Package boundaries should follow public type ownership. Concrete public domain
types belong to the package users name; `internal/*` packages are limited to
implementation helpers.

### D8. Do not rewrite the current ERP in place

The existing ERP remains operational during development and migration. The new
product is built beside it, verified through repeatable parity scenarios, run in
shadow mode, and cut over only after reconciliation and rollback gates pass.

## Functional scope

The basic OPC product covers all of the following as one coherent system:

1. Corporate identity, organization, parties, users, roles, authority, and RBAC.
2. Resource ownership, custody, budgets, reservations, and commitments.
3. Customers, offers, pricing, pipeline, marketing, sales, renewal, and counterparties.
4. Work portfolios, delivery plans, progress, deliverables, acceptance, quality, and capacity.
5. Configurable workflow, approvals, thresholds, delegation, and segregation of duties.
6. Suppliers, sourcing, procurement, contracts, amendments, and milestones.
7. Expenses, employee advances, loans, allocation, reimbursement, and repayment.
8. Invoices, receivables, payables, collections, payments, refunds, and settlement.
9. Cash, banking, treasury, financing, and customer/contribution economics.
10. General and subsidiary ledgers, assets, period close, statements, and consolidation.
11. Tax determination, evidence, filings, payments, reconciliation, and tax risk.
12. Investment planning, mandates, scenarios, portfolios, performance, and absorbed Moonfish agents.
13. Reports, scorecards, warnings, controls, audit, learning, continuity, and bounded AI assistance.

The real-estate extension additionally owns development lifecycles, CBS and
target/dynamic cost, construction tendering, property inventory, reservation,
mortgage, engineering progress, and the unchanged designer UI journeys. Its
complete acceptance inventory remains in `ERP_CAPABILITY_BASELINE.md`.

The detailed parity floor is maintained in
[ERP_CAPABILITY_BASELINE.md](ERP_CAPABILITY_BASELINE.md).

The sibling ownership and reuse boundary is maintained in
[MOON_SUITE_BOUNDARY.md](MOON_SUITE_BOUNDARY.md).

## Architectural invariants

These invariants apply even during early implementation:

1. Every business record belongs to an institutional principal.
2. Actor identity and represented principal are separate fields.
3. Authority is explicit, scoped, effective-dated, delegable, and revocable.
4. Money is fixed-point or decimal-safe; binary floating-point is not used for postings.
5. Business state changes produce immutable audit events.
6. Operational completion, approval, contractual performance, settlement, and accounting recognition are distinct states.
7. Posted journals are immutable and balanced; corrections use reversing or adjusting entries.
8. One system owns a record at any point during migration; uncontrolled dual writes are forbidden.
9. Agent output is untrusted input until locally validated and accepted.
10. External integrations use explicit versioned ports and adapters.
11. Attachments and evidence have provenance, integrity metadata, retention, and access control.
12. Every production cutover capability has a tested rollback path.

## Conceptual architecture

```text
application and API
  |
  +-- foundation
  |     entity, organization, party, identity, authority, workflow, evidence
  |
  +-- operations
  |     project, sales, marketing, procurement, supplier, contract, delivery, expense
  |
  +-- finance
  |     budget, cost, accounting, receivable, payable, treasury, financing, tax
  |
  +-- investment
  |     planning, portfolio, analytics, risk, agents, absorbed Moonfish capabilities
  |
  +-- intelligence
  |     warnings, forecasting, reporting, controls, agent port
  |
  +-- adapters
        MoonClaw initially; other Moon Suite adapters only when justified
```

The likely MoonBit layout is documented as a target, not a requirement to create
all packages before their behavior exists. Packages should be introduced with
their first cohesive vertical capability.

## Non-goals for the initial program

- Deep integration with every Moon Suite product.
- Reusing Moon Suite workspace paths as the company's persistence model.
- Allowing agents to become authoritative business actors without local grants.
- A big-bang replacement of the working ERP.
- Mechanical one-to-one translation of every existing table or endpoint.
- Splitting the product into many repositories before boundaries are proven.
- Declaring success after an attractive narrow prototype.

## Success definition

The product succeeds when a real company can use it to organize itself, control
authority, run projects, buy and sell, manage resources and contracts, account
for economic activity, finance operations, satisfy tax obligations, invest
capital, and understand its condition without requiring the old ERP to complete
the lifecycle.

## Open decisions

These remain intentionally unresolved:

- final public subtitle and Chinese product name;
- production deployment topology;
- whether a future desktop/mobile surface reuses the browser contracts;
- jurisdiction and accounting-standard priorities;
- first production business unit and migration cohort;
- whether the current ERP receives a small read-only export API or migration
  extracts operate directly against a replica;
- calendar estimates, which require team size and availability.

Resolving these should not reopen the agreed product boundary.
