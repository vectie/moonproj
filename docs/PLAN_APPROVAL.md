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
