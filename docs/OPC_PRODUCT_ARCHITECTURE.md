# MoonProj Basic OPC Product Architecture

Status: adopted product direction; migration in progress

Recorded: 2026-07-20

Primary management input: `China_OPC_Management_Operating_System_Condensed_Report.docx`

MoonSuite catalog input: `/Users/kq/Workspace/vectie.github.io`

## Decision

MoonProj targets the basic operating needs of a general One-Person Company.
It is not a real-estate product with generic labels, and it is not a personal
workspace with accounting attached.

The company is the principal. It owns resources and records, grants bounded
authority to people and agents, makes commitments, conducts exchanges, keeps
accounts, finances activity, handles tax, learns, and remains recoverable when
the founder or an automation provider is unavailable.

The working `erp_new` real-estate implementation remains valuable and must not
be discarded. It becomes the first vertical extension pack and the broadest
migration acceptance source.

## What the OPC report changes

The report's central rule is **compress headcount, not organizational
functions**. An OPC still needs six systems:

1. **Accountable principal** — purpose, charter, risk appetite, capital, and
   reserved decisions.
2. **Market system** — customer discovery, offer, pricing, pipeline, sales, and
   customer success.
3. **Delivery system** — scope, work, capacity, acceptance, quality, and change
   control.
4. **Control system** — authority, contracts, cash, data, commitments,
   reconciliation, and incidents.
5. **Learning system** — metrics, experiments, postmortems, reusable procedures,
   and invalidated assumptions.
6. **Continuity system** — operating record, dependency register, backup,
   restore, trustee access, and safe degraded mode.

Those systems support three circuits that must be measured separately:

| Circuit | Flow | MoonProj responsibility |
|---|---|---|
| Economic | problem → offer → delivery → cash → renewal | Customers, offers, commitments, exchange, margin, collection, and investment outcome |
| Operating | orient → plan → execute → assure → learn → revise | Work portfolio, workflow, delivery, acceptance, evidence, and procedure learning |
| Governance | authorize → monitor → intervene → reconcile → account | Principal, rights, budgets, controls, ledger, tax, audit, incidents, and continuity |

Automation is not a fourth circuit. It serves all three and may never hide a
weak customer, cash, acceptance, or authority model.

## Product layers

```text
MoonProj Basic OPC (default product)
  ├─ company constitution and accountable principal
  ├─ organization, parties, resources, rights, and delegations
  ├─ customer, offer, pipeline, sales, and renewal
  ├─ work portfolio, workflow, delivery, quality, and acceptance
  ├─ commitments, contracts, procurement, invoices, and exchange
  ├─ budget, accounting, receivable, payable, treasury, financing, and tax
  ├─ native investment domain with absorbed Moonfish capabilities
  ├─ evidence, audit, risk, learning, scorecards, and founder-attention budget
  └─ continuity, restore, trustee mode, and dependency controls

Optional ports (awareness, not ownership)
  ├─ MoonClaw: bounded agent execution and proposal receipts
  ├─ MoonBook: approved knowledge/evidence projection
  ├─ MoonFlow: recoverable work receipts
  ├─ Moontown: recurring observation and scheduling
  ├─ MoonDesk: optional operator surface
  └─ MoonGate: provider access, cost, health, and telemetry

Extension packs
  └─ real-estate-erp
       ├─ development project lifecycle
       ├─ development CBS, target cost, and dynamic cost
       ├─ construction tendering and engineering progress
       └─ property inventory, subscription, mortgage, and handover flows
```

The dependency direction is one way: an extension depends on the OPC product
contract; the OPC core never imports a vertical pack. MoonSuite siblings expose
optional ports; no sibling owns company identity, authority, money, contracts,
tax, journals, or investment positions.

## Core capability contract

The executable catalog lives in `product` and `product/opc`. Stable capability
IDs are the product compatibility boundary. The initial profile covers:

