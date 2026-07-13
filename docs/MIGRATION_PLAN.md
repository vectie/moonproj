# ERP-to-Company-Product Migration Plan

Status: active strangler-migration plan; no cutover authorized  
Recorded: 2026-07-13  
Source: working site ERP in `../erp/erp_new`  
Target: standalone company product in this repository

## 1. Objective

Build and adopt a standalone company operating system that preserves the broad
operational capability of the current ERP and adds complete institutional,
accounting, treasury, financing, tax, and investment models.

The program must protect the working site. The current ERP remains authoritative
until an explicitly named capability passes specification, parity, migration,
shadow, operational, user-acceptance, and rollback gates.

Current execution baseline: the repository has translated the institutional,
finance, operational, investment, evidence, warning, and migration foundations;
the real sanitized 26-table/120-row fixture now passes raw SQLite rehearsal,
19 mapped economic rows through native domain importers, 2 workflow definitions
with 12 steps, 2 project lifecycle cohorts, 2 dependency-ordered task plans,
1 investment model with 26 indexes, 4 planned milestones, and 2 performed
commitments with 3 requested settlements, and 5 credential-free user
identities plus 2 explicitly mapped audit records, and 2 opaque parameter
dictionaries with 8 options (including the 3-row expense-proceeding catalog).
These are promotion rehearsals, not a production
cutover. The task-state planner has a clean project-2 replay and quarantines
two project-1 dependency conflicts. The source schema report also records 75
authoritative ERP table definitions, 26 present in this fixture, and 49
schema-only tables requiring later cohorts. The next hard gates are a
production SQL driver, durable target projections with reviewed accounting
links, remaining typed-cohort promotion, shadow parity, and business-owner
acceptance. The current fixture also proves
two balanced commitment links plus one employee-advance opening source-to-
journal link, transactionally persisted and idempotently replayed; they are
traceability receipts, not cash release or accounting-book posting.
The separate advance-offset cohort also replays one explicit `cb_loan_offset`
against the imported advance and passes projection parity; its accounting link
remains a separate reviewed event. An optional payment-accounting cohort now
ties all three requested-settlement applications to reviewed journals without
releasing cash or posting a period.
The typed-cohort runner now promotes and projects 34 additional business items
across workflow, lifecycle, task structure, investment, payment, users, audit,
parameter, and the clean project-2 task-state cohorts, with a distinct mapping
version and exact parity report for each cohort. Task-state conflicts in project
1 remain quarantined. Forty additional typed-evidence rows (task
snapshots/reports, assignees, lifecycle history/catalog, and proceedings) are
preserved without becoming business state, bringing the typed-cohort total to
74.
The optional eighth cohort maps all seven non-empty `cb_cost` rows to explicit
CBS subjects through `cmd/cbs_link`, and persists one deduplicated active
`cbs_version` configuration projection; its 103-projection/17-receipt
rehearsal passes exact parity and replay while leaving budget consumption and
accounting posting separate. Full CBS schema coverage remains open.
The optional ninth cohort maps all six `wf_step_assignee` rows through
`cmd/workflow_assignment`; its 109-projection/18-receipt rehearsal retains
workflow configuration, validates explicit process/step attachment, and does
not create permissions or approve instances.
The typed investment cohort then runs `cmd/investment_model_eval` against its
native promotion receipt, adding one mapping-scoped source-bound evaluation
projection; the next complete typed run therefore reaches 110 projections.
The optional eleventh cohort maps the one `jd_task_report` row through
`cmd/delivery_progress`; the next evaluation-aware full rehearsal reaches 111 projections while
retaining the report as a draft-only delivery intake with acceptance,
recognition, budget/cost consumption, and task-state mutation false.
The current complete SQLite rehearsal additionally runs the source-bound CBS
budget planner against the five positive `cb_cost.dfs_budget` values; with CBS
cost links, workflow assignments, delivery progress, offset accounting, and
payment accounting it reaches 112 aggregate projections, 7 durable accounting
links, and 21 migration receipts with exact parity and idempotent replay.
The same source-bound warning scan can add one `warning_finding` projection for
the two explicit leaf-row component overruns, reaching 113 projections and 22
receipts while notification routing and workflow mutation remain separate.
The optional notification cohort maps a reviewed source event to one
authority-checked `notification_outbox` projection, reaching 114 projections
and 23 receipts in the complete rehearsal. It proves queue intent and
idempotent replay without invoking a provider or mutating workflow, cash, or
accounting state; source notification rows and production delivery remain
later gates.
The optional reviewed access cohort validates source-role intent through the
native authority directory and adds one `access_directory` projection,
reaching 115 projections and 24 receipts in the complete rehearsal. It makes
authority migration explicit while excluding passwords and super-user bits;
real source role rows and owner approval remain later gates.
The optional fourteenth cohort maps only separately reviewed accepted delivery
evidence through `cmd/delivery_recognition`; it requires a positive measured
value and explicit acceptance evidence, and produces a pending-posting
source-to-journal link without posting, cash release, tax, or period close.
The authority directory now proves effective-dated bounded delegation,
revocation, and exact-scope separation-of-duties checks; legacy role-table
migration and site-specific delegation policy remain later cohorts.
The finance boundary also now separates asset-disposal derecognition journals,
tax-filing preparation/submission/acceptance, and bank-statement import,
cash-movement reconciliation, and statement-to-ledger traceability from
posting or external filing/bank adapters. These slices are locally tested
domain evidence; production adapters and period-close acceptance remain later
gates. The managed-production manifest validator is likewise in place, but the
fixture intentionally remains `ready_for_owner_review` until finance,
operations, and security approve it.
The first schema-only wave now has an explicit six-table target/security map.
Because the available snapshot has zero rows for `foundation-security`, this
artifact records semantic ownership and exclusion rules only; it does not
pretend that the wave has been imported.

