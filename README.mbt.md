# MoonProj — Basic OPC Company Operating System

> **Domain product · migration/operator-preview alpha.** Read the
> [product contract](docs/PRODUCT_CONTRACT.md) for accounting authority,
> system-of-record limits, operations and release gates.

This repository is the home of a standalone operating system for a general
One-Person Company (OPC). The company—not the founder's workspace—is the
principal: it owns resources, delegates authority, makes commitments and
exchanges, keeps accounts, finances operations, handles tax, learns, and
remains recoverable.

The product is independently operable. Initial Moon Suite integration is kept
deliberately shallow: MoonClaw may be used through an optional agent adapter,
and Moonfish investment capabilities will be absorbed into the native investment
domain. The working real-estate ERP is retained as the first extension pack and
as a broad migration acceptance source; it is no longer the definition of the
default product.

## Documentation

- [Desktop UI guide](docs/UI_GUIDE.md) — every Basic OPC page, the unified
  nine-Gate release model, PostgreSQL boundary, and LEPUSA preview recovery.
- [0.1.0 preview release notes](docs/releases/v0.1.0-preview.1.md) — packaged
  features, verification evidence, prerequisites, and signing limitations.
- [Moon Suite engineering control plane](docs/MOONSUITE_ENGINEERING_CONTROL_PLANE.md)
  — the three evidence views, project registry, MoonClaw skills and controller,
  independent review rule, UI workflow, problem ledger, and remaining connector
  work.
- [Basic OPC product architecture](docs/OPC_PRODUCT_ARCHITECTURE.md) — default
  product, three circuits, six organizational systems, MoonSuite awareness, and
  the real-estate extension boundary.
- [Product charter](docs/PRODUCT_CHARTER.md) — agreed product direction,
  boundaries, decisions, invariants, and success definition.
- [Conversation decisions](docs/DESIGN_DECISIONS.md) — chronological rationale
  for the separate product, shallow integration, Moonfish absorption, and ERP
  migration strategy.
- [Plan approval](docs/PLAN_APPROVAL.md) — records user approval of the product
  direction and migration plan, without authorizing production cutover.
- [ERP capability baseline](docs/ERP_CAPABILITY_BASELINE.md) — the minimum
  operational breadth and acceptance catalog inherited from the working ERP.
- [ERP snapshot inventory](docs/ERP_SNAPSHOT_INVENTORY.md) — metadata-only
  table counts and executable shadow controls from the available SQLite backup.
- [ERP full-export contract](docs/ERP_FULL_EXPORT_CONTRACT.md) — credential-free
  validation for a future complete MySQL/JSON source export.
- [ERP source-export request](docs/ERP_SOURCE_EXPORT_REQUEST.md) — exact
  49-table handoff generated from the schema/cohort plan.
- [ERP MySQL source probe](docs/ERP_MYSQL_SOURCE_PROBE.md) — read-only metadata
  probe result and current connection availability.
- [ERP row-coverage ledger](docs/ERP_ROW_COVERAGE.md) — proves every available
  non-empty source row has a target, evidence, or explicit structural disposition.
- [Business-acceptance packet](docs/BUSINESS_ACCEPTANCE_PACKET.md) — structured
  owner decisions required before shadow operation.
- [Shadow-period contract](docs/SHADOW_PERIOD_CONTRACT.md) — read-only target,
  legacy authority, comparison dimensions, and rollback requirements.
- [Migration completion audit](docs/MIGRATION_COMPLETION_AUDIT.md) — verified
  requirements versus external source and owner gates still open.
- [Migration plan](docs/MIGRATION_PLAN.md) — phased implementation, Moonfish
  absorption, optional MoonClaw adapter, data migration, verification, cutover,
  and rollback gates.
- [ERP translation map](docs/ERP_TRANSLATION_MAP.md) — semantic mapping from
  legacy ERP tables and workflows to target packages and current status.
- [ERP CBS cost-link cohort](docs/ERP_CBS_COST_LINK.md) — explicit source-cost
  to governed CBS-subject migration and parity rehearsal.
- [ERP workflow assignment cohort](docs/ERP_WORKFLOW_ASSIGNMENT.md) — explicit
  workflow assignee migration without implicit permissions.
- [ERP parameter catalog cohort](docs/ERP_PARAMETER_CATALOG.md) — explicit
  opaque parameter and expense-proceeding catalog migration.
- [ERP delivery-progress cohort](docs/ERP_DELIVERY_PROGRESS.md) — draft-only
  task-report translation with acceptance and accounting boundaries.
- [ERP task-state exception review](docs/ERP_TASK_STATE_EXCEPTION.md) —
  fail-closed handling of dependency-conflicting source states.
- [ERP schema-only cohorts](docs/ERP_SCHEMA_COHORTS.md) — seven ordered waves
  for the 49 ERP tables absent from the current snapshot.