- company identity, constitution, organization, and authority;
- resources, parties, customers, offers, pipeline, and work portfolio;
- delivery, acceptance, commitments, contracts, procurement, and exchange;
- budget, accounting, receivables, payables, treasury, financing, and tax;
- investment mandates, proposals, positions, valuation, and performance;
- evidence, risk, learning, continuity, trustee mode, agents, and scorecards.

The default profile intentionally contains no `real_estate.*` capability.

## Real-estate extension contract

`extensions/real_estate` owns the vertical manifest. Existing ERP UI routes,
source schemas, translations, fixtures, and parity ledgers are retained as
extension evidence until they are physically relocated. Their current location
does not make them generic core.

The designer-built Rabbita UI remains the visual authority for this extension.
Moving it is a packaging change, not an opportunity to redesign or simplify it.
Shared company screens may later be extracted only after their generic data and
authority contracts are proven.

## MoonSuite relationship

MoonProj is independently operable. It is aware of the public MoonSuite product
seams described by the Vectie catalog:

- MoonBook owns durable knowledge;
- MoonClaw owns agent execution;
- MoonFlow owns declared-work progression and recovery;
- Moontown owns standing orchestration;
- MoonDesk owns the optional human workspace shell;
- MoonGate owns model access, usage, health, and telemetry;
- physical and world-model products remain outside the company core.

Moonfish is the exception. Its deterministic market evidence, analytics,
strategy validation, risk, replay, and investment-agent behavior are absorbed
into MoonProj's native investment packages. A Moonfish result never bypasses a
mandate, approval, accounting, cash, tax, or risk gate.

## Product maturity and operating gates

The report's topology becomes the release sequence:

| Gate | Product outcome | Exit evidence |
|---|---|---|
| P0 Safe operation | Principal, reserved matters, rights, data and payment controls, incident and trustee paths | Every material action has an owner, authority, record, and stop path |
| P1 Demand proof | Customer, paid problem, offer, value measure, buyer, and next-purchase condition | At least one paid use case has acceptance and a follow-on decision |
| P2 Repeatable delivery | Standard work, acceptance, change control, capacity, and partner boundaries | A second delivery reuses the core process without proportional founder effort |
| P3 Economics and control | Margin, cash forecast, approval limits, close, concentration, and model cost | Standard work is cash-positive or has an explicit funded path |
| P4 Resilience and learning | Operating record, restore, trustee, incident drill, postmortem, procedure promotion/invalidation | The company can stop, restore, and continue safely |
| P5 Governed scale | Read-first integrations, bounded agents, partner scorecards, and portfolio governance | Growth does not degrade value, margin, control, or founder attention |

These gates apply to the generic product and each extension. ERP screen count
alone does not satisfy them, but ERP breadth remains mandatory for the
real-estate pack.

## Immediate migration sequence

1. Keep the current production ERP authoritative and preserve all existing
   route/data parity evidence.
2. Make `opc-basic` the default product profile and treat extension activation
   as explicit configuration.
3. Build a general OPC cockpit around customer, cash, commitments, exceptions,
   owner attention, and continuity—not around development projects.
4. Classify existing packages and routes as generic core, reusable service, or
   `real-estate-erp`; do not mass-move code before classification tests exist.
5. Move the unchanged designer UI behind the real-estate extension entry point,
   then extract only proven generic screens.
6. Continue feature porting against the ERP parity matrix inside the extension
   workstream while completing missing generic OPC systems in parallel.
7. Absorb Moonfish package by package using fixed market fixtures and archive
   its runtime only after output and control parity pass.

## Non-negotiable acceptance rules

- Pure MoonBit plus shell orchestration; PostgreSQL is the target database.
- No required MoonSuite runtime dependency for ordinary operation or recovery.
- No industry-specific capability in the default OPC profile.
- No reduction of the real-estate ERP's documented breadth.
- No agent self-authorization or direct posting/payment/trade authority.
- No production cutover without source reconciliation, owner acceptance,
  backup/restore proof, and rollback.
