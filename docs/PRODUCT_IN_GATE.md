# Moon Suite Product In-Gate

- Status: active portfolio-admission policy
- Adopted: 2026-08-04
- Owner: Moon Suite product owner

## Purpose

The Product In-Gate answers a question that the engineering release Gates do
not answer: **is there credible evidence that people will adopt this product?**

G1-G9 remain the fixed, candidate-bound engineering and release lifecycle.
They prove that an admitted product is intentional, complete, usable, safe,
operable, and releasable. They do not by themselves prove demand. The Product
In-Gate therefore sits before substantial product engineering and does not
become a new numbered engineering Gate.

```text
demand hypothesis
  -> Product In-Gate
  -> admitted product work
  -> G1-G9 engineering and release evidence
  -> Owner-controlled release
  -> observed adoption and retention review
```

## Value hypothesis

Every proposal must name one primary value type:

- **Solution:** removes a painful, risky, costly, or otherwise important
  problem.
- **Convenience:** makes an existing job meaningfully faster, simpler, or less
  burdensome.
- **Experience:** creates a feeling or experience users cannot obtain as well
  elsewhere.

A product may create more than one type of value, but it must choose a primary
one. This classification sharpens the hypothesis; it is not evidence that the
hypothesis is true.

## Required evidence

An In-Gate packet must identify:

1. **User and buyer:** the narrow initial user segment, the economic buyer when
   different, and how the team can reach them.
2. **Situation:** the trigger, frequency, and concrete job in which the need
   occurs.
3. **Observed problem:** at least three dated, recent problem episodes across
   at least two prospective users or organizations. Opinions about a proposed
   feature do not count as episodes.
4. **Current behavior and cost:** the workaround users employ today and its
   cost in money, time, delay, risk, or frustration.
5. **Commitment:** a behavioral signal such as workflow access, representative
   data, recurring pilot time, a design-partner agreement, a purchase
   commitment, or payment.
6. **Outcome:** one baseline, one target measure, and the observation period
   that would show whether the product delivered value.
7. **Adoption path:** who introduces, approves, configures, and repeatedly uses
   the product in the normal workflow.
8. **Owner and freshness:** a named decision owner, dated receipts, unresolved
   risks, and a review date. Evidence older than 90 days must be refreshed
   unless the packet explains why the underlying behavior has not changed.

Receipts must be consented, minimally identifying, and safe to retain. Store a
redacted observation, transcript excerpt, workflow artifact, pilot agreement,
or payment receipt reference rather than credentials, private production data,
or unsupported summaries.

## Strength of evidence

Evidence is ordered by demonstrated behavior:

1. a user says the idea sounds useful;
2. a user describes a recent instance of the problem;
3. a user already spends effort or money on a workaround;
4. a user commits time, data, access, or a recurring pilot;
5. a user pays, pre-commits, or replaces an existing workflow.

The first level alone never passes the gate. Interviews are evidence of the
problem only when they capture recent behavior; compliments and hypothetical
purchase answers remain weak signals.

## Decisions

The named product owner records one of three decisions:

- **Pass:** all required evidence exists and the packet contains either two
  independent level-4 commitments or one level-5 commitment. Substantial
  implementation may enter the product plan.
- **Experiment:** the user, situation, and problem are credible but commitment
  or adoption evidence is incomplete. Only bounded discovery, prototypes,
  concierge trials, and work required to protect an existing system or honor
  an existing obligation are authorized.
- **Park:** the problem is weak, infrequent, unreachable, already solved well
  enough, or unsupported by commitment. Do not spend product-engineering
  capacity until materially new evidence appears.

A pass is not permanent. Scope changes that introduce a different user, buyer,
job, or primary value hypothesis require a new packet. After release, actual
activation, repeated use, retention, outcome movement, support burden, and
payment replace the original demand hypothesis. Failure to observe adoption
returns the product to `experiment` or `park`; engineering quality cannot
override that decision.

## MoonProj initial decision

- Decision: **experiment**
- Decision date: 2026-08-04
- Refresh by: 2026-11-02

This documented decision is not silently seeded as a runtime fact. The system
remains `unknown` until a signed product owner persists the corresponding
record, preserving actor attribution and the audit trail.

MoonProj has a defined OPC user hypothesis, a working real-site ERP that proves
the real-estate extension contains genuine operating workflows, and an agreed
product direction. It does not yet have a qualifying commitment that proves
the industry-neutral Basic OPC product will be adopted or paid for. Product
direction approval, ERP parity, business acceptance, and passing G1-G9 are not
substitutes for that missing evidence.

| Requirement | Current receipt | Status |
| --- | --- | --- |
| Primary value | Governed company operation removes fragmented control, authority, accounting, and continuity risk; **solution** is primary and convenience is secondary | hypothesis only |
| User and buyer | `PRODUCT_CONTRACT.md` names one-person-company founders and operators, but no narrow initial segment or reachable buyer cohort | incomplete |
| Observed problem | The working real-site ERP proves operating jobs exist for the real-estate extension, but no three dated Basic OPC problem episodes are recorded | missing |
| Current behavior and cost | Existing ERP and manual operating boundaries are documented; their time, money, delay, risk, or frustration cost is not quantified for the initial OPC user | missing |
| Commitment | Product direction is approved, but no external pilot, workflow-access, purchase, or payment commitment is recorded | missing |
| Outcome | The broad success definition exists; no workflow baseline, target, or observation period exists | missing |
| Adoption path | Founders, operators, agents, and named human approvers are identified; introduction, configuration, activation, and repeat-use ownership for one workflow are not | incomplete |
| Decision owner | Moon Suite product owner | present |

Until MoonProj passes the In-Gate:

- preserve the working ERP and complete safety-, migration-, recovery-, and
  existing-obligation work;
- do not use broad module coverage as evidence of demand;
- admit new Basic OPC implementation only when it is part of a bounded demand
  experiment;
- select one paid or commitment-backed OPC workflow before expanding further
  modules.

The next packet must name the initial workflow and user segment, record three
recent problem episodes, quantify the current workaround, obtain the required
commitment, and define the activation and repeat-use measures. The product
owner then records `pass`, `experiment`, or `park` with receipt references.

## System persistence

MoonProj persists the Product In-Gate separately from engineering release
evidence:

- `GET /api/company/products/<product>/in-gate` returns the latest revision or
  an explicit `unknown`, non-persisted projection;
- authenticated `PUT /api/company/products/<product>/in-gate` records a
  `pass`, `experiment`, or `park` decision with its primary value hypothesis,
  segment, repeated workflow, problem and commitment receipt references,
  current behavior and cost, outcome measure, adoption path, unresolved risks,
  next experiment, decision and review dates, and signed owner identity;
- the command writes an immutable `company_command`, a revisioned
  `product_in_gate` aggregate projection, and a `company_audit_event` in one
  PostgreSQL transaction;
- the Idempotency-Key is replay-safe and cannot be reused for a different
  request;
- a `pass` is rejected unless at least three problem receipts and a qualifying
  commitment are present; commitment references use `level4:` or `level5:`
  prefixes, and the service requires either two level-4 receipts or one
  level-5 receipt;
- decision and review dates must be valid ISO dates, with review scheduled no
  later than 90 days after the decision;
- every projection carries `exit_gate_effect=false`. It cannot satisfy,
  renumber, waive, or modify G1-G9.

The Moon Suite UI loads and edits this marking on the product-line page. The
Quality page deliberately does not render it and remains the candidate-bound
Exit Gate console. Persistence and service-restart behavior are covered by
`scripts/company_postgres_product_in_gate_smoke.sh`.