## 2. Program constraints

1. No big-bang rewrite or cutover.
2. No uncontrolled dual writes.
3. No production capability is retired on screen similarity alone.
4. Existing ERP breadth is the minimum replacement floor.
5. The new product owns all core company data and rules locally.
6. Initial Moon Suite integration is limited to an optional MoonClaw adapter.
7. Moonfish investment capability is absorbed, not called as a required service.
8. Money, postings, authority, and audit invariants are designed before migration.
9. Every migration is repeatable, measurable, idempotent, and reversible.
10. Calendar commitments are made only after team capacity and the capability
   inventory are known.

## 3. Migration strategy

Use a capability-oriented strangler migration with explicit record ownership.

For every capability, maintain an ownership state:

```text
legacy-owned
  -> target-shadow
  -> target-owned-with-legacy-read
  -> target-owned
  -> legacy-archived
```

At any moment, one system is authoritative for a record class. During shadow
operation, target results are compared but not allowed to create external effects.
During transition, the legacy system may receive a read-only projection, but the
program avoids bidirectional business writes.

## 4. Workstreams

The phases below are sequencing gates. Several workstreams may proceed in
parallel after their dependencies are stable.

### Workstream A — Capability discovery and parity control

Deliverables:

- route, table, page, report, background-job, and integration inventory;
- business capability map using IDs from `ERP_CAPABILITY_BASELINE.md`;
- named business owner for every capability;
- state machines and business invariants;
- current production volumes, period boundaries, and retention requirements;
- golden scenarios from real site workflows;
- parity register and decision log;
- list of legacy behavior to preserve, intentionally change, or retire.
- source-envelope fixtures and an atomic manifest-to-store apply rehearsal;
- metadata-only schema/backup inventory with immutable source hash;
- credential-safe, deterministic row export from the SQLite snapshot, with
  per-table hashes and a manifest kept outside the target repository;
- raw staging-envelope generation from that redacted export, with primary-key
  identity, source-id uniqueness, and fail-closed secret checks;
