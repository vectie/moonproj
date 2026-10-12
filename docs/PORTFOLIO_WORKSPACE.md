# MoonProj portfolio workspace

MoonProj is the founder's top-down product and commitment surface. MoonDesk is
for quick prototypes and MoonTown for bottom-up emergence. Those roles reflect
the founder's direction; a live cross-product handoff is not yet verified.

## Start

From the MoonProj repository:

```sh
sh scripts/run_portfolio_workspace.sh
```

Open `http://127.0.0.1:4310/`. The normal entry shows 25 active products and
MoonStat's separate retirement entry. MoonProp and Mooncake are excluded;
MoonMini is an alias. The bundle contains the 447-row source PRD assessment,
and each product page can open the existing versioned PRD workspace. The
catalog is a source snapshot and does not prove current runtime fulfillment.

The loopback host stores adapter attempts under
`~/Library/Application Support/MoonProj/portfolio-workspace`. It does not use
the signed PostgreSQL company ledger. Set `MOONPROJ_PORTFOLIO_DATA` to an
isolated directory for a synthetic trial, and `MOONPROJ_PORT` to a different
loopback port if 4310 is occupied. Back up the data directory before moving
machines; browser PRD versions and plans have their own JSON export/restore.

## Produce a result

Choose a product and one PRD requirement, then press **Generate review-pending
plan**. The host invokes MoonProj's existing native
`moonproj/project.plan.prepare@0.1.0` adapter with a fixed digital-artifact
claim. Its real output is a JSON plan with a task, owner, milestone, acceptance
gate, risk and next actions. **Open exact JSON artifact** shows the produced
file. Repeat clicks reuse the same attempt. Cancel stops only that local adapter
process; retry resumes the same request. If durable intent exists the adapter
reconciles it; if cancellation came before intent it executes the immutable
request with the same idempotency identity.

This creates a planning artifact, not code, a customer result, an approved
project or a company accounting fact. Source PRD assessments remain unverified
until independently checked. No model provider or paid service is called.

## Missing goal-to-code path

The signed MoonProj gateway and MoonClaw daemon were not responding in
the local review. PostgreSQL was accepting connections at the final check,
but no signed MoonProj service/session was configured or tested. The existing architecture gives MoonFlow work progress,
MoonClaw agent execution, and MoonProj company planning/authority. To make a
founder goal produce a code change inside the product, connect a specific
approved plan artifact to a running MoonFlow/MoonClaw work declaration, then
render its real result and require human acceptance. This workspace does not
simulate those missing services or claim that an agent changed source code.

## Approved work handoff (code-only integration)

The portfolio host can now prepare a MoonFlow work graph and MoonClaw native
`moonclaw/agent.goal.execute@0.1.5` request from the exact produced plan. This
requires `MOONPROJ_EXECUTION_CONFIG` to name a canonical owner-only JSON file
with `contract_id: moonproj.portfolio-execution-config.v1`, an absolute
`workspace_root`, an explicit `model_selector` beginning `moongate/`, and an
absolute `review_file`. The review file must also be owner-only and contain
`contract_id: moonproj.portfolio-plan-review.v1`, `decision: approved`, the
portfolio `run_id`, exact `plan_digest` and `source_digest`, a named
`reviewer_id`, and `reviewed_at`. This is a local operator review boundary,
not a signed company approval or a substitute for the MoonProj gateway.

After a plan is produced and reviewed, **Prepare approved MoonFlow work**
writes `flow/work-graph.json`, `inputs/agent-goal-execution-request.json`, and
`runtime/execution-handoff.json` below the same durable portfolio run. Repeated
preparation accepts only identical bytes. The work graph uses MoonClaw's real
pack operation, schema IDs, claim ceiling, and one stable MoonClaw session and
goal ID. The request targets the configured workspace, allowing MoonDesk to
open and steer that same MoonCode session rather than creating a second task.

The host reads the native MoonFlow projection from that run workspace and
shows attempt, result digest, artifact references, and named review only when
the projection still binds the original plan digest and work identity. An
accepted label requires a succeeded attempt, a result digest, and MoonFlow's
named acceptance review. MoonDesk's existing edit baseline and MoonClaw's
durable journal/checkpoint remain responsible for human interleaving and
revision conflicts; this handoff does not implement a second editor or
runtime control loop.

`scripts/portfolio_dispatch.mjs` contains the native MoonClaw capability HTTP
client and a durable journal for the prepared attempt. Its fake-adapter tests
cover success, failure, cancellation receipts, timeout, retry, identity checks,
and recovery after a MoonFlow reconciliation interruption. The portfolio host
does not expose live dispatch: its invocation packet is not submitted to
MoonClaw. A live dispatch endpoint requires separately reviewed provider usage,
sandbox policy, and gateway authority configuration. Until then, no code result
may be inferred from the packet or local journal alone.

**Import approved work into MoonFlow** uses an operator-configured canonical
`moonflow_binary` and `catalog_file` to run MoonFlow's existing
`import-conformant-graph` and `prepare-next`. The host preserves the exact
catalog bytes in the run and reuses the existing run/attempt on retry. This
creates MoonFlow's durable work position and request; it does not submit a
model request, execute a tool, promote a file, or publish an artifact. The
resulting MoonFlow projection is the portfolio readback. MoonClaw selects
`moongate/<model>` only from MoonGate's live catalog;
the configured Ark Agent Plan entry or a saved suite-status file alone is not
a successful provider check. MoonFort still gates agent-controlled commands.

After `prepare-next` records an attempt, **Prepare MoonClaw dispatch packet**
reads its actual MoonFlow request artifact, checks operation, schema, run,
work item, declaration, input digest and idempotency identity, and writes
`runtime/capability-invocation.json`. Its default
`provider_calls_forbidden: true` prevents an accidental model call. An
operator-owned execution config may explicitly set `provider_calls_approved`
only after a separate bounded usage decision; preparing the packet still
makes no request. The portfolio shows the attempt, result digest, artifacts,
and independent review from the MoonFlow projection, never from a local
optimistic state flag.

## Source and authority

The catalog was generated by `scripts/generate_portfolio_catalog.py` from the
Library PRD evidence dossier and 447-row requirement CSV; their Library IDs
and SHA-256 hashes are recorded in `frontend/opc_public/portfolio_catalog.json`.
The PRD workspace's imported assessment is not a new verification. Local plan
results are separate from formal company facts, and a named founder still owns
selection, authorization, and acceptance.
