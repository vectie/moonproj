# Product and Migration Plan Approval

Recorded: 2026-07-13  
Decision source: user conversation

The user approved the documented standalone company-product direction and the
ERP-to-company-product migration plan.

This approval covers:

- the standalone company product boundary;
- shallow, optional Moon Suite integration;
- optional MoonClaw agent execution;
- native absorption of Moonfish investment capabilities;
- ERP breadth as the replacement floor;
- capability-oriented strangler migration with one authoritative writer;
- the documented parity, accounting, source-export, acceptance, shadow, and
  rollback controls.

It does **not** authorize:

- production database provisioning;
- importing credentials or secrets;
- changing the working ERP;
- production accounting posting or cash release;
- shadow-period execution;
- ownership transfer or cutover.

Those actions still require the complete source export, named business,
finance, operations, and security decisions, and the gates described in
`BUSINESS_ACCEPTANCE_PACKET.md`, `SHADOW_PERIOD_CONTRACT.md`, and
`PRODUCTION_DEPLOYMENT_GATE.md`.

## Plan amendment (2026-07-15)

The implementation-language boundary is now explicit: the company product
must use pure MoonBit plus shell orchestration. Existing Python migration and
PostgreSQL bridge scripts are transitional evidence only; they must be ported
to MoonBit, shadow-compared, and removed from supported build/deployment paths.

## Plan amendment (2026-08-04)

The user approved an upstream Product In-Gate that tests whether a product will
actually be adopted before substantial engineering. The gate requires a named
user and buyer, a primary solution/convenience/experience hypothesis, recent
problem behavior, a quantified workaround, behavioral commitment, a measurable
outcome, and a credible adoption path.

This amendment does not renumber or weaken engineering Gates G1-G9. MoonProj's
initial Basic OPC decision is `experiment`, not `pass`: bounded discovery and
work needed for ERP preservation, migration safety, recovery, or existing
obligations remain authorized, while broad new module expansion waits for a
commitment-backed initial workflow. The complete policy and execution packet
are in `PRODUCT_IN_GATE.md`.