- an executable schema-gap report comparing the authoritative ERP initializer
  with each fixture export (75 definitions / 26 present / 49 schema-only), with
  every table assigned to a baseline capability ID and migration action;
- an executable schema-only cohort plan that orders all 49 absent tables into
  seven dependency-aware waves with security-specific actions;
- a reviewed relationship/orphan audit over the read-only fixture, with every
  non-empty reference either resolved or explicitly quarantined;
- a capability-tagged route-surface inventory covering handler and middleware
  registrations, with scenario-verification actions for every route;
- raw-row staging for unmapped tables, kept separate from target-owned
  aggregates;
- count, balance, and minor-unit parity metrics with declared tolerances;
- immutable migration receipts that retain the pre-apply baseline and fail
  closed on rollback conflicts;
- cohort-scoped projection and accounting receipt hashes so later append-only
  migration waves do not invalidate earlier accepted cohorts;
- executable shadow plans that derive target counts and accept explicit source
  control totals;
- validated opening control-total sets keyed by domain and reconciliation
  dimension, with duplicate and negative-value rejection;

Exit gate:

- every site-critical capability is at least `specified`;
- no critical workflow depends only on undocumented operator knowledge;
- existing ERP defects are distinguished from desired target behavior.

### Workstream B — Target architecture and engineering foundation

Deliverables:

- final module/product name and deployment topology;
- database selection and versioned migration tool;
- domain package map and public type ownership rules;
- identity, tenancy/entity, local RBAC/delegated authority, workflow, evidence,
  and audit foundations;
- decimal-safe money, currency, quantity, rate, and accounting-period types;
- immutable business-event and journal identifiers;
- API versioning, idempotency, pagination, error, and concurrency conventions;
- schema-versioned record envelopes, durable pending-snapshot transactions,
  append-only aggregate projections, and a driver-neutral SQL command port;
- a versioned company SQL catalog covering the record envelope, aggregate
  revisions, source-to-journal links, and migration receipts;
- a concrete driver adapter for the parameterized company-record command port,
  with an allow-listed SQL shape, bound parameters, duplicate failure, and
  transaction rollback verification;
- an executable SQLite rehearsal adapter that applies the catalog transactionally,
  records migration receipts, reopens for verification, and proves idempotent
  replay before a production database service is selected;
- a durable projection adapter that accepts only native domain-promotion
  receipts, appends immutable aggregate revisions, records projection receipts,
  and proves idempotent replay before production service integration;
- a reopened projection-parity gate that compares source identity and target
  type counts, rejects missing/extra revisions, and records `shadow_verified`
  only on an exact cohort match;
- an explicit accounting-link plan and native command that require reviewed
  event/journal mappings, balanced postings, and append authority, followed by
  a transactional durable-link apply with uniqueness, integrity, and replay
  checks; this gate must remain separate from cash release and period posting;
- an exact-scope separation-of-duties policy in the access directory that
  rejects incompatible active role assignments before bounded grants are
  issued; delegation expiry remains a later authority gate;
- a single end-to-end rehearsal command that chains source export, raw staging,
  durable SQLite apply, and backup/restore parity without writing to the source
  ERP;
- an explicit mapped-cohort promotion-plan generator that turns reviewed
  identity/money mappings into candidate target records and quarantines gaps;
- a typed-cohort rehearsal runner that versions each workflow/lifecycle/task,
  investment/payment, identity/audit, and parameter map separately, applies
  native receipts to durable projections, and requires exact reopened parity;
- a cutover-readiness evidence gate that combines all cohort parity, replay,
  database, SQL-driver, backup/restore, and quarantine evidence while keeping
  authorization false until named owners accept the remaining exceptions;
- a credential-free managed-production deployment manifest and validator that
  requires bounded pooling, TLS, encryption, cross-region backup, restore
  objectives, rollback, observability, and operations/security/finance approval;
- a credential-free production-service manifest and validator that requires
  authenticated fixed read endpoints, schema-matched readiness, private TLS
  binding, bounded reusable pooling, and no arbitrary SQL or mutation routes;
