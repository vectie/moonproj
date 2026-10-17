# Deliverable workflow: producer/consumer wire review

This is a source cross-check, not a live runtime qualification. The feature was
compared with these exact integrated-main snapshots on 2026-10-12:

- MoonProj `70204e1ab4bd8be7cd6f094ef5c91b6738a8f731`
- MoonFlow `db116564185d4ed0394edc78c5e44d10391f5171`
- MoonClaw `a94d7f5863af856e2082a5c18d5f3afb4712464d`

## Plan and ownership

MoonProj `product/plan_workbench/contracts.mbt:141-200` assigns task gate IDs to
milestone gates and emits `scope_type: milestone`. The deliverable panel therefore
requires explicit per-task acceptance adaptation for milestone/project-wide gates.
It does not silently reuse them as task acceptance. `schemas/project-plan-artifact.schema.json`
defines owners, dependencies and the proposal-only authority fields.

Flow `types.mbt:120-152` defines RuntimeItem with dependency/acceptance fields but
no authenticated human assignment field. The work graph retains dependencies;
MoonProj retains the accountable plan owner and adds that name to the bounded goal
brief. Owner names do not create a Flow actor or grant company authority.

## Graph import and dispatch preparation

- Flow `cmd/main/main.mbt:993-1014`, `import_conformant_graph`, accepts
  `import-conformant-graph <workspace> <graph.json> <catalog.json> <evaluated-at>`;
  it compiles conformant graph events, persists the selected catalog and run.
- Flow `cmd/main/main.mbt:469-537`, `prepare_next`, reads a workspace-relative
  catalog, uses native runnable items and adapter selection, hashes declared
  inputs, writes `dispatch/<request-id>.request.json` and records submission.
- Flow `director.mbt:167-213` includes accepted direct prerequisite artifacts in
  the prepared input list and defines all AdapterRequest identities. The host
  checks those same identities and exact current input bytes.
- Flow `capability_catalog.mbt:989-1000` filters operation health using the current
  evaluation time. The host therefore stores per-candidate/per-attempt snapshots
  and uses native `validate-work-graph-capabilities` before each new preparation
  or invocation, rather than freezing one catalog forever. Because native Claw
  evaluates the invocation's supplied time, the definite-first-submit path also
  revalidates current health just before its durable submitting checkpoint. Only
  an unsent Prepared checkpoint may refresh timestamps with an identical payload;
  uncertain/submitted attempts retain their original snapshot for reconciliation.
- Flow `engine.mbt:607-615` exposes native Ready items to the director. The host
  does not manufacture Ready or Active states. It additionally refuses dispatch
  unless each declared prerequisite has accepted result/review evidence.
- Flow `cmd/main/main.mbt:805-880` stores run controls in `control.json`; the host
  respects paused/cancelled state and a narrowed authority ceiling.

## Installed Claw boundary

- Claw `capabilities/moonflow.adapter-declaration.v1.json` declares
  `moonclaw-agent-goal-v1`, pack 0.1.5 and agent.goal.execute.
- Claw `pack.json:52-66` declares WorkspaceMutation, digital output receipt/session
  prefixes and required review. `schemas/agent-goal-execution-request.schema.json`
  defines the exact request fields and local quantum limits. The host uses
  `moonclaw/agent.goal.execute@0.1.5`, request schema 1.0.0 and receipt schema 1.0.0.
- Claw `gateway/server/request.mbt:142-146` selects submit/reconcile/status.
  `gateway/server/capability_http.mbt:495-616` takes a bare invocation and emits
  the bare canonical receipt. It serves the workspace at `self.cwd` and loads
  host policy there; request data cannot install or widen that policy.
- Claw `packtool/capability_invocation.mbt:113-147` deliberately matches the
  common receipt fields to Flow AdapterResult. `:336-349` defines artifact digest
  as SHA-256 of ordered `ref|sha256:<bytes-hash>` lines without a trailing newline.
  `:930-995` validates identity/policy/input bytes and uses a durable idempotency
  lock before invoking the installed executor.
- Claw `packtool/agent_goal_executor.mbt:188-282` builds the goal from the exact
  request/profile and workspace. `:358-390` hashes evidence references found in
  its journal. `:430-484` writes a goal receipt and returns receipt + journal as
  top-level artifacts. Real deliverable content is in nested `artifact_evidence`.
  The MoonProj assembly verifies both digest levels and refuses receipt-only work.
  All tasks use the narrower deliverable run root, also used by Flow and the
  separately configured Claw gateway, avoiding mismatched relative artifact roots.

## Reconciliation and acceptance

- Flow `adapter.mbt:227-284` defines AdapterResult and its decoder. The bare Claw
  receipt can be sent unchanged to `reconcile-attempt`; no synthetic conversion
  or successful receipt is invented by this feature.
- Flow `cmd/main/main.mbt:918-939` reconciles that result with exact attempt events.
  `engine.mbt:436-465` maps submitted/running to Active, succeeded to Review, failed
  to Failed, cancelled to Cancelled, and unknown to Blocked. The fixture uses
  these exact mappings. A Blocked/unknown item stays reconcilable without submit;
  it cannot authorize a new rework scope while the original effect is uncertain.
- Flow `acceptance_review.mbt:5-25,139-216` binds the named review to run, work,
  declaration, result, attempt, output digest and exact criteria/evidence. Native
  `review-outcome` remains the acceptance operation. MoonProj does not post it.
- Flow `engine.mbt:294-298` stores `event.authority_id` in the misleadingly named
  `acceptance_reviewer_id`. This is the review authority, not the receipt's human
  `reviewer_id`. The panel labels it authority; assembly checks that authority
  against `review_authority_id` and displays the human from the exact receipt.

The focused tests use fixture adapters matching these inspected shapes and run
actual production host/helper/UI code. They cannot establish installed-pack
health, provider routing, persistent native service behavior or live PostgreSQL
acceptance. Missing registry dependencies prevent native compilation here; no
restoration, dependency substitution, browser-start retry, install or service
provisioning was performed.
