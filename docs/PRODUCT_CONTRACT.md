# MoonProj product contract

Class: domain pack
Visible surface: project and program operator UI
Maturity: migration and operator-preview alpha
Last reviewed: 2026-07-30

## Outcome

MoonProj gives a one-person company one governed operating system for projects,
budget, accounting, procurement, sales, tax, treasury and management review.

## Users and jobs

- Founders plan and monitor work, cash, obligations and performance.
- Operators import or shadow existing ERP records.
- Agents prepare analyses and proposals under explicit authority.
- Named humans approve accounting, payment, tax and external business effects.

## Ownership

MoonProj owns OPC business-domain records, controls, reconciliations, reports
and migration evidence. It does not own model-provider access, the generic
agent loop, generic workflow state or durable wiki truth.

For Moon Suite jobs, MoonProj additionally owns the planning semantics of the
versioned `moonproj/project.plan.prepare@0.1.0` capability. MoonFlow may
schedule it and MoonClaw may invoke it, but neither product may bypass
MoonProj's native `ProjectPlan` invariants or turn its review-pending output
into company authority.

## Capability status

| Capability | Status |
| --- | --- |
| Project, budget and management-accounting models | available locally |
| Procurement, sales, treasury and tax workflows | available locally |
| Rabbita operator preview | available locally |
| PostgreSQL company service | available for development |
| Persisted Product In-Gate marking and audit trail | available locally |
| Versioned project-plan pack and restart-safe MoonFlow adapter | available locally |
| Existing ERP migration/shadowing | experimental |
| Production system of record | not yet declared |
| Autonomous payment, filing or contracting | excluded |

## Authority and accounting integrity

Every posting, approval, payment, filing and external communication records the
actor, authority, source document, period, revision and resulting receipt.
Agents may draft or reconcile; they cannot silently become the legal approver
or change a closed period.

During migration, the existing ERP remains authoritative until a named cutover
decision and reconciliation gate say otherwise.

## Operations and recovery

Production readiness requires database backup/restore, migration rollback,
period-close protection, audit export, credential rotation and clean-machine
deployment instructions. Preview data must remain distinguishable from
production books.

## Verification

```sh
moon check --target native
moon test --target native
moon info
moon fmt
```

Financial release validation additionally requires balanced-ledger,
authorization, duplicate-effect, migration reconciliation and restore tests.

The suite planning capability has a narrower release gate: exact manifest and
schema identity, source-evidence digests, deterministic replay, durable
reconciliation, budget-envelope validation, and an output that remains
pending named-human review with no business effects. See
[MOONFLOW_PROJECT_PLAN.md](MOONFLOW_PROJECT_PLAN.md).

## Release gates and next milestones

- Pass the upstream Product In-Gate for one narrow OPC workflow with dated
  problem evidence, a quantified workaround, a qualifying user commitment, a
  measurable outcome, and an adoption path. The current decision is
  `experiment`; see [PRODUCT_IN_GATE.md](PRODUCT_IN_GATE.md).
- Split oversized frontend and PostgreSQL service packages by business
  capability.
- Complete one real ERP shadow period with reconciliation.
- Prove backup, restore, close, reopen and rollback controls.
- Select one paid OPC workflow before expanding further modules.
