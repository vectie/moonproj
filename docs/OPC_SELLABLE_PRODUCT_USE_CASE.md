# OPC sellable-product use-case test

- Tested: 2026-08-12
- Offering: **Market Entry Decision Brief**
- Price: CNY 2,500.00 (`250000` minor units)
- Execution model: founder-led, four bounded Agent roles
- Test package: `acceptance/opc_sellable_product`
- Result: 2 tests passed

## Question

Can MoonProj, acting as the operating system of a one-person company, produce
and sell a real customer product rather than merely coordinate tasks?

## Scenario

The tested OPC is a small market-intelligence studio. A customer orders a
fixed-price decision brief through a signed webhook. The company accepts a
commercial commitment, decomposes production into four roles, and runs each
role through the versioned execution-attempt protocol:

1. engagement lead frames the decision and exclusions;
2. researcher produces evidence-linked market research;
3. producer creates the customer brief;
4. an independent reviewer checks claims and the recommendation.

The modeled execution cost is CNY 440.00 against CNY 2,500.00 revenue, giving
CNY 2,060.00 modeled contribution and an 82.4% contribution margin before
founder time, tax, payment fees, and overhead.

After production, a second signed customer message accepts the deliverable.
MoonProj then separately authorizes delivery acceptance, commitment
performance, invoice creation and issue, receivable recognition, accounting
links, cash collection, invoice payment, and commitment settlement. The first
accepted workflow qualifies as adoption evidence.

The adversarial test also proves that runtime permission and the shadow
workflow's invoice proposal cannot create an invoice. A fresh company-authority
grant is required.

## Evidence matrix

| Capability | Result | Evidence |
| --- | --- | --- |
| Verified customer order | Pass | HMAC signature, customer binding, timestamp, nonce, replay registry |
| Commercial commitment | Pass | Create, submit, and independent approval with scoped grants |
| Multi-Agent production | Pass | Four dependency-ordered requests and claimed execution attempts |
| Cost visibility | Pass | Per-attempt execution costs and positive modeled contribution |
| Independent quality review | Pass | Reviewer is distinct from owner and producer |
| Customer acceptance | Pass | Second signed, replay-checked customer receipt |
| Delivery governance | Pass | Planned, submitted, and accepted deliverable with evidence |
| Invoice and receivable | Pass | Separate grants for invoice, issue, acceptance, and receivable opening |
| Accounting linkage | Pass | Balanced receivable/revenue and cash/receivable event pairs |
| Collection and settlement | Pass | Receivable collected, invoice paid, commitment settled |
| Authorization-plane separation | Pass | Runtime-only grant is rejected by invoice creation |
| PostgreSQL persistence of this workflow | **Not implemented** | Professional-service and customer-channel objects are currently library state |
| Live service API for this workflow | **Not implemented** | No professional-service/customer-channel command routes reference these types |
| Customer-facing product artifact | **Not proven** | Test uses evidence references; there is no typed brief document renderer or content validator |
| Outbound delivery channel | **Not implemented** | The verified webhook is deliberately inbound-only |
| Real payment rail | **Not proven** | Collection is a governed domain transition, not a bank/provider receipt |
| Live MoonFlow/MoonClaw execution | **Not proven here** | Attempts are executed deterministically inside the acceptance test |

## Verdict

**MoonProj can model and govern the complete economics and authority chain of a
sellable professional-service product, but it cannot yet honestly claim a real,
autonomous sale in production.**

The domain kernel passes the hard structural test: demand can become bounded
work, reviewed delivery, revenue, receivable, cash, accounting evidence, and
learning without collapsing runtime permission into company authority. That is
the distinctive OPC value.

The current limiting factor is productization at the edges, not the company
model. The professional-service aggregate, verified customer channel, and
execution projection are not yet connected to PostgreSQL service commands.
The “brief” is represented by evidence identities rather than a validated
customer artifact, and neither outbound delivery nor real payment confirmation
is connected.

Therefore the readiness decision is:

- **Pass** for an in-memory, human-supervised vertical product proof;
- **Pass** for validating MoonProj's top-down OPC architecture;
- **Fail closed** for claiming unattended production commerce today.

## Smallest production experiment

The next Product In-Gate experiment should sell this exact offering to one
design partner, without adding staffing or marketplace autonomy. Implement only
the missing vertical slice:

1. persist the engagement, work attempts, customer receipts, and attention
   items in PostgreSQL;
2. add typed `market-entry-brief@1` content and acceptance validation;
3. dispatch the four work contracts through the real MoonFlow/MoonClaw seam;
4. add signed outbound artifact delivery and signed customer acceptance;
5. reconcile one real payment-provider or bank receipt before collection;
6. display the live engagement, attention, margin, invoice, and cash states in
   the cockpit.

Success means one external customer pays for and accepts the artifact, every
transition is replayable from the three ledgers, and founder intervention time
is measured. Only then should the workflow count as commercially adopted.

