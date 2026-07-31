# MoonProj UI-to-UI qualification

Last reviewed: 2026-07-31
Surface: Rabbita OPC operator, internal `Projects` page
Product class: project and company portfolio; migration/operator-preview alpha

## Product truth

MoonProj has two related but currently unequal surfaces:

1. The internal `Projects` page is the published project-portfolio UI. It
   displays delivery stages, health, next Gate, and responsible Agent.
2. `moonproj/project.plan.prepare@0.1.0` is the pack-local durable plan
   capability. It creates a review-pending digital artifact with tasks,
   milestones, owners, budget envelope, risks, evidence, and acceptance gates.

The current UI does **not** yet render or review the adapter artifact. This
qualification therefore proves the published portfolio UI and its denial
behavior, while the exact plan capability is validated at its MoonFlow adapter
boundary. It must not be reported as a complete plan UI-to-UI loop.

## Prerequisites and launch

```sh
cd /Users/kq/Workspace/moonproj
warren dev frontend/opc --public-dir frontend/opc_public --port 4300
```

Open the standalone Warren development surface:

```text
http://127.0.0.1:4300/
```

Then use the left navigation to open **项目组合**. The standalone Warren server
does not provide SPA fallback for a direct `/projects` request and returns
404. A MoonDesk or pack host may mount a product route separately, but that
host behavior must be qualified in its own integration test.

## P1 — positive project-portfolio inspection

1. Open the application.
2. In the left navigation, click **项目组合**.
3. Confirm the page shows the software and hardware stage legends.
4. Inspect the four portfolio rows:
   - `OPC Core v0.9`
   - `Agent Evidence Bus`
   - `Edge Node MkII`
   - `Company Control Pack`
5. For each row, verify current stage, next Gate, health, and responsible Agent
   are visible.
6. Confirm the blocked hardware row remains visibly `阻塞`; the UI must not
   infer healthy status from the presence of a row.
7. Click **Moon 专案**, then select `moonrobo`.
8. Verify the three separate questions remain visible:
   - 走了多远
   - 走得多好
   - 能否生产
9. Confirm missing evidence is shown as `未知` or `尚未审计`, never as pass.
10. Click **出厂质检** and verify G1–G9 are derived from one candidate ledger.

This use case is read-only. It does not authorize a budget, task execution,
release, payment, or physical work.

## P2 — governed task denial

This exercises the visible command boundary without fabricating a successful
backend.

1. Click **任务编排**.
2. Open the formal task form.
3. Enter:
   - Task name: `Prepare governed robot-cell layout`
   - Acceptance: `Named review of plan, spatial model, and robot readiness`
   - Project ID: `proj-0001`
   - Signed identity: `ui-qualifier`
   - Planned start: `2026-08-03`
   - Planned completion: `2026-08-14`
4. Click **写入正式任务** while the signed PostgreSQL command gateway is absent.
5. Expect a visible failure/blocked state. No task may advance to pending,
   started, submitted, or accepted without the gateway’s event and audit
   receipts.
6. Reload the page. Seeded portfolio data must remain visible, but the failed
   command must not be presented as a durable accepted task.

## P3 — plan-capability recovery boundary

The detailed adapter contract is in
`docs/MOONFLOW_PROJECT_PLAN.md`. A supported external MoonFlow/MoonClaw caller
must:

1. Compile the exact `moonproj/project.plan.prepare@0.1.0` declaration.
2. Submit a `moonproj/project-plan-request@1.0.0` artifact and the exact
   aggregate input digest.
3. Grant only `workspace-mutation` with claim ceiling `digital-artifact`.
4. Inspect the result under:

   ```text
   .moonsuite/products/moonproj/adapter-attempts/<attempt-id>/
   ```

5. Verify the result remains:

   ```text
   workflow.status = pending_review
   workflow.accepted = false
   spend_authorized = false
   accounting_posted = false
   payment_released = false
   contract_signed = false
   work_executed = false
   ```

6. Interrupt after intent persistence, then call adapter `reconcile` with the
   same request and result references.
7. Expect the same immutable plan artifact. Changed input, digest, schema,
   authority, or idempotency identity must fail closed.

## What the missing UI integration must eventually add

The internal **项目组合** UI should project, without recomputing:

- durable plan request and artifact identity;
- tasks, dependencies, milestones, risks, and budget envelope;
- source-evidence digests;
- named-human review and decision receipt;
- reconciliation state;
- explicit false authority effects.

Until that projection exists, MoonProj can be the planning producer in a
MoonFlow graph, but the plan itself cannot honestly be accepted from UI to UI.

## Qualification record

- Source/build validation: passed (`moon check --warn-list +73`, 12 JS
  frontend tests, 3 native project-plan tests, 5 native MoonFlow-adapter tests,
  `moon info`, and a Warren production build; existing warnings only)
- Rabbita static root: passed at `/`
- Direct standalone `/projects`: known 404; internal navigation is the tested
  standalone route, while product-host route mounting remains an integration
  responsibility
- P1 portfolio and Gate navigation: passed in-app-browser qualification,
  including the blocked portfolio row, MoonRobo's three separate unknown
  projections, and the G1–G9 candidate ledger
- P2 visible gateway denial: passed; the complete signed form reached the
  absent standalone gateway and failed safely with zero persisted tasks
- Browser evidence:
  [`formal-task-safe-denial.png`](../../_build/ui-to-ui/2026-07-31-consolidated/formal-task-safe-denial.png)
- Plan adapter contracts/recovery: passed targeted MoonBit qualification;
  the published capability is `moonflow.adapter.v2`, claim ceiling
  `digital-artifact`, `supports_reconcile=true`
- Plan-artifact review in the internal **项目组合** page: not implemented / not
  tested
- Business or physical authorization: excluded