- an executable authenticated PostgreSQL fixed-read runtime with bounded
  reusable sessions, fail-closed exhaustion, forwarded-TLS enforcement, schema
  readiness, and a local negative-path smoke; managed gateway and provider
  deployment remain separate gates;
- a source-to-journal reconciliation gate that checks reviewed principal,
  amount, currency, event, source, and journal identity against durable links
  without treating traceability as cash release or period posting;
- a reconciled period-close control that aggregates every accepted subledger
  report and requires the native accounting-book close gate;
- secrets, encryption, access logging, backup, restore, observability, and CI;
- test pyramid with unit, state-machine, contract, migration, integration, and UI tests.

Suggested MoonBit package direction:

```text
foundation/entity
foundation/organization
foundation/party
foundation/identity
foundation/authority
foundation/workflow
foundation/evidence

operations/project
operations/sales
operations/marketing
operations/procurement
operations/supplier
operations/contract
operations/delivery
operations/expense

finance/budget
finance/cost
finance/accounting
finance/receivable
finance/payable
finance/treasury
finance/financing
finance/tax

investment/domain
investment/analytics
investment/portfolio
investment/agents

intelligence/warning
intelligence/reporting
intelligence/forecasting
intelligence/agent_port

adapters/moonclaw
```

Packages are created incrementally with real behavior. Public concrete types stay
in their owning public package; implementation-only parsers, persistence helpers,
and validators may use `internal/*`.

Exit gate:

- a fresh environment can be created entirely from versioned migrations;
- authority and money invariants have executable tests;
- backup and restore are demonstrated before business data is loaded;
- core operation succeeds with MoonClaw and all other Moon products absent.

### Workstream C — Institutional and finance backbone

Build first because every operational domain depends on it:

- legal entity, business unit, department, project, and counterparty identity;
- user, employment identity, role, delegated authority, data scope, and segregation;
- configurable workflow and approval cases;
- chart of accounts, accounting book, dimensions, periods, and posting templates;
- budget, reservation, release, transfer, and consumption;
- payable, receivable, cash, bank, and reconciliation primitives;
- evidence, attachments, audit, notification, warning, and exception cases.

Required vertical scenario:

```text
authorized user
  -> reserves a project budget
  -> creates a controlled commitment
  -> receives and accepts a service
  -> recognizes a payable
  -> approves and settles payment
  -> posts and reconciles journals
  -> retains evidence and complete authority history
```

Exit gate:

- the scenario is balanced, reversible, auditable, and repeatable;
- unauthorized, self-approved, over-budget, duplicate, and replayed commands fail;
- operational, subledger, general-ledger, and cash states reconcile.

### Workstream D — Core operational parity

Implement site workflows in dependency order:

1. Project master, lifecycle, planning, and delivery progress.
2. CBS, target cost, committed cost, actual cost, and dynamic forecast.
3. Supplier master, risk, sourcing, tendering, and award.
4. Contract, amendment, milestone, payable, invoice, and payment.
5. Expenses, employee advances, loans, allocation, and reimbursement.
6. Customers, marketing, reservations, sales agreements, receivables, and collections.
7. Project progress linkage to cost, revenue, cash, and warnings.

For each capability:

- implement local domain rules and public APIs;
- add black-box tests for stable business outcomes;
- add white-box tests only for private invariants;
- define accounting and tax event mapping;
- migrate representative records;
- replay golden scenarios;
- compare reports and exception behavior;
- obtain business-owner acceptance.

Exit gate:

- all site-critical operational capabilities are `scenario-verified`;
- cross-domain workflows do not require manual database fixes;
- material operational events reconcile to accounting consequences.

### Workstream E — Moonfish absorption and investment expansion

#### E1. Inventory Moonfish

Classify every Moonfish package as:

- reusable deterministic investment domain logic;
- investment agent behavior;
- evidence, replay, comparison, or review logic;
- adapter to another Moon product;
- migration/cutover history;
- obsolete or duplicated infrastructure.

#### E2. Define the target investment domain

