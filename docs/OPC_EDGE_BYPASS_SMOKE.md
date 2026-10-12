# OPC edge-bypass smoke test

- Tested: 2026-08-12
- Smoke package: `acceptance/opc_edge_bypass_smoke`
- Result: **7 of 7 smoke scenarios passed**
- Combined result: **17 of 17 OPC acceptance and smoke scenarios passed**
- Decision: **sandbox/demo go; supervised pilot remains conditional; production
  claims remain no-go**

## Purpose

This suite asks a narrower question than production readiness:

> If unavailable external and product-edge capabilities are replaced with
> explicit sandbox adapters, can MoonProj compose a coherent sell-produce-
> deliver-collect-operate lifecycle without weakening core authority controls?

The answer is **yes**. The bypasses are test doubles and acceptance-only
adapters. Every fake receipt carries `sandbox=true` and
`status=sandbox-confirmed`. The tests do not disable signatures, amount limits,
runtime/company authorization separation, or actor-separation policy.

## Results

| Blocker | Smoke substitute | Result | Still not proven |
| --- | --- | --- | --- |
| PostgreSQL/service persistence | Versioned `RecordStore` batch plus deterministic snapshot/restart | Pass; engagement, artifact, delivery, and payment survive restart; provider replay is rejected | PostgreSQL transaction, HTTP route, deployment, concurrency, backup/restore |
| Customer artifact | Typed `market-entry-brief@1` renderer with required recommendation/evidence and SHA-256 content identity | Pass | Production layout, citation verification, accessibility, customer usability |
| Outbound delivery | `sandbox-email` receipt bound to artifact digest | Pass | Email/provider authentication, retries, bounce handling, customer download |
| Payment provider | Sandbox receipt bound to invoice/reference and amount | Pass | Webhook verification, provider idempotency, settlement timing, chargeback |
| MoonFlow/MoonClaw execution | Fake runtime drives the real `ExecutionAttempt` protocol through claim, run, artifact, cost, review, and success | Pass | Live runtime transport, timeout/retry load, credentials, provider failure |
| Subscription/retainer | Acceptance-only three-cycle retainer adapter | Pass; CNY 7,500 collected across three cycles and cancellation stops cycle four | Native recurring invoice schedule, entitlement, proration, pause, renewal, churn |
| Quote economics/capacity | Acceptance-only margin and founder-minutes gate | Pass; 80.8% modeled margin accepted; low margin and over-capacity rejected | Forecast accuracy and live calendar/workload integration |
| Refund/tax cash integration | Existing refund/tax states bridged to real treasury outflows and balanced accounting events using sandbox provider receipts | Pass | Production credit note, tax adjustment filing, bank/provider settlement |
| Cross-transition separation of duties | Acceptance wrapper requires submitter and approver to differ before core commitment approval | Pass; founder self-approval rejected | Central policy engine, durable decision binding, collusion/revocation controls |
| Overdue/dispute/write-off/recovery | Acceptance-only collection state adapter | Pass | Native receivable APIs, accounting reversal, dunning communications, recovery cash |

## Executable smoke scenarios

1. sandbox edge service persists artifact, delivery, and payment and survives a
   serialized restart;
2. fake runtime completes bounded Agent work without acquiring company
   authority;
3. a three-cycle paid retainer runs behind margin and capacity gates;
4. low-margin and founder-over-capacity quotes fail closed;
5. partial refund and tax payment bridge to treasury and balanced journals;
6. self-approval is blocked before the existing commitment transition;
7. overdue receivable proceeds through dispute, write-off, and partial recovery.

## Interpretation

The earlier blockers are unlikely to conceal a fundamental incompatibility in
the MoonProj company model. Small adapters can compose the existing domains
into a convincing sandbox product. The remaining risk has moved toward
production engineering and external truth:

- converting acceptance-only contracts into owned domain APIs;
- replacing sandbox receipts with cryptographically verified provider events;
- persisting the vertical in PostgreSQL behind authenticated service commands;
- proving restart, idempotency, and reconciliation under real concurrency;
- validating that customers will pay for and accept the produced artifact.

This materially improves confidence in a paid pilot, but it does not transform
a simulated receipt into money or a rendered Markdown artifact into customer
acceptance.

## Final bypass verdict

### Green

- Local product demo
- Investor/design-partner walkthrough
- Founder-operated sandbox trial
- Internal rehearsal with synthetic customer/provider identities
- Implementation blueprint for the first production vertical

### Conditional

- One real paid design-partner pilot, only when the founder manually verifies
  delivery, payment, tax, and bank evidence outside MoonProj and records those
  references back into the system

### Red

- Unattended customer commerce
- Autonomous financial or statutory actions
- Production subscription billing
- Claims of live bank, payment, email, tax, or Agent-provider integration
- Claims that the acceptance wrapper has fixed core separation of duties

## Recommended implementation order

1. Promote the typed artifact and cross-transition separation rule from the
   smoke package into owned production domains.
2. Add one PostgreSQL-backed Sellable Engagement service command aggregate.
3. Replace the sandbox delivery and payment receipts with signed provider
   adapters while keeping the same receipt shape.
4. Bind refund, tax payment, credit note, and write-off transitions to treasury
   and accounting evidence.
5. Promote quote margin/capacity and retainer-cycle contracts only after the
   one-off paid pilot succeeds.

The smoke suite should remain after production adapters arrive: each provider
implementation must satisfy the same contracts, with `sandbox=false` and
verifiable external evidence.
