# Governed project-plan capability

Status: implemented pack-local capability
Pack: `moonproj@0.1.0`
Operation: `moonproj/project.plan.prepare@0.1.0`

## Outcome

MoonProj can now turn a source-evidence-bound project request into one complete
planning artifact for the Moon Suite job canvas. The artifact contains:

- institutional project identity;
- named owners;
- dependency-ordered tasks and milestones;
- a fixed-point planned-cost envelope and contingency;
- risks and mitigations;
- acceptance gates and required evidence;
- immutable source-evidence identities;
- a review-pending workflow state.

It is a project proposal, not a business authorization.

## Exact contracts

| Boundary | Canonical identity |
| --- | --- |
| Operation | `moonproj/project.plan.prepare@0.1.0` |
| Input | `moonproj/project-plan-request@1.0.0` |
| Output | `moonproj/project-plan-artifact@1.0.0` |
| Authority | `workspace-mutation` |
| Claim ceiling | `digital-artifact` |
| Review | required; named human |
| Cancel | unsupported |
| Reconcile | supported |

The output always has `workflow.status = pending_review`,
`workflow.accepted = false`, and false values for spending, accounting,
payment, contract, and work-execution effects.

## Native invariant reuse

The capability does not invent a parallel project model. It constructs a
native `Project`, advances it to `Planning`, and adds every task through
`operations/project/ProjectPlan::add_task`. This preserves the existing
identity, fixed-point money, duplicate-task, self-dependency,
missing-dependency and authority-scope checks.

The grants used during this construction exist only to validate a
non-authoritative proposal. They are not stored as institutional authority and
cannot be reused by a later business operation.

## Durable call chain

```text
MoonFlow compiled capability catalog
  -> exact MoonProj manifest + adapter declaration + fresh health
  -> MoonClaw generic installed-capability invocation (or named operator)
  -> MoonProj pack-local adapter
  -> durable intent + idempotency identity
  -> native ProjectPlan validation
  -> immutable project-plan artifact
  -> MoonFlow-compatible result receipt
  -> named-human review in the existing project portfolio surface
```

MoonProj does not run a second agent runtime. MoonFlow owns cross-product graph
progress, MoonClaw owns agent execution, and MoonProj owns only company project
rules and artifacts.

## Restart and evidence behavior

The adapter records intent before calculation under:

```text
.moonsuite/products/moonproj/adapter-attempts/<attempt-id>/
```

It also records a SHA-256-keyed idempotency identity. If the process stops
after intent, reconciliation reloads the same request, verifies the complete
input digest and every source-evidence digest, then deterministically rebuilds
the same planning artifact. This replay is safe because the operation cannot
spend, post, pay, sign, execute, publish, or create a physical effect.

Conflicting intent, changed input, stale evidence, schema drift, authority
drift, claim drift, unsafe workspace paths and duplicate idempotency keys fail
closed.

The adapter decodes and retains the full generic MoonFlow request identity:
run, book, work item, work declaration, attempt, idempotency key and acceptance
criteria. MoonFlow's `declaration_id` is the work declaration, not the pack
adapter ID; it is therefore treated as an opaque bound identity. Adapter
selection is instead proven by the compiled catalog's exact canonical
operation, schema, authority, claim, declaration and health tuple.

Health attestations bind the exact operation and schema refs to
`moonflow.adapter.v2`. Their evidence path is content-addressed and their
validity window may not exceed one hour.

## Existing UI boundary

The existing Rabbita `/projects` route remains the only project-planning
surface. `pack.json` points to that route rather than creating another app.
This slice deliberately does not add fixture-backed “live” adapter state or a
second HTTP service. A later read-model projection can render the durable
artifact and named review receipt on `/projects` without copying project rules
into frontend code.

## Non-goals

This capability does not:

- accept a plan on behalf of a human;
- reserve or approve a budget;
- create procurement or contract obligations;
- execute tasks;
- post accounting;
- release payment;
- alter tax, treasury or investment records;
- authorize an external or physical effect.