The target owns:

- investment mandates and limits;
- projects, instruments, portfolios, positions, and counterparties;
- market snapshots and provenance;
- assumptions, models, versions, and scenarios;
- proposals, approvals, orders, executions, settlements, and fees;
- valuation, exposure, performance, and risk;
- investment accounting and tax events;
- agent requests, analyses, recommendations, and evidence.

#### E3. Port behavior, not repository shape

- copy or translate cohesive packages with their tests;
- rename concepts only through explicit mapping;
- remove dependencies that exist solely for old suite orchestration;
- keep deterministic analytics callable without any agent runtime;
- place research agents behind the local agent port;
- archive migration/parity/decommission material as evidence;
- compare outputs on fixed market fixtures before retiring Moonfish.

Required vertical scenario:

```text
investment mandate and available cash
  -> versioned market evidence
  -> deterministic Moonfish analytics
  -> optional investment-agent recommendation
  -> local mandate, risk, authority, and conflict checks
  -> approval
  -> simulated then controlled execution
  -> position, cash, fee, tax, and journal events
  -> valuation, performance, monitoring, and review
```

Exit gate:

- deterministic fixture outputs meet the approved parity tolerance;
- agents cannot execute or approve investments directly;
- investment positions, cash, accounting, and performance reconcile;
- Moonfish can be placed in read-only archive mode.

### Workstream F — Optional MoonClaw adapter

Define a product-owned port before implementing the adapter.

Minimum request contract:

```text
request_id
institutional_principal
human_or_service_actor
requested_capability
authority_ceiling
input_evidence_refs
expected_result_schema
deadline
idempotency_key
```

Minimum result contract:

```text
request_id
status
findings
recommendations
evidence_refs
confidence
proposed_commands
resource_usage
error_classification
```

Rules:

- requests contain the minimum authorized data;
- results are stored and audited locally;
- proposed commands pass the normal local API and authorization path;
- timeouts and MoonClaw absence degrade gracefully;
- model and agent failures never partially post business transactions;
- paid usage has quotas, rate limits, ownership, and cost reporting.

Initial allowed capabilities:

- document extraction and classification;
- contract clause and risk review;
- supplier or investment research;
- reconciliation suggestions;
- anomaly investigation;
- report explanations and draft narratives.

Initial forbidden effects:

- journal posting;
- payment release;
- investment execution;
- final approval;
- authority delegation;
- tax filing;
- deletion or destructive correction of business records.

Exit gate:

- unplugging MoonClaw leaves all core operations available;
- malformed, late, duplicate, unauthorized, and adversarial results are rejected;
- every accepted proposal links to actor, authority, evidence, and resulting command.

### Workstream G — Reporting, controls, tax, and financing completeness

Deliverables:

- group, company, project, department, and portfolio cockpits;
- standard operational and financial reports;
- controlled custom report models and exports;
- warning rules, risk register, controls, tests, findings, and remediation;
- bank reconciliation, liquidity forecast, facilities, debt, interest, and covenants;
- jurisdiction, registration, tax rule, invoice qualification, withholding, filing,
  payment, and tax reconciliation;
- period close, statements, intercompany activity, and consolidation;
- traceable AI explanation over authorized report datasets.

Exit gate:

- management reports drill to reconciled source records;
- accounting statements balance and reconcile to subledgers;
- tax outputs reconcile to invoices, accounting, and settlement;
- financing balances and covenant calculations are reproducible;
- report access applies the same entity and data-scope rules as operations.

## 5. Data migration plan

### 5.1 Inventory and classify

Inventory all current tables, columns, views, files, attachments, reference data,
generated records, and operational logs. For each source object record:

- business owner;
- record volume and growth;
- authoritative or derived status;
- retention and sensitivity;
- primary and natural keys;
- relationships and orphan behavior;
- quality findings;
- target aggregate or entity;
- transformation and defaulting rules;
- reconciliation measures.

### 5.2 Build stable identity maps

