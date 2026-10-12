# ADR: top-down company execution, two authorization planes, and three ledgers

- Status: adopted
- Recorded: 2026-08-12
- Decision owner: MoonProj product owner
- Protocol: `moonproj.agent-execution.v1`
- Applies to: Basic OPC, MoonClaw/MoonFlow adapters, MoonTown observations,
  customer channels, learning, and extension packs

## Context

MoonProj owns company identity, authority, commitments, delivery acceptance,
accounting, cash, tax, evidence, and continuity. It needs several Agents to
work together as a one-person company's delegated operating organization,
without turning an Agent runtime into the company or creating a second source
of business truth.

Three neighboring coordination models are useful but different:

| Product/model | Direction | Unit of coordination | What it owns |
| --- | --- | --- | --- |
| MoonProj OPC | top down | accountable company objective and bounded work contracts | principal, authority, business state, acceptance, and effects |
| MoonFlow | declared sequence | one recoverable workflow/attempt | progression, artifact claim, reconciliation, and recovery for that workflow |
| MoonTown | bottom up | standing goals, observations, and multiple emerging workers | recurring observation, scheduling, discovery, and proposals |

OpenOPC demonstrates useful execution mechanics: a work-item dependency graph,
role sessions, claims, peer waits, review/rework, crash recovery, attempt
streaks, activity projections, channels, and outcome-attributed learning. The
decision is to absorb those invariants behind MoonProj's product-owned port,
not to import OpenOPC's Python runtime, organization identity, generic metadata
store, or tool approval as business authority.

## Decision

MoonProj adds a **top-down company execution plane**. The accountable principal
starts from a company objective, decomposes it into bounded work contracts,
assigns execution personas, and receives evidence-backed results and inert
command proposals. MoonFlow may progress each declared work item. MoonTown may
surface observations or propose new work. MoonClaw or another adapter may run
the Agents. Only MoonProj can authorize and record company effects.

The unique value is not “more Agents.” It is a closed, inspectable chain:

```text
company objective
  -> bounded role work
  -> recoverable multi-Agent execution
  -> evidence and independent review
  -> named-human or delegated company authorization
  -> typed business command
  -> accounting/cash/tax/audit consequence
  -> measured outcome and reviewed procedure learning
```

This is deliberately different from a personal agent workspace. The company,
not a conversation or Agent collective, remains the principal.

## Two authorization planes

### Runtime-permission plane

The execution runtime decides whether a tool may operate on a host resource:

- shell, files, browser, network, worktrees, and external Agents;
- sandbox paths and command risk;
- session, project, or one-shot grants;
- runtime cancellation and resource budgets.

Runtime permission answers **“may this process use this tool here?”** It does
not answer whether the company has authorized a business effect.

### Company-authority plane

MoonProj decides whether an actor may create a company effect:

- exact principal, actor, capability, and scope;
- amount ceiling, effective dates, and revocation;
- separation of duties and reserved matters;
- source evidence, idempotency, period, and resulting receipt;
- named-human approval where policy requires it.

Company authority answers **“may this actor bind or change this company fact?”**

### Non-substitution invariant

Neither plane implies the other. In particular:

- successful tool execution is not a company command;
- manager/reviewer approval of an Agent artifact is not business authorization;
- a company grant does not grant shell, network, or filesystem permission;
- an Agent proposal always carries `company_authority_granted=false`;
- accounting posting, cash/payment release, contract signing, tax filing, and
  trade execution are reserved effects re-authorized at the domain command.

## Three ledgers

### 1. Company ledger

The PostgreSQL company command/event/projection store is authoritative for
business facts. It owns immutable commands, domain events, aggregate revisions,
audit receipts, idempotency, accounting links, and business read models.

### 2. Execution ledger

The execution ledger owns operational facts that make Agent work recoverable:

- request/work/flow/attempt identities;
- phase, CAS revision, claim token, executor, and lease;
- attempt number, crash/interruption streaks, and quarantine;
- peer/child/review/human waits and rework rounds;
- tool/activity summaries, artifact references, and execution cost;
- terminal technical result and error classification.

Execution success is never projected as company acceptance or a financial
effect. The ledger may be implemented by the selected adapter, but it must
conform to `intelligence/agent_port` and retain the MoonProj correlation IDs.

### 3. Evidence ledger