- [ERP foundation-security cohort](docs/ERP_FOUNDATION_SECURITY_COHORT.md) —
  explicit ownership and security mapping for the first schema-only wave,
  without fabricating absent rows.
- [ERP workflow-control schema cohort](docs/ERP_WORKFLOW_CONTROL_SCHEMA_COHORT.md)
  — approval, warning, and runtime-assignee mapping with no implicit authority.
- [ERP cost-investment schema cohort](docs/ERP_COST_INVESTMENT_SCHEMA_COHORT.md)
  — CBS and Moonfish-model ownership with no implicit budget, accounting, or
  investment effects.
- [ERP procurement-contract schema cohort](docs/ERP_PROCUREMENT_CONTRACT_SCHEMA_COHORT.md)
  — supplier, tender, contract-split, and milestone ownership with separate
  award/payment controls.
- [ERP sales-receivables schema cohort](docs/ERP_SALES_RECEIVABLES_SCHEMA_COHORT.md)
  — customer, invoice, refund, receivable, payable, revenue, and tax boundaries.
- [ERP delivery-treasury schema cohort](docs/ERP_DELIVERY_TREASURY_SCHEMA_COHORT.md)
  — delivery, treasury, and marketing ownership without implicit cash effects.
- [ERP reporting-notification schema cohort](docs/ERP_REPORTING_NOTIFICATION_SCHEMA_COHORT.md)
  — report, message, email, and share-token controls.
- [Tax filing boundary](docs/TAX_FILING_BOUNDARY.md) — separate reviewed
  filing evidence from tax payment and ledger posting.
- [Bank statement boundary](docs/BANK_STATEMENT_BOUNDARY.md) — immutable
  statement import, exact cash-movement reconciliation, and separate
  statement-to-ledger evidence.
- [Authority controls](docs/AUTHORITY_CONTROLS.md) — RBAC, delegation,
  separation-of-duties, and workflow-enforcement boundaries.
- [Production deployment gate](docs/PRODUCTION_DEPLOYMENT_GATE.md) —
  credential-free managed database, backup, restore, and owner-approval contract.
- [PostgreSQL target setup](docs/POSTGRES_TARGET_SETUP.md) — local PostgreSQL
  target configuration and credential-free raw-envelope apply; ERP MySQL
  remains source-only.
- [Rabbita frontends](frontend/README.md) — the industry-neutral Basic OPC
  product in `frontend/opc` and the separately preserved designer ERP surface
  in `frontend/main` for the real-estate extension pack.
- [Basic OPC UI acceptance](docs/OPC_UI_ACCEPTANCE.md) — screen map, interaction
  boundary, responsive evidence, and local run commands for the default UI.
- [Moon Suite boundary](docs/MOON_SUITE_BOUNDARY.md) — observed sibling
  ownership, reuse rules, and optional integration order.
- [Governed project-plan capability](docs/MOONFLOW_PROJECT_PLAN.md) — the
  product-owned planning pack, exact MoonFlow contracts, durable replay and
  named-human review boundary.

## Current status

The repository is an active MoonBit migration. The executable `opc-basic`
profile and `real-estate-erp` extension manifest now make the new product
boundary testable without relocating working code prematurely. The first
slices cover
legal entities, organization hierarchy, scoped authority, fixed-point money, chart-of-accounts/period controls, source-to-journal accounting links, journal invariants, dependency-gated project plans, budget
reservation, commitment and settlement state transitions, invoice/receivable
controls, customer/reservation/mortgage/refund sales records, marketing campaign/placement controls, supplier/tender/milestone procurement, delivery evidence, audit/evidence provenance, cost forecasting, warning findings, cash planning/dispatch, migration manifests, versioned SQL catalog, tax obligations, cash-account controls, financing facilities, investment model versions/indexes, local investment mandates/proposals/portfolio valuation, reconciliation reports, a
versioned JSON/file record-store adapter with durable pending-snapshot
transactions, aggregate projections, and parameterized SQL transaction plans,
asset lifecycle/depreciation controls,
an ERP fixture importer, a
MoonClaw-neutral agent port, and a deterministic investment analytics seed. The
existing ERP remains authoritative;
see [implementation status](docs/IMPLEMENTATION_STATUS.md) for the verified
boundary and next slices. The migration rehearsal now supports separately
versioned typed cohorts and a clean project-2 task-state wave, while preserving
the inconsistent project-1 state rows as quarantine evidence.

The optional suite projection now also publishes
`moonproj/project.plan.prepare@0.1.0`. It reuses the native `ProjectPlan`
dependency and fixed-point cost invariants, persists restart-safe MoonFlow
intent and receipts, and emits only a review-pending digital planning artifact.
It cannot spend, post, pay, sign, or execute work.