Preserve source identifiers as migration references while generating target
identifiers. Identity maps cover entity, business unit, department, user,
project, customer, supplier, contract, workflow, invoice, payment, account,
investment, and attachment records.

Maps are immutable after acceptance except through audited correction.

### 5.3 Establish opening accounting state

Operational history alone cannot safely infer an accounting opening position.
Prepare and approve:

- opening trial balance by entity, book, currency, account, and dimension;
- open receivables and payables;
- cash and bank balances;
- employee advance and loan balances;
- contract commitments and retention;
- budget reservations and remaining budget;
- assets and accumulated depreciation;
- financing principal, accrued interest, and covenants;
- tax balances and open filing obligations;
- investment positions, cost, cash, and valuation basis.

Represent the approved opening workbook as a versioned control-total set before
loading target records. Each control names its domain, dimension, value, and
tolerance. The migration runner compiles that set into the shadow plan and
requires the target projection to pass the resulting exact/tolerance checks.
This prevents a successful row import from being mistaken for a reconciled
opening position.

### 5.4 Repeatable migration pipeline

Every migration run has:

- immutable source snapshot identifier;
- target schema version;
- mapping version;
- row counts and control totals;
- rejected-record quarantine;
- deterministic rerun behavior;
- per-domain reconciliation report;
- signed business-owner decision for unresolved differences.

### 5.5 Attachments and evidence

Migrate content, not only database pointers. Verify:

- content hash;
- size and media type;
- original filename and provenance;
- owner and linked records;
- access classification;
- retention and legal hold;
- readable retrieval after migration.

### 5.6 Reconciliation dimensions

Reconcile at least by:

- legal entity and business unit;
- project;
- customer and supplier;
- contract;
- account and accounting period;
- currency;
- budget and CBS subject;
- bank account;
- tax category and filing period;
- investment portfolio and position.

## 6. Verification program

### 6.1 Golden business scenarios

Create executable scenarios from real workflows, including:

- normal completion;
- rejection and resubmission;
- cancellation and reversal;
- early, duplicate, and excessive payment;
- insufficient budget;
- authority expiry and delegation;
- supplier blacklist and risk escalation;
- partial delivery, invoice, payment, and collection;
- period close and late adjustment;
- tax exception;
- financing covenant warning;
- agent failure and disputed recommendation.

### 6.2 Financial invariants

Automate checks that:

- every journal balances;
- each source aggregate produces at most one accounting event for a given
  source identity;
- subledgers reconcile to control accounts;
- bank and cash movements have settlement evidence;
- no payment exceeds the approved payable without controlled exception;
- operational reversal produces accounting reversal or adjustment;
- closed periods reject unauthorized posting;
- currency and decimal rounding follow policy;
- consolidated results eliminate approved intercompany balances.

### 6.3 Security and authority tests

Test entity isolation, data scope, amount thresholds, delegation, expiry,
segregation of duties, report access, attachment access, API replay, idempotency,
agent data minimization, and administrative audit.

### 6.4 Operational tests

Rehearse deployment, migration, backup, restore, failover, job ownership,
monitoring, alerting, support diagnostics, capacity, and rollback.

## 7. Cutover waves

The exact grouping depends on site dependencies, but the default order is:

| Wave | Candidate ownership transfer | Required prerequisite |
|---|---|---|
| 0 | Read-only master-data and report shadow | Foundation and migration pipeline |
| 1 | Organization, identity, projects, dictionaries | Identity mapping and authority acceptance |
| 2 | Budget, CBS, and cost planning | Finance backbone and opening dimensions |
| 3 | Suppliers, procurement, contracts, expenses | Payable, workflow, evidence, and accounting |
| 4 | Sales, customers, receivables, collections | Receivable, cash, revenue, and tax mapping |
| 5 | Project delivery and progress | Project, contract, cost, and revenue linkage |
| 6 | Treasury, financing, tax, close, reporting | Reconciled subledgers and bank controls |
| 7 | Investment and absorbed Moonfish agents | Investment accounting, mandate, and risk |
| 8 | Legacy archive and retirement | All critical capabilities accepted |

