# OPC commercial portfolio use-case results

- Tested: 2026-08-12
- Native executable scenarios: **10 passed out of 10**
- New portfolio scenarios: **8 passed out of 8**
- Decision: **conditional go for a founder-operated paid pilot; no-go for
  unattended production commerce**

## What “passed” means

An executable scenario passes when the current public MoonProj domain APIs
produce the expected state and reject the tested invalid actions. Passing a
characterization test does not make every observed behavior commercially
acceptable. In particular, one passing test deliberately proves that separate
authority grants can still be issued to the same founder for submission and
approval. That observation is a red launch gate.

These are in-memory native tests. They do not claim that PostgreSQL routes,
external providers, or a customer-facing artifact were exercised.

## Portfolio results

| # | Commercial use case | Executable result | Business result |
| --- | --- | --- | --- |
| 1 | CNY 2,500 market-entry brief from signed order through collected cash | Pass | 82.4% modeled contribution before founder time, tax, fees, and overhead |
| 2 | Runtime agent attempts to turn an inert invoice proposal into a real invoice | Rejected as expected | Company authority remains separate from runtime permission |
| 3 | Ten acquired leads produce two completed CNY 2,500 sales cycles | Pass | 80.0% modeled contribution after CNY 880 delivery cost and CNY 120 acquisition cost |
| 4 | CNY 5,000 brand kit with a qualified CNY 1,200 external supplier | Pass | 76.0% gross contribution before founder time, tax, fees, and overhead |
| 5 | CNY 500 partial refund against a CNY 2,500 sale | Pass; CNY 2,500.01 over-refund rejected | Refund amount and approval are bounded, but refund cash/accounting integration is absent |
| 6 | Customer cancels after reservation | Pass; receivable creation rejected | Cancelled demand does not become phantom revenue |
| 7 | Two sales create 6% tax, 1% withholding, reviewed filing, and accounting evidence | Pass | Tax calculation and filing state are governed, but “paid” is not bound to a treasury movement |
| 8 | CNY 2,500 receipt reaches receivable, treasury, bank statement, and journal match | Pass | Strongest cash-evidence result; still uses an imported test statement rather than a live bank feed |
| 9 | Replay, modified signature, stale order, and wrong customer identity | All rejected | Inbound signed-webhook boundary fails closed |
| 10 | CNY 1,200 payable with only CNY 1,000 authority; founder submits and approves own commitment | Payable rejected; self-approval succeeds | Amount caps work; actor separation is not intrinsic and is a red gate |

All monetary values above use minor units in code and are rendered here as CNY.

## What MoonProj now proves

MoonProj has a coherent company kernel for a small professional-services OPC:

- verified inbound demand can become a scoped sale or commitment;
- work can be decomposed among bounded Agent roles and independently reviewed;
- marketing cost, execution cost, supplier cost, budget, revenue, receivable,
  payable, tax, cash, and accounting evidence can be kept distinct;
- partial collections and partial supplier payments preserve outstanding state;
- cancellation, refund limits, signature attacks, replay, identity mismatch,
  scope, capability, and amount limits fail closed;
- a customer receipt can be reconciled from a bank statement line to a
  treasury movement and source-to-journal accounting event.

That combination is enough to support a manually supervised paid design-partner
trial. It is materially stronger than a task orchestrator: the company—not the
Agent runtime—owns the commercial state and authority.

## Launch gates that failed

### 1. No production professional-service vertical

`ProfessionalServiceShadow` and `VerifiedWebhookChannel` are referenced by
their libraries and acceptance tests, not by the PostgreSQL company service.
The service cannot yet receive, persist, resume, or expose this engagement.

### 2. No real customer artifact or outbound delivery

The tested brief is a set of evidence identities. There is no typed
`market-entry-brief@1` content model, renderer, claim validator, signed outbound
delivery, or customer download/acceptance experience.

### 3. No general subscription or retainer

The only `SubscriptionState` belongs to the inherited property `Reservation`
shape and requires a `unit_reference`. The two-cycle revenue test proves manual
repeatability, not cadence, renewal, entitlement, proration, recurring billing,
or churn handling.

### 4. Self-approval is possible