The evidence ledger owns immutable or content-addressed inputs and outputs:

- customer briefs, observations, work artifacts, and review packets;
- hashes, media types, provenance, consent, retention, and redaction;
- acceptance evidence and links to proposed/domain commands;
- learning observations and procedure-review receipts.

Large artifacts need not live in PostgreSQL, but the company ledger stores
their verified references and digests.

## Execution invariants

1. Every execution request is versioned and identifies one principal, work
   item, flow run, capability, scope, evidence digest, acceptance contract,
   result schema, idempotency key, authority ceiling, and prohibited effects.
2. A dispatch requires `Ready` or `ReadyForRework`, a fresh CAS revision, a
   unique claim token, an executor identity, and a positive lease.
3. Active transitions require the matching claim token.
4. Expired active claims return to dispatchable state; passive review/human
   waits lose stale claims without re-running the original worker.
5. Three consecutive crashes or five consecutive interrupted leases quarantine
   the attempt for human attention.
6. Review rejection creates an explicit rework round; it does not mutate the
   previous result in place.
7. Terminal attempts cannot be reopened. New work uses a new attempt identity.
8. Artifacts and costs are revisioned execution observations, not authority.
9. Proposed commands are inert, schema-identified, evidence-linked, and
   independently idempotent.
10. A later typed domain command revalidates current company authority and may
    reject a technically successful proposal.

## Top-down, single-flow, and bottom-up composition

```text
MoonTown observation/proposal ─┐
                              v
Owner -> MoonProj objective -> company work graph -> role work contract
                                              |-> MoonFlow attempt A -> Agent
                                              |-> MoonFlow attempt B -> Agent
                                              `-> MoonFlow attempt C -> Agent
                                                        |
                                                        v
                                           review + evidence synthesis
                                                        |
                                                        v
                                              proposed company command
                                                        |
                                                        v
                                          MoonProj authority/domain gate
```

- MoonTown may originate evidence or a proposed objective, never self-admit a
  product, install a company pack, or grant authority.
- MoonFlow owns recovery within each declared workflow, not the multi-role
  company objective or institutional organization.
- MoonProj owns decomposition policy, role accountability, cross-work
  acceptance, founder attention, and all business effects.
- MoonClaw owns the generic Agent loop and may use parallel subagents inside a
  work contract, subject to the same claim and output boundary.

## Product and package ownership

- `intelligence/agent_port` owns public execution protocol types and invariants.
- `integration/moonflow_adapter` maps MoonFlow attempts to that protocol.
- professional-services shadow mode owns no payment, posting, signing, filing,
  or external-delivery authority.
- customer channels create verified observations or draft work only.
- procedure learning promotes candidates only after independent review.
- business capability packs, operating playbook packs, and talent/skill packs
  remain distinct.
- transactional pack activation requires a persisted Product In-Gate `pass`
  for the target workflow and an owner-approved installation receipt.
- autonomous staffing and a marketplace remain unavailable while the Basic OPC
  product is `experiment` or `unknown`.

## Consequences

Positive consequences:

- OpenOPC's best recovery and collaboration properties become available
  without reversing Moon Suite ownership.
- one person can direct several specialized Agents through a single accountable
  company objective;
- every automated result remains traceable to authority, evidence, acceptance,
  and economic outcome;
- Agent/provider replacement does not rewrite company history.

Costs and constraints:

- execution and company state must be correlated rather than stored as one
  generic task record;
- UI labels must distinguish execution success, acceptance, and authorization;
- adapters must persist claims and attempts and cannot rely on conversation
  history as recovery state;
- learning and package installation require review workflows instead of silent
  self-modification.

## Acceptance evidence

This decision is implemented only when all of the following are true:

- generated `agent_port` interface exposes the versioned request, attempt,
  claim, transition, recovery, result, and proposed-command contracts;
- tests prove CAS, claim-token, expiry, crash/interruption, review/rework,
  quarantine, reserved-effect, and inert-proposal behavior;
- the professional-services workflow operates in shadow mode end to end;
- the cockpit distinguishes attention, execution activity, acceptance, and
  company authorization;
- one customer channel verifies sender/provenance and cannot create effects;
- procedure promotion and pack activation fail closed without their reviews
  and Product In-Gate evidence;
- MoonFlow and MoonTown ownership remains explicit in code and documentation.