Before each wave:

1. freeze the affected legacy schema and behavior except emergency fixes;
2. take a recoverable source snapshot;
3. run migration and reconciliation;
4. complete shadow comparison;
5. obtain technical, security, finance, and business sign-off;
6. rehearse rollback;
7. communicate ownership and support changes;
8. cut over during the approved window;
9. monitor enhanced controls and reconciliation;
10. retain the legacy path read-only until the exit window closes.

## 8. Program gates

### Gate A — Scope controlled

- capability baseline owned and prioritized;
- critical workflows specified;
- intentional changes approved.

### Gate B — Foundation trustworthy

- authority, money, event, journal, audit, migration, backup, and restore proven.

### Gate C — Functional parity

- golden scenarios and cross-domain workflows pass.

### Gate D — Data and finance reconciled

- counts, totals, balances, attachments, and opening positions accepted.

### Gate E — Shadow verified

- target results meet agreed parity tolerances over a representative period.

### Gate F — Operationally ready

- performance, security, support, monitoring, incident response, and rollback pass.

### Gate G — Business accepted

- named owners sign off; users complete role-based acceptance and training.

### Gate H — Legacy retired

- retention requirements met; old write paths disabled; archive is searchable and controlled.

## 9. First actions

These actions start the program without premature integration:

1. Approve `PRODUCT_CHARTER.md` as the product boundary.
2. Assign owners to the capability IDs in `ERP_CAPABILITY_BASELINE.md`.
3. Generate the complete ERP inventory and link routes, tables, pages, reports,
   and jobs to capability IDs.
4. Select five golden workflows: project investment, contract-to-payment,
   expense-to-settlement, sale-to-collection, and period-close reconciliation.
5. Decide target database, deployment, accounting standard, tax jurisdiction,
   and first migration cohort.
6. Design and test decimal money, institutional principal, actor, authority grant,
   business event, evidence reference, and journal primitives.
7. Run the snapshot inventory, schema-gap report, and credential-safe row
   export; freeze the source hash and export manifest, and approve the first
   cohort. The available backup exposes 26 application tables and 120 rows
   against 75 schema definitions; 19 rows have mapped domain import seams and
   the remaining rows require typed preservation or later domain validation.
8. Review the redacted export for secret leakage and relationship/orphan
   findings; `scripts/erp_snapshot_export.sh` is the repeatable extractor and
   `scripts/erp_snapshot_stage_raw.sh` creates raw staging envelopes only from
   its sanitized output.
9. Approve the identity/counterparty/employee/currency mapping file and run
   `scripts/erp_promotion_plan.py`; do not promote quarantined items.
10. Run `cmd/promote` through the wrapper and retain the domain-promotion
    receipt; do not call the cohort target-owned until the receipt and financial
    controls are accepted.
10a. If the CBS cost-subject cohort is approved, review
     `scripts/fixtures/cbs_cost_link_mapping.json`, run the wrapper's eighth
     argument, and retain its dedicated parity/replay evidence; do not infer
     CBS subjects from legacy cost codes.
10b. If workflow assignment migration is approved, review
     `scripts/fixtures/workflow_assignment_mapping.json`, run the wrapper's
     ninth argument, and retain its configuration parity/replay evidence;
     assignees must not become authority implicitly.
11. Inventory Moonfish packages and produce the keep/port/archive matrix.
12. Define the local agent port without importing MoonClaw.
13. Estimate calendar and staffing only after steps 2–11 expose actual scope.

## 10. Progress reporting

Report progress by accepted capabilities and reconciled workflows, not by line
count, page count, or route count.

Recommended dashboard:

```text
capabilities by parity state
critical workflows passing / total
unresolved migration rejects
financial reconciliation differences
security and authority failures
shadow comparison differences
business-owner acceptances
rollback rehearsals passed
legacy record classes remaining authoritative
```

A broad product is complete only when broad business behavior and economic truth
are accepted together.