Authority checks validate principal, actor, capability, scope, amount, and
active status independently for each transition. They do not compare actors
across a workflow. If grants are issued to the same founder, the founder can
submit and approve the same commitment. Independent-review conventions are not
an enforcement mechanism.

### 5. Incomplete failure and adjustment accounting

Refund state is not connected to a credit note, revenue reversal, tax
adjustment, payable, treasury outflow, or bank reconciliation. Receivable has a
`WrittenOff` state but no public write-off transition; there is no general due
date, dunning, dispute, chargeback, bad-debt, or recovery workflow.

### 6. Commercial controls are not composed

The system can calculate margin in a test, but it does not bind a quoted sale
to its cost forecast, capacity, minimum margin, tax treatment, or approval
threshold. Marketing placement records leads, but no attribution identity links
a lead to a customer or sale.

### 7. External execution remains simulated

The scenarios do not execute real MoonFlow/MoonClaw work, a payment provider, a
bank API, tax-authority submission, email/customer portal, or provider-backed
signature delivery. Imported evidence proves reconciliation logic, not provider
operation.

## Final commercial decision

### Conditional go

MoonProj can be used behind one founder to sell one tightly scoped,
fixed-price, high-margin professional-service product to one design partner,
provided that the founder manually controls contracting, final artifact review,
delivery, payment confirmation, and statutory filing.

The best first offer remains the **Market Entry Decision Brief**. It has fewer
external dependencies than the supplier-backed brand kit, and its modeled
82.4% contribution leaves the most room for currently unmeasured founder time
and overhead.

### No-go

MoonProj should not yet be marketed as an autonomous OPC, unattended commerce
system, recurring-revenue platform, or production system of record for a real
customer. A green domain test cannot substitute for live persistence, real
artifacts, provider receipts, enforced separation of duties, and operational
recovery.

## Product ideas produced by the tests

### P0 — Sellable Engagement vertical

Build one service-owned PostgreSQL aggregate joining customer receipt,
commercial agreement, work attempts, typed artifact, review, delivery,
invoice, receivable, bank receipt, margin, and founder-intervention evidence.
Expose only the commands required for the decision-brief pilot.

### P0 — Cross-transition separation-of-duties policy

Add a workflow policy that can require `requested_by != reviewed_by`, bind both
decisions to the same aggregate revision, and reject self-issued or colluding
grant chains. Apply it to commitment approval, tender award, refunds, cash
release, tax review, and artifact acceptance.

### P0 — Adjustment and collection pack

Add invoice due dates, collection attempts, disputes, credit notes, revenue/tax
reversals, receivable write-off, refund treasury movement, and bank
reconciliation. This makes “customer does not pay” and “we must give money
back” first-class company cases.

### P1 — Productized retainer

Create a domain-neutral subscription with offer/version, billing cadence,
renewal policy, service entitlement, usage/delivery cycle, proration, pause,
cancel, churn reason, and invoice schedule. Do not reuse the property
reservation model.

### P1 — Quote profitability and capacity gate

Before a sale can be signed, bind the quote to execution forecast, supplier
commitments, tax estimate, acquisition attribution, founder-capacity estimate,
minimum contribution, and an override approval when the threshold is missed.

### P1 — Evidence-backed customer portal

Give the customer a signed order, artifact version, acceptance/rejection,
invoice, payment, refund, and support timeline. This is the smallest visible
product surface that turns the internal company kernel into something a buyer
can trust.

## Next acceptance gate

The next test must not be another in-memory simulation. It should use one real
design partner and require all of the following:

1. a persisted signed order received by the production service;
2. a rendered and independently reviewed customer artifact;
3. signed outbound delivery and customer acceptance;
4. a real payment or bank receipt reconciled to receivable and journal;
5. a policy-enforced independent commercial review;
6. measured founder minutes, delivery cost, acquisition cost, tax estimate,
   refund exposure, and final contribution;
7. restart and replay of the engagement without manual database repair.

Passing that gate would justify the statement “MoonProj helped an OPC produce
and sell a real product.” The present result justifies the narrower statement:
“MoonProj's company kernel can govern the complete simulated lifecycle of a
sellable product and is ready for a supervised paid pilot.”
