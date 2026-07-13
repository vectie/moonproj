# ERP-to-Target Translation Map

Recorded: 2026-07-13  
Source: `../erp/erp_new`  
Target: this repository

This map records semantic translation, not a promise that target tables will
match legacy tables one-for-one. The new product owns its aggregates and emits
its own business and accounting events. Legacy identifiers remain migration
references.

The current `persistence/store` package is a reference adapter for this
envelope. It now provides deterministic JSON snapshots, a thin file adapter,
validated backup/restore helpers, and all-or-nothing in-memory batches. The
`persistence/sql` package adds a version-checked, parameterized command and
transaction-plan boundary, while `persistence/store` adds a pending-snapshot
transaction journal and append-only aggregate projections. A concrete database
driver is still required for production. Every adapter must preserve the same
record identity, schema-version, source-event, and duplicate guarantees.

The `migration/erp` package now has executable fixture translators for
`ep_project`, `cb_contract`, classified dynamic-cost rows, suppliers, tenders,
milestones, invoices, expenses, and employee loans. They also produce
schema-bound JSON envelopes with stable source identities for repeatable batch
import. These translators are deliberately small and reject invalid input
instead of silently coercing it.

For source tables without a domain translator, `LegacyRawRow` preserves the
read-only extractor payload as `legacy/raw/<table>` evidence. Raw staging is
not a company aggregate and must pass a later domain translation and authority
validation step before it can become target-owned business data.

The checked-in SQLite fixture can be exported with
`scripts/erp_snapshot_export.sh` into a credential-safe, per-table hashed
bundle, then staged with `scripts/erp_snapshot_stage_raw.sh`. The staging
bridge consumes only that redacted bundle, emits 120 unique raw envelopes for
the current fixture, and fails closed if a secret-shaped key or stable source
identity is missing.

The source-row envelope layer now covers the snapshot's task/progress, payment
plan/application, workflow definition/step/assignee, lifecycle,
investment-version/index, loan-offset, parameter, proceeding, and credential-
safe user/audit shapes. These are typed preservation seams; their target-owned
state machines and accounting links remain migration gates.

`migration/manifest` records the source snapshot, target identity, disposition,
quarantine reason, and apply/rollback state for each migration item. Validated
manifests can now atomically apply matching target envelopes to the record store;
target mismatches fail before any record is appended.

`migration/parity` provides the shadow-run comparison primitive for counts and
minor-unit totals. A report is accepted only when every metric is exact or
within its declared tolerance; mismatches remain visible rather than being
silently rounded away.

`migration/run` wraps a validated manifest apply in an immutable receipt. It
retains the baseline, records parity certification, and refuses rollback when
the applied target has changed since the receipt was issued.

`migration/shadow` builds parity reports from the actual target record store:
record counts are derived directly, while domain control totals are supplied
by the sanitized extractor. This keeps shadow evidence reproducible without
coupling the migration package to a database vendor.

`migration/control` validates the opening-state control-total set before it is
compiled into a shadow plan. Each control is keyed by domain and dimension,
rejects duplicate or negative values, and carries an explicit tolerance. This
is the bridge between an approved ERP opening-balance workbook and executable
target-side reconciliation.

`migration/erp/snapshot.mbt` also records the available SQLite backup as a
metadata-only 26-table/120-row inventory. Mapped, typed-staged, planned, and empty source
tables are all represented in the shadow plan, so the current small fixture is
not mistaken for complete ERP coverage.

`scripts/erp_schema_gap_report.py` makes that boundary executable: it parses
the authoritative `erp_new/server/src/db/index.js` initializer, compares its
75 table definitions with the export manifest, assigns each table to a
baseline capability ID (for example `SAL-01`, `SRM-04`, `WF-03`, or `FIN-09`),
and emits a machine-readable 75/26/49 scope report. Each absent table carries
an explicit `specify_then_implement_then_import` action, except credential
history which requires a security review exclusion. The cutover gate requires
this report and carries the 49 schema-only tables as an explicit open scope
exception.
`scripts/erp_schema_cohort_plan.py` then orders those 49 tables into seven
dependency-aware waves, preserving table-specific security actions for tokens,
credentials, attachments, email/network data, and retention. See
[ERP_SCHEMA_COHORTS.md](ERP_SCHEMA_COHORTS.md).

`scripts/erp_relationship_audit.py` executes the reviewed relationship map
against the read-only SQLite source because the legacy initializer does not
declare foreign keys. The current fixture checks 60 relationships and 216
non-empty references with zero orphan values; the result is included in the
cutover evidence before any target promotion is considered reconciled.

`scripts/erp_route_inventory.py` inventories the actual ERP route surface and
tags every handler with a baseline capability ID. The current source reports
30 route files, 338 handler registrations, and 28 middleware registrations;
the route surface remains a parity inventory until each critical workflow has
scenario evidence in the company product.

`persistence/sql` supplies a versioned DDL catalog (`company_catalog`), a driver-neutral
parameterized command/transaction contract, and executors against both the
immutable record store and the durable file boundary for a generic company
record envelope. `scripts/company_sqlite_rehearsal.py` applies the same four
schema gates to SQLite, persists the sanitized raw-envelope cohort in one
transaction, records a migration receipt, reopens the file, and proves an
identical replay is idempotent. `scripts/company_sqlite_projection_apply.py`
then consumes only a native, domain-validated promotion receipt and persists
immutable aggregate revisions plus a projection receipt with idempotent replay.
The executable `scripts/company_postgres_service.py` now provides the local
authenticated fixed-read runtime plus the reviewed expense, contract,
payment-application, and tender command verticals, with bounded reusable sessions, schema
readiness, idempotency, projection, and audit receipts. The payment-application
read model joins the three real `cb_htfk_apply` rows to their contract,
project, supplier, applicant, plan, and dual approval/payment state; its local
command boundary also covers edit/void and milestone early/over-payment checks.
The tender read model exposes latest procurement projections and its local
planning/publish/open-bidding/award/complete/cancel boundary; imported tenders
remain read-only and awards require an active qualified supplier projection.
The supplier read model exposes qualification/scope candidates to
`/srm/providers`; local supplier create/update/review/blacklist/void commands,
derived risk reads, tender award, and contract-split commands now share the
same idempotent PostgreSQL/audit boundary. Imported rows remain read-only and
award-to-commitment remains a separate authority gate.
`scripts/company_postgres_dev_gateway.py` adds the local
HttpOnly session and signed actor assertion required by the Rabbita browser;
managed provider deployment, token issuer/audience validation, and operational
backup/restore runbooks are still required. The rehearsal backup/restore parity
gate is executable.
`scripts/company_sqlite_driver.py` is the shared local driver boundary used by
projection, accounting-link, backup, and rollback smoke paths. It centralizes
WAL, foreign keys, busy timeout, immediate transactions, catalog application,
and reopen checks; managed pooling, encryption, retention, and operational
restore remain deployment gates.
Its allow-listed prepared-command path executes the exact `company_record`
insert emitted by `persistence/sql`, preserving parameter binding and duplicate
failure semantics instead of exposing arbitrary SQL.
Projection and accounting receipts hash only their own source/mapping cohort,
so later append-only cohorts do not invalidate earlier migration receipts.
The complete multi-cohort wrapper is rerunnable: the second run inserts zero
projections and links while retaining every receipt.
`scripts/company_sqlite_projection_parity.py` compares the reopened projections
back to the receipt's source identities and target types; the mapped cohort is
`shadow_verified` at 19/19, and a mismatched workflow cohort fails with
explicit missing/extra findings.
The PostgreSQL target now has the equivalent
`company_postgres_projection_apply.py` and
`company_postgres_projection_parity.py` adapters. The configured local target
has 109 reviewed aggregate projections across the base, ten typed cohorts, and
the optional CBS, workflow-assignment, delivery-progress, and advance-offset
cohorts;
each receipt reopens as `shadow_verified` and an identical replay inserts zero
rows. PostgreSQL receipt state is separate from cash, accounting posting, and
business ownership.
`scripts/erp_accounting_link_plan.py` then requires an explicit reviewed
source-to-journal map for an allow-listed set of commitment, advance/offset,
settlement, expense, delivery, receivable, payable, tax, financing, investment
acquisition/valuation, asset, cash, and bank source types. The native `cmd/accounting_link` command validates balanced
journals, principal/scope authority, and duplicate event/source protection
before emitting a receipt. The standalone
`scripts/company_postgres_accounting_cohort_rehearsal.sh` runs any reviewed
receipt through native validation, PostgreSQL traceability, and replay; it
never releases cash, posts a period, or invents accounting recognition.
The fifth wrapper argument runs the separate advance-offset promotion and its
own accounting-link receipt when that cohort has been approved.
Each accounting receipt is also checked by
`scripts/company_sqlite_accounting_reconciliation.py`, which ties the reviewed
amount/principal/currency back to the promoted source candidate and durable
link while keeping cash and period posting false.
The seventh wrapper argument can supply a target-type-restricted payment
accounting map; it validates three requested-settlement/payment-application
links from the typed payment cohort and appends them without cash release or
period posting.
The eighth wrapper argument can supply the independently reviewed CBS
cost-subject map; it translates all seven non-empty `cb_cost` rows through the
native `finance/cbs` link API, persists `cbs_cost_link` projections, and proves
exact parity/replay plus one deduplicated active `cbs_version` configuration
projection without budget consumption or accounting posting. See
[ERP_CBS_COST_LINK.md](ERP_CBS_COST_LINK.md).
The ninth wrapper argument can supply the independently reviewed workflow
assignment map; it translates all six `wf_step_assignee` rows through the
native workflow assignment API and persists `workflow_assignment` projections
with typed `configuration_only=true`, `grants_authority=false`, and
`approves_instance=false` evidence without turning assignees into permissions.
See
[ERP_WORKFLOW_ASSIGNMENT.md](ERP_WORKFLOW_ASSIGNMENT.md).
The eleventh wrapper argument can supply the independently reviewed delivery
progress map; it translates the one `jd_task_report` row through the native
delivery API as a `Draft` `progress_report` with explicit evidence and zero
completed value. Acceptance, recognition, budget/cost effects, and task-state
mutation remain separate. See
[ERP_DELIVERY_PROGRESS.md](ERP_DELIVERY_PROGRESS.md).
The fourteenth wrapper argument can supply a separately reviewed delivery
recognition map; it translates accepted progress evidence through the native
recognition API into a `delivery_recognition` projection with explicit
acceptance evidence and pending-posting state. Posting, cash release, tax, and
period close remain separate. See
[ERP_DELIVERY_RECOGNITION.md](ERP_DELIVERY_RECOGNITION.md).
The seventeenth wrapper argument can supply a reviewed consolidated-report
plan; it combines balanced sections under one source snapshot and persists a
non-posting `consolidated_report` projection. See
[ERP_CONSOLIDATED_REPORTING.md](ERP_CONSOLIDATED_REPORTING.md).
The eighteenth wrapper argument can supply a reviewed external benchmark
reconciliation plan; it is passed through `cmd/investment_benchmark` and the
same projection/parity/replay adapters. See
[ERP_INVESTMENT_BENCHMARK.md](ERP_INVESTMENT_BENCHMARK.md).
The nineteenth wrapper argument can supply a reviewed warning plan; it is
passed through `cmd/warning` and persists source-bound warning evidence
without notification delivery, workflow mutation, or cash effects. See
[ERP_WARNING_BOUNDARY.md](ERP_WARNING_BOUNDARY.md).
The twentieth wrapper argument can supply a reviewed CBS budget plan; it is
passed through `cmd/cbs_budget` and persists reservation/consumption evidence
without accounting posting or cash release. See
[ERP_CBS_BUDGET.md](ERP_CBS_BUDGET.md).
The twenty-first wrapper argument can supply a source-bound CBS budget mapping;
the wrapper derives a plan from explicit positive `cb_cost.dfs_budget` values
and requires a consume decision for every source amount. This is budget
reservation evidence, not an inferred posting or cash event.
The twenty-second wrapper argument can supply a source-bound warning mapping;
the wrapper derives one `warning_finding` from explicitly named positive
`cb_cost` overruns, preserving source IDs and scan policy without notification,
workflow, cash, or accounting effects.
The twenty-third wrapper argument can supply a reviewed notification plan;
`cmd/notification` maps it to a source-bound `notification_outbox` receipt and
projection. Queue intent is explicit, while provider delivery, workflow
mutation, cash release, and accounting posting remain false. See
[ERP_NOTIFICATION_BOUNDARY.md](ERP_NOTIFICATION_BOUNDARY.md).
The twenty-fourth wrapper argument can supply a reviewed access plan;
`cmd/access_import` maps explicit roles, bounded permissions, exact-scope
assignments, and separation rules into an `access_directory` receipt and
projection. Passwords and legacy super-user privilege remain excluded. See
[ERP_ACCESS_BOUNDARY.md](ERP_ACCESS_BOUNDARY.md).
The twenty-fifth wrapper argument can supply a reviewed accounting-posting map
after the base accounting-link map. `scripts/erp_accounting_post_plan.py`
selects an explicit chart, period, and exact already-linked event IDs;
`cmd/accounting_post` calls the native `AccountingBook.post` gate and persists
an `accounting_posting` projection with exact SQLite/PostgreSQL parity and
zero-insert replay. Cash release, tax filing, opening balances, period close,
and production ownership remain separate. See
[ERP_ACCOUNTING_POSTING.md](ERP_ACCOUNTING_POSTING.md).
The twenty-sixth wrapper argument can supply a separately reviewed opening
control map. `scripts/erp_opening_control_plan.py` and `cmd/opening_control`
compile exact value/tolerance/unit/dimension controls through native
`migration/control`; SQLite and PostgreSQL adapters compare complete candidates
and replay idempotently. The controls are reconciliation evidence only:
accounting posting, cash release, tax filing, and period close remain false.
See [ERP_OPENING_CONTROLS.md](ERP_OPENING_CONTROLS.md).
The twenty-seventh SQLite wrapper argument, or the twenty-fifth PostgreSQL
cohort-runner argument, can supply a separately reviewed tax-filing map.
`scripts/erp_tax_filing_plan.py` and `cmd/tax_filing` replay the native tax
obligation and filing lifecycle, while exact adapters preserve rates, amounts,
currency, period, authority reference, and accepted/rejected state. Tax
payment, accounting posting, cash release, and period close remain false. See
[ERP_TAX_FILING.md](ERP_TAX_FILING.md).
The twenty-eighth SQLite wrapper argument, or the twenty-sixth PostgreSQL
cohort-runner argument, can supply a separately reviewed bank-statement map.
`scripts/erp_bank_statement_plan.py` and `cmd/bank_statement` validate exact
opening/closing balance arithmetic and line identity through native
`finance/treasury`; exact adapters preserve balances, currency, references,
timestamps, amounts, and directions. Movement matching, ledger reconciliation,
cash release, and accounting posting remain false. See
[ERP_BANK_STATEMENT.md](ERP_BANK_STATEMENT.md).
The twenty-ninth SQLite wrapper argument, or the twenty-seventh PostgreSQL
cohort-runner argument, can supply a separately reviewed financing-facility
map. `scripts/erp_financing_facility_plan.py` and
`cmd/financing_facility` replay the native facility lifecycle and interest
calculation; exact adapters preserve limit, draw, repayment, outstanding
principal, rate, state, and interest evidence. Lender calls, cash release,
accounting posting, tax treatment, and period close remain false. See
[ERP_FINANCING_FACILITY.md](ERP_FINANCING_FACILITY.md).
The thirtieth SQLite wrapper argument, or the twenty-eighth PostgreSQL
cohort-runner argument, can supply a separately reviewed asset-lifecycle map.
`scripts/erp_asset_lifecycle_plan.py` and `cmd/asset_lifecycle` replay native
capitalization, depreciation, impairment, and disposal controls; exact
adapters preserve book values, depreciation entries, disposal basis, gain/loss,
and lifecycle state. Journal posting, disposal cash, tax treatment, and period
close remain false. See [ERP_ASSET_LIFECYCLE.md](ERP_ASSET_LIFECYCLE.md).
The thirty-first SQLite wrapper argument, or the twenty-ninth PostgreSQL
cohort-runner argument, can supply a separately reviewed treasury plan and
dispatch map. `scripts/erp_treasury_plan_dispatch_plan.py` and
`cmd/treasury_plan_dispatch` replay native cash-plan confirmation/actualization
and inter-project dispatch approval/execution; exact adapters preserve planned
and actual amounts, direction, project scopes, reasons, and states. Bank
movement, cash release, accounting posting, tax treatment, and period close
remain false. See
[ERP_TREASURY_PLAN_DISPATCH.md](ERP_TREASURY_PLAN_DISPATCH.md).
The thirty-second SQLite wrapper argument, or the thirtieth PostgreSQL
cohort-runner argument, can supply a separately reviewed invoice/subledger map.
`scripts/erp_invoice_subledger_plan.py` and `cmd/invoice_subledger` issue and
accept customer invoices, open receivables, record bounded collections, and
open/pay supplier obligations. Exact adapters preserve source identity,
principal, party, project scope, amount, currency, payment, and lifecycle
state across `invoice`, `receivable`, and `payable` projections. Cash release,
revenue/expense posting, tax settlement, and period close remain false. See
[ERP_INVOICE_SUBLEDGER.md](ERP_INVOICE_SUBLEDGER.md).
The thirty-third SQLite wrapper argument, or the thirty-first PostgreSQL
cohort-runner argument, can supply a separately reviewed procurement cohort.
`scripts/erp_procurement_cohort_plan.py` and `cmd/procurement_cohort` validate
supplier qualification, tender bids/award, and the separate award-to-commitment
boundary. Exact adapters preserve supplier identity, project scope, bids,
award amount, counterparty, and commitment state across `supplier`, `tender`,
and `commitment` projections. Cash release, accounting posting, settlement,
tax, and period close remain false. See
[ERP_PROCUREMENT_COHORT.md](ERP_PROCUREMENT_COHORT.md).
The standalone `scripts/company_invoice_procurement_accounting_rehearsal.sh`
then binds two receivable openings, one payable opening, and one performed
procurement commitment through target-specific accounting-map keys. Exact
SQLite/PostgreSQL identity parity and zero-insert replay preserve four
source-to-journal links without releasing cash, posting the book, settling tax,
or closing a period. See
[ERP_INVOICE_PROCUREMENT_ACCOUNTING.md](ERP_INVOICE_PROCUREMENT_ACCOUNTING.md).
The thirty-fourth SQLite wrapper argument, or the thirty-second PostgreSQL
cohort-runner argument, can supply a separately reviewed investment
performance map. `scripts/erp_investment_performance_plan.py` and
`cmd/investment_performance` build a bounded mandate/portfolio, attribute
explicit quotes, and reconcile an external benchmark observation. Exact
adapters preserve positions, quote values, returns, benchmark evidence,
differences, and tolerance across `investment_portfolio`,
`investment_performance`, and `investment_benchmark_reconciliation`
projections. Position mutation, cash release, accounting posting, and period
close remain false. See [ERP_INVESTMENT_PERFORMANCE.md](ERP_INVESTMENT_PERFORMANCE.md).
The standalone `scripts/company_investment_valuation_accounting_rehearsal.sh`
then reuses that reviewed portfolio plan with a separate valuation map and
explicit accounting map. `cmd/investment_valuation` constructs the native
mark-to-market event; `cmd/accounting_link` binds its event, journal, accounts,
scope, principal, amount, and currency without posting. SQLite/PostgreSQL
adapters preserve one `investment_valuation` source-to-journal link with exact
identity parity and zero-insert replay. Position mutation, cash release,
accounting-book posting, and period close remain false. See
[ERP_INVESTMENT_VALUATION.md](ERP_INVESTMENT_VALUATION.md).
The standalone `scripts/company_tax_financing_accounting_rehearsal.sh` adds
the same explicit boundary for finance obligations. Separate reviewed maps
compile two tax-obligation recognition events and one financing draw plus one
repayment event; `cmd/tax_accounting_link` and
`cmd/financing_accounting_link` call the native event builders before
`cmd/accounting_link` validates the final source-to-journal identities. Exact
SQLite/PostgreSQL parity and zero-insert replay pass for all four links.
Tax filing/payment, lender calls, cash release, book posting, and period close
remain separate. See [ERP_TAX_FINANCING_ACCOUNTING.md](ERP_TAX_FINANCING_ACCOUNTING.md).
When accounting mappings are supplied, the wrapper also emits
`period-close-control.json`; it aggregates every reconciled link cohort and
requires the native `AccountingBook.close_reconciled` gate before a real period
can close.
The sixth wrapper argument (or the standalone
`scripts/erp_typed_cohort_rehearsal.sh`) runs separately versioned typed
cohorts: workflow, lifecycle, task structure, investment, payment, users,
audit, parameters, and the clean project-2 task-state cohort. The fixture
accepts 34 business-cohort items; every cohort is projected to SQLite and rechecked at exact
`shadow_verified` parity. Project 1 task state remains a separate exception
gate, while its undecided exception is now durably preserved as a separate
non-authorizing observation projection.
The evidence plan additionally preserves 40 rows from task snapshots/reports,
workflow assignees, lifecycle-instance history, lifecycle-stage catalog, and
proceeding catalog as `typed_evidence` projections. These are queryable
redacted evidence, not target workflow, authority, or economic state.
The source-bound investment evaluation adds one analytics-only projection.
Together the 34 business, 40 typed-evidence, one task-state-observation, and
one evaluation cohort items add 76 accepted typed projections to the rehearsal
database; evidence rows remain explicitly non-authoritative.
The PostgreSQL cohort wrapper additionally emits
`cross-domain-projection-parity.json`, comparing every supplied domain receipt
between the SQLite and PostgreSQL payloads after both stores are reopened. The
full wrapper also emits `cutover-gate.json`; a technical pass means
`ready_for_business_acceptance`, not ownership transfer. The artifact records
the unresolved project-1 dependency, managed-production database deployment,
and 49 schema-only-table scope as explicit next actions.
The wrapper `scripts/erp_migration_rehearsal.sh` runs export, staging, and this
SQLite apply in one repeatable read-only-source flow.
It finishes by backing up and reopening the target database with
`scripts/company_sqlite_backup_restore.py`; logical counts and digests must
match before the rehearsal can be promoted to an operational review.
`scripts/erp_promotion_plan.py` then consumes only the sanitized export and an
approved mapping file. It generates 19 mapped-cohort candidates (business
units, projects, contracts, costs, and advances), converts money under an
explicit fixed-point policy, and quarantines missing ownership/counterparty/
employee evidence. It remains a plan for the MoonBit domain importers, not a
shortcut around them. `cmd/promote` is the native application boundary: it
refuses quarantined plans, calls the explicit target importers, and writes a
domain-promotion receipt for the accepted cohort.
`scripts/erp_lifecycle_promotion_plan.py` adds a second reviewable plan for
project masters and lifecycle instances. Its native promotion first creates
projects, then replays only the ordered current stage under explicit
`project:advance` authority; source progress and dates remain preserved
evidence. The current fixture reaches `development` and `design` for its two
projects and refuses incomplete stage maps.
`scripts/erp_task_promotion_plan.py` now promotes the dependency-ordered task
structures for both projects through `migration/erp.import_project_tasks`.
It deliberately does not replay task state/progress: the source child-state
history is not compatible with the target dependency invariant and remains
typed evidence until an explicit exception mapping is approved.
The full task-state plan now also emits a review-only exception artifact with
the two `proj-0001` dependency conflicts and empty owner decision fields;
`scripts/erp_task_state_exception_review.py` never repairs or authorizes those
states automatically. See [ERP_TASK_STATE_EXCEPTION.md](ERP_TASK_STATE_EXCEPTION.md).
`scripts/erp_investment_promotion_plan.py` now promotes the fixture's one
investment model and 26 indexes through `import_investment_models`, keeping
index values as source representations and refusing missing principals or
stray indexes.
`scripts/erp_payment_promotion_plan.py` adds an explicit contract-state map:
the native boundary replays two contracts to `performed`, converts four
payment-plan rows into planned milestones, and converts three applications
into requested settlements only. Approval, release, cash, and accounting
events remain separate.
`scripts/erp_accounting_link_plan.py` is a separate, reviewed accounting gate:
the fixture maps two performed contracts and one employee advance to balanced
journals, and the native receipt is persisted as three durable links. The link
is traceability only; it does not post a journal to an accounting book or
recognize cash.
`scripts/erp_user_promotion_plan.py` promotes five safe user identities through
`foundation.UserDirectory` and `import_users`; credentials, network data,
authentication timestamps, and legacy super-user privilege remain excluded or
evidence-only.
`scripts/erp_audit_promotion_plan.py` promotes two audit records only after an
explicit target/outcome interpretation and actor-scoped append grant; missing
target mappings remain quarantined and redacted network fields stay excluded.
`scripts/erp_parameter_promotion_plan.py` promotes the original 5-option
`cost_subject` dictionary plus an explicitly mapped 3-option
`expense_proceeding` catalog through the local parameter API under explicit
principal/scope grants; values remain opaque until a later CBS/accounting or
expense-domain map, and proceeding metadata remains source evidence.
`scripts/erp_task_state_promotion_plan.py` simulates dependency completion:
the full fixture quarantines two child states for `proj-0001`, while a clean
`proj-0002` plan replays its two task states through the authority-bearing
importer.

## Implemented translation seams

| ERP source | ERP meaning | Target package | Current state |
|---|---|---|---|
| `mu_business_unit`, `sys_user`, `sys_role`, `sys_user_role` | Entity, organization, actor, role, and authority context | `foundation` + `foundation/access` + `foundation/organization` + `migration/erp` + `cmd/promote` + `cmd/access_import` | Legal entity, business-unit hierarchy, and 5 credential-free user identities are implemented. The reviewed access importer now validates explicit local roles, bounded permissions, exact-scope principal/actor assignments, and separation rules into an `access_directory` projection; passwords, legacy super-user privilege, and real source role rows remain pending because those tables are absent from the fixture. |
| `ep_project`, `proj_lifecycle_*` | Project master and lifecycle stages | `operations/project` + `migration/erp` + `cmd/promote` | Ordered lifecycle and scoped transitions implemented; the real fixture promotes 2 project masters and 2 lifecycle cohorts with explicit source-stage mappings, replaying current stages as development/design while retaining historical status/progress as typed evidence. |
| `proj_lifecycle_instance` | Historical lifecycle-stage instances and progress | `migration/erp` + `cmd/promote` + `persistence/store` | All 14 source instances are preserved as `typed_evidence` lifecycle history; only the explicitly mapped current stage is target-owned project state. Historical status/progress cannot bypass the local lifecycle invariant. |
| `proj_lifecycle_stage` | Lifecycle-stage catalog evidence | `migration/erp` + `cmd/promote` + `persistence/store` | Seven source catalog rows are preserved as typed evidence; target lifecycle semantics remain governed by the explicit stage map. |
| project and task-plan snapshots | Project persistence | `operations/project` + `persistence/store` | Lifecycle, task, dependency, planned-cost, and progress snapshots serialize as revisioned projections. |
| `jd_task`, `jd_task_report` | Project plan, task dependencies, and progress | `operations/project` + `operations/delivery` + `migration/erp` + `cmd/promote` | The real fixture promotes 7/2 dependency-ordered task structures; all 9 source task snapshots and the report are also preserved as typed evidence. Clean `proj-0002` replays 2 states, while two `proj-0001` child states remain quarantined because their parent is still in progress; the separate task-state evidence cohort durably preserves that exception without target mutation. |
| `jd_task` task-state exception | Observed dependency conflict evidence | `scripts/erp_task_state_promotion_plan.py` + `scripts/erp_task_state_exception_review.py` + `cmd/task_state_evidence` + `persistence/store` | One undecided `proj-0001` exception becomes a `project_task_state_observation` projection containing all observed rows and exact parent conflicts. `decision_required=true` and `target_state_mutated=false`; owner repair or acceptance remains separate. |
| `jd_task_report` | Task progress report evidence and draft delivery intake | `operations/delivery` + `migration/erp` + `cmd/delivery_progress` + `cmd/delivery_recognition` + `persistence/store` | One redacted report remains a `typed_evidence` projection and, only with an explicit project/principal/value/evidence map, becomes one `Draft` `progress_report` projection. A separate reviewed acceptance cohort can create a pending-posting `delivery_recognition` projection with acceptance evidence; posting, cash, tax, and task-state mutation remain separate. |
| Reconciled domain sections | Consolidated management/reporting control totals | `finance/reconciliation` + `finance/reporting` + `cmd/consolidated_report` + `persistence/store` | Balanced section reports sharing one currency and source snapshot combine into one `consolidated_report` projection with section totals and explicit non-posting cash/period/tax controls. |
| `proj_progress`, `proj_output` | Evidence-backed progress and delivery acceptance | `operations/delivery` | Progress submission/acceptance and deliverable remediation states implemented. |
| progress/deliverable snapshots | Delivery persistence | `operations/delivery` + `persistence/store` | Accepted value/progress and evidence-linked deliverables serialize as revisioned projections. |
| accepted delivery progress | Cost, revenue, and contract-asset recognition boundary | `operations/delivery` + `finance/cost` + `finance/accounting` | Accepted evidence-backed progress feeds the project cost forecast and can construct a balanced source-to-journal recognition event; posting, cash, tax, and revenue policy remain separate. |
| `wf_process_def`, `wf_step_def`, `wf_process_instance` | Configurable approval/workflow | `operations/workflow` + `migration/erp` + `cmd/promote` | Process definitions, weighted decisions, step authority, replay guards, and revisioned durable projections implemented; the actual fixture promotes 2 definitions/12 steps only with explicit step-to-capability maps. Workflow instances remain empty in the fixture. |
| `wf_step_assignee` | Workflow assignment configuration | `operations/workflow` + `foundation/access` + `scripts/erp_workflow_assignment_plan.py` + `cmd/workflow_assignment` + `persistence/store` | Six assignee rows now migrate through explicit user/process/scope/capability mappings into immutable `workflow_assignment` projections; native promotion validates typed `attach_assignment` process/step evidence, while assignments remain separate from authority and approval. Delegated decisions retain effective-window/revocation and delegation-ID evidence, and SLA policies retain due/overdue observation evidence, through the workflow boundary. |
| `cb_contract` | Commercial commitment | `operations/commitment` + `migration/erp` | Commitment state machine implemented; promotion requires explicit principal, project-scope, counterparty, and amount-bounded authority mappings. A separate reviewed accounting-link plan can persist source-to-journal identity without posting cash. |
| commitment snapshots and transition events | `operations/commitment` + `persistence/store` | Revisioned JSON aggregate projections with source-event anchors implemented; recognition-event adapter is implemented, while wider aggregate persistence remains pending. |
| `srm_provider`, `srm_provider_bu` | Supplier master, qualification, blacklist | `operations/procurement` + `scripts/company_postgres_service.py` | Supplier identity, review, qualification, suspension, and blacklist controls implemented; the reviewed procurement cohort now persists qualified supplier projections with exact parity/replay, and `/srm/providers` reads those candidates through PostgreSQL. Supplier creation/review/blacklist commands and real supplier rows remain pending. |
| `tender_plan`, `tender_award` | Tender planning, bidding, and award | `operations/procurement` + `scripts/company_postgres_service.py` | Planning → publishing → bidding → award → completion flow with qualified-supplier and duplicate-bid guards; the reviewed procurement cohort persists bid/award evidence and a separate performed commitment without settlement. The Rabbita `/tender` route now reads PostgreSQL tender projections and drives local planning/publish/open-bidding/cancel commands; award remains gated on supplier qualification and matching bid evidence. |
| supplier/tender snapshots and bid events | Procurement persistence | `operations/procurement` + `persistence/store` | Qualification and award snapshots serialize supplier/evaluation/bid evidence for reconciliation; an awarded tender now crosses into a draft commitment only through separate procurement and commitment authority grants. |
| `cb_contract_milestone` | Time/progress/event obligation | `operations/contract` | Milestone trigger, eligibility, achievement, payment, overdue, and cancellation states implemented. |
| milestone snapshots and payment events | Contract milestone persistence | `operations/contract` + `persistence/store` | Plan/actual amounts, triggers, and reached/paid state serialize as revisioned projections. |
| `cb_htfkplan`, `cb_htfk_apply` | Payment plan and application | `operations/contract` + `operations/settlement` + `migration/erp` + `cmd/promote` | The real fixture promotes 4 planned milestones and 3 requested settlements after an explicit two-contract performed-state replay; reached milestones retain their ID on requested settlements and on separate immutable projections, approval/payment flags remain evidence, and release plus accounting-event links require separate target authority. |
| Reviewed contract milestone/settlement cohort | Performed contract → reached milestone → requested settlement | `scripts/erp_contract_milestone_plan.py` + `cmd/contract_milestone` + `operations/contract` + `operations/settlement` + `persistence/store` | One reviewed commitment drives a progress milestone through `eligible` and `reached`; a separate settlement retains the milestone ID and remains `requested`. Exact SQLite/PostgreSQL parity and zero-insert replay pass for commitment, milestone, and settlement projections. Approval, release, cash, accounting, tax, and period close remain separate. |
| `cb_cost`, `cb_subject_dict`, CBS versions | Dynamic/project cost | `finance/cost` + `finance/cbs` + `migration/erp` | `B = D + E + F + G` deterministic calculation and target/commitment/actual/progress forecast implemented; the reviewed fixture maps all 7 non-empty `cb_cost` rows to explicit active/frozen CBS subjects with durable projections, and an opt-in budget plan now records subject-scoped reservation/consumption evidence without posting. Broader schema coverage remains pending. |
| dynamic-cost and forecast snapshots | Cost persistence | `finance/cost` + `persistence/store` | Component totals, progress, forecast-at-completion, and signed variance serialize as revisioned projections. |
| CBS subject/version snapshots | Cost structure persistence | `finance/cbs` + `cmd/cbs_link` + `cmd/cbs_budget` + `persistence/store` | Hierarchical subjects, targets, totals, version state, reviewed source-to-subject links, and separate budget-ledger projections serialize with source identity; accounting posting and cash release remain separate. |
| budget checks and reservations | Budget availability and consumption | `finance` + `operations/commitment` | Reservation, consumption, release, and explicit commitment link implemented. |
| `vcb_expense`, `cb_expense_split` | Expense and multidimensional allocation | `operations/expense` | Allocation, approval, advance offsetting, durable projection, and balanced recognition journal implemented. |
| expense snapshots and recognition events | Expense persistence/accounting | `operations/expense` + `persistence/store` + `finance/accounting` | Allocations, offsets, approval state, balanced recognition journal, and source-to-journal event adapter serialize for reconciliation. |
| `vcb_loan_simple` | Employee advance/loan | `finance/employee_finance` + `migration/erp` | Open, partial, full repayment, scoped offset, and durable projection implemented; promotion requires explicit principal/employee scope mappings and amount-bounded creation authority. |
| `cb_loan_offset` | Employee advance repayment/expense offset | `finance/employee_finance` + `migration/erp` + `cmd/promote` | Separate offset plan requires explicit advance, principal, employee, currency, scope, and amount mapping; native import mutates only an imported advance balance and rejects unknown/over-limit offsets. |
| employee advance snapshots | Employee-finance persistence | `finance/employee_finance` + `persistence/store` | Advance and repayment balances serialize as revisioned projections; opening advance-to-cash and separate expense-to-advance accounting-event adapters are implemented, while cash posting and subledger reconciliation remain pending. |
| Reviewed employee expense/advance-offset cohort | Approved allocated expense with bounded advance offset | `scripts/erp_expense_advance_cohort_plan.py` + `cmd/expense_advance_cohort` + `operations/expense` + `finance/employee_finance` + `persistence/store` | One reviewed advance, approved expense claim, and separate offset persist as three projections with exact SQLite/PostgreSQL parity and zero-insert replay. The offset changes only the advance balance; cash, accounting, tax, and period close remain separate. |
| Employee advance/offset accounting-link cohort | Advance issuance and expense-offset journal traceability | `scripts/company_expense_advance_accounting_rehearsal.sh` + `scripts/company_postgres_accounting_reconciliation.py` + `scripts/fixtures/expense_advance_accounting_link_mapping.example.json` + `cmd/accounting_link` | A separate reviewed map binds only the advance issuance and offset identities to two explicit journals with exact SQLite/PostgreSQL identity parity, zero-insert replay, and source-to-durable reconciliation. The expense recognition event is intentionally not linked here, avoiding duplicate expense recognition; book posting, cash, tax, and period close remain separate. |
| sales customer/subscription/contract routes | Sales agreement lifecycle | `operations/sales` | Reserve/sign/fulfill lifecycle implemented. |
| `sale_customer`, `sale_subscription`, `sale_mortgage`, `sale_refund` | Customer, reservation, mortgage, and refund controls | `operations/sales` | Customer identity, reservation conversion, mortgage approval/release, and refund approval/payment implemented; fulfilled sales agreements can now open customer receivables through a separate authority boundary. |
| `mkt_campaign`, `mkt_placement`, `mkt_channel`, `mkt_material` | Marketing planning and spend | `operations/marketing` + `cmd/marketing_cohort` | The reviewed marketing cohort persists one bounded campaign, one placed allocation, and channel/material catalog evidence with exact SQLite/PostgreSQL parity and replay; provider calls, budget-ledger consumption, cash, accounting, attribution, and real source acceptance remain separate. |
| `sys_warning`, warning rules/scans/tickets | Warnings and exception ownership | `intelligence/warning` + `cmd/warning` + `scripts/erp_warning_plan.py` + `persistence/store` | Deterministic cost-overrun finding and scoped acknowledge/resolve/suppress lifecycle are source-bound into immutable `warning_finding` projections; the available `cb_cost` fixture now derives one explicit leaf-row scan, while scheduled scans and ticket persistence remain pending. |
| `sys_message`, `sys_email_outbox` | Company-owned notification intent and delivery evidence | `intelligence/notification` + `cmd/notification` + `persistence/store` | Reviewed source events map to an authority-checked, idempotent `notification_outbox` lifecycle with in-app/email/webhook intent and provider evidence fields. The available snapshot has no source rows; real provider delivery, consent, retry policy, and workflow effects remain separate gates. |
| `sale_revenue` | Customer receivable/revenue schedule | `finance/receivable` | Open/partial/collected balance, explicit opening receivable-to-revenue recognition, and separately identified cash-collection source-to-journal events are implemented; revenue policy and cash release remain pending. |
| ERP sales runtime routes | Authenticated sales/receivables read boundary and local lifecycle commands | `scripts/company_postgres_service.py` + `scripts/company_postgres_read_model_server.py` + `frontend/main` | PostgreSQL reads now cover customers, reservations, agreements, mortgages, refunds, revenue evidence, and receivables; local commands retain idempotency, immutable revisions, and audit receipts. Imported rows remain read-only and browser/production identity acceptance remains pending. |
| ERP delivery/progress runtime routes | Project progress, output value, and task-report runtime | `operations/delivery` + `operations/project` + `scripts/company_postgres_service.py` + `frontend/main` | Native progress/deliverable state machines and draft/recognition cohorts are tested. The local PostgreSQL service/read-model adapter and Rabbita `/project/progress` and `/project-plan` now expose source-preserving task/report reads plus evidence-gated progress/output/task-report commands with idempotent replay. Imported rows remain read-only; the available export has no `proj_progress`/`proj_output` rows, and browser production-identity acceptance plus owner sign-off remain pending. Keep acceptance, output confirmation, cost, recognition, cash, tax, and close separate. See `docs/ERP_DELIVERY_RUNTIME_AUDIT.md`. |
| ERP core reporting runtime routes | Cost, contract-payment, supplier, approval, and project-stage reports | `finance/reporting` + `scripts/company_postgres_service.py` + `scripts/company_postgres_read_model_server.py` + `frontend/main` | Five fixed PostgreSQL report reads and `/api/company/reports/overview` now preserve source-table coverage and feed the Rabbita `/reports` page. Current cost/contract/stage rows are imported; supplier and approval results remain empty where the export lacks provider/workflow rows. Templates, share links, browser production identity, and report-owner reconciliation remain open. See `docs/ERP_REPORT_RUNTIME_AUDIT.md`. |
| reviewed sales lifecycle cohort | Customer, subscription, contract, mortgage, refund, receivable, and revenue evidence | `operations/sales` + `finance/receivable` + `cmd/sales_cohort` | One synthetic customer, converted subscription, fulfilled agreement, opened receivable, released mortgage lifecycle, paid refund workflow, and source-evidence-only revenue row pass exact SQLite/PostgreSQL parity and replay across seven projections; collection, refund cash, revenue recognition, accounting posting, and period close remain separate. |
| receivable snapshots and collection events | Customer receivable persistence | `finance/receivable` + `persistence/store` + `finance/accounting` | Revisioned snapshots serialize open/collected balances for reconciliation; reviewed collection events carry explicit cash/receivable postings without releasing cash or posting the book; revenue recognition policy remains pending. |
| invoice routes and invoice tables | Invoice acceptance and payment | `operations/invoice` | Issue/accept/void/payment states implemented; an accepted invoice can open a customer receivable through a separate invoice-recognition grant. |
| invoice snapshots and payment events | Invoice persistence | `operations/invoice` + `persistence/store` | Revisioned snapshots serialize invoice state and paid totals; accepted invoice-to-receivable flows retain separate source-linked invoice and receivable projections. |
| contract payable and supplier settlement rows | Supplier obligation subledger | `finance/payable` | Open, partial/full payment, overpayment, and void controls plus explicit opening expense-to-payable and separately identified payment cash-settlement event adapters implemented; cash release and persistent posting remain pending. |
| payable snapshots and payment events | Supplier payable persistence | `finance/payable` + `persistence/store` + `finance/accounting` | Revisioned snapshots serialize open/paid/voided balances for reconciliation; reviewed payment events carry explicit payable/cash postings without releasing cash or posting the book; persistent posting remains pending. |
| tax configuration and filing routes | Tax determination and filing | `finance/tax` | Rate-based obligation calculation and review/file/pay/void lifecycle plus separate period/authority-referenced filing preparation/submission/acceptance implemented; reviewed obligations now emit a balanced tax-expense/tax-payable source-to-journal link without posting; external filing adapters remain pending. |
| tax obligation/filing snapshots | Tax persistence | `finance/tax` + `cmd/tax_filing` + `persistence/store` | Jurisdiction, category, rates, calculated/withheld amounts, obligation state, separate tax-filing state, period, and authority reference serialize as reviewed `tax_filing` projections with exact parity/replay; payment and ledger posting remain separate. |
| bank/cash and reconciliation routes | Cash position and controlled movement | `finance/treasury` + `finance/reconciliation` | Account balance, approved release, overdraw protection, expected-versus-actual journal checks, bank-statement line import/matching, and separate line-to-ledger-event traceability implemented; external bank adapters remain pending. |
| cash account/movement/statement snapshots | Treasury persistence | `finance/treasury` + `persistence/store` | Balances, movement direction, release/reconciliation state, statement lines, balance controls, line-to-movement matches, and line-to-accounting-event matches serialize as revisioned projections. |
| `fund_plan`, `fund_dispatch`, loan/facility routes | Treasury plan, dispatch, and corporate financing | `finance/treasury` + `finance/financing` + `cmd/treasury_plan_dispatch` | Cash plan confirmation/actualization, controlled project dispatch, and facility approval/draw/interest/repayment controls implemented; reviewed treasury plan/dispatch receipts now pass exact SQLite/PostgreSQL parity and replay, while draw/repayment actions emit explicit balanced source-to-journal links without posting; lender statements and covenant persistence pending. |
| financing facility snapshots | Financing persistence | `finance/financing` + `cmd/financing_facility` + `persistence/store` | Facility limits, draw, outstanding principal, rate, repayment state, lifecycle events, and reviewed interest evidence serialize as revisioned projections with exact SQLite/PostgreSQL parity and replay; lender/cash/accounting effects remain separate. |
| chart-of-accounts, journal, period-close routes | Accounting books and close control | `finance/accounting` + `finance/reconciliation` + `cmd/accounting_post` | Account/currency validation, open/soft-close/close periods, native balanced ledger posting, reviewed source-linked posting projections, and `close_reconciled` control implemented; the period-close artifact binds reconciliations to one source snapshot with a deterministic evidence hash; opening balances, subsidiary links, statement import, tax/cash effects, and financial statements remain pending. |
| asset/register/depreciation routes | Asset ownership and depreciation/disposal | `finance/assets` + `cmd/asset_lifecycle` | Capitalization, activation, impairment/disposal, residual-value controls, deterministic depreciation, balanced depreciation/derecognition journals, reviewed lifecycle receipts, and exact SQLite/PostgreSQL asset parity/replay are implemented; journal posting, period-close integration, and production asset-import cohorts remain pending. |
| operational accounting event hooks | Source-to-journal traceability | `finance/accounting` | Validated source/journal links and duplicate event/source replay protection implemented. |
| durable accounting-event links | Source-to-journal persistence | `finance/accounting` + `persistence/store` + `scripts/company_sqlite_accounting_link_apply.py` + `scripts/company_postgres_accounting_link_apply.py` | Native balanced-journal link receipts are persisted transactionally with event/source/journal uniqueness, migration receipt state `AccountingLinked`, integrity verification, and idempotent replay in both SQLite and PostgreSQL; a separate reviewed posting plan now calls `AccountingBook.post` and persists `accounting_posting` projections, while opening balances, external settlement, tax/cash effects, and period close remain separate. |
| `audit_log`, `sys_error_log`, attachments | Evidence and administrative trace | `foundation/evidence` + `migration/erp` + `cmd/promote` | The fixture promotes 2 explicitly mapped audit records with actor-scoped append grants; network fields remain redacted, while error taxonomy and durable blob storage remain pending. |
| `my_biz_param_option`, `vys_proceeding` | Configurable parameter and expense-proceeding catalogs | `foundation` + `migration/erp` + `cmd/promote` | The fixture promotes 2 dictionaries/8 options under explicit authority: the original 5-option `cost_subject` dictionary and an explicit 3-option `expense_proceeding` catalog. Values remain opaque; manager/department/cost metadata, CBS/accounting meaning, and expense state are not inferred. |
| `vys_proceeding` | Expense/proceeding catalog evidence | `migration/erp` + `cmd/promote` + `persistence/store` | Three redacted proceeding rows are preserved as typed evidence; no expense policy or accounting subject is inferred. |
| `tzsy_*` investment model | Investment assumptions and scenarios | `investment/model` + `investment/domain` + `investment/analytics` + `investment/portfolio` + `cmd/investment_benchmark` + `cmd/investment_performance` + `cmd/investment_valuation` + `cmd/investment_model_eval` + `migration/erp` + `cmd/promote` | The real fixture promotes 1 version/26 indexes under explicit authority, preserves source value representations, and now evaluates numeric/date values, three parent totals, and four known ratio derivations into a source-bound analytics-only projection; the reviewed performance cohort also persists bounded portfolio attribution and external benchmark reconciliation, and the separate valuation cohort binds one explicit mark-to-market event through accounting-link identity checks, while source-feed acceptance, richer formula vocabulary, and full accounting remain pending. |
| investment mandate/proposal/position/model snapshots | Investment persistence | `investment/model` + `investment/domain` + `investment/portfolio` + `persistence/store` | Model versions/indexes, source-bound evaluation metrics, mandate limits, deterministic Moonfish analysis, proposal state, positions, shock stress evidence, per-position period performance, source-bound external benchmark reconciliation, acquisition links, and explicit gain/loss valuation event links serialize as revisioned evidence; full investment accounting remains pending. |
| Moonfish deterministic tools | Market evidence and analysis | `investment/analytics` | Moving-average/trend seed implemented; full package absorption pending. |

## Current vertical scenarios

### Contract to payment

```text
cb_contract
  -> Commitment::new
  -> commitment:submit
  -> commitment:approve
  -> commitment:perform
  -> Settlement::request
  -> settlement:approve
  -> settlement:release
  -> payable/cash JournalEntry
```

Covered by the commitment and settlement tests. Budget reservation and
recognition journal are separate explicit events so an implementation cannot
silently equate commitment, performance, payment, and accounting.

The executable CLI also demonstrates the migration side of the boundary:
validated manifest -> canonical source/target envelope -> atomic record-store
append.

### Supplier to contract milestone

```text
srm_provider
  -> Supplier::new
  -> submit review
  -> qualified
tender_plan + tender_award
  -> TenderPlan::new
  -> publish -> bidding
  -> qualified supplier bid
  -> award
cb_contract_milestone
  -> ContractMilestone::new
  -> eligible -> reached -> paid/overdue
```

Covered by procurement and contract-milestone tests. The next integration step
is to persist the award-to-commitment link and reconcile source milestone
amounts with payment applications and payables. The reviewed contract
milestone/settlement cohort now proves that target lifecycle link without
claiming settlement approval, cash, or accounting effects.

### Project and dynamic cost

```text
ep_project + lifecycle stages
  -> Project::new
  -> Project::advance

cost components D/E/F/G
  -> CostBreakdown::total_minor
  -> DynamicCost::total_minor (B)
```

Covered by project lifecycle and cost invariant tests. The next step is attaching
CBS subjects, budgets, progress, commitments, and actuals to a persistent project
aggregate.

### Sales to collection

```text
sales customer/agreement
  -> SalesAgreement::new
  -> reserve -> sign -> fulfill
  -> Receivable::open
  -> partial collection
  -> complete collection
```

The target currently keeps sales agreement, invoice, and receivable as distinct
types. This preserves the ERP's operational distinctions. A fulfilled sales
agreement now opens a receivable through separate authority grants. Opening
receivables emit a validated source-to-journal link. An accepted invoice now
has the same explicit recognition boundary, with the invoice ID retained as the
receivable source. Collection cash, revenue policy, and tax events remain
separate accounting decisions.

### Investment analysis to controlled position

```text
market closes
  -> investment/analytics deterministic report
  -> InvestmentMandate::propose
  -> attach analysis -> submit -> approve
  -> execute under local authority
  -> InvestmentPosition
```

Covered by investment-domain tests. The proposal path is deliberately local and
does not give Moonfish or MoonClaw direct execution authority; portfolio
valuation and shock-risk evidence are implemented locally, and explicit
gain/loss valuation links now preserve mark-to-market accounting evidence;
external benchmark observations can be reconciled as source-bound analytics
evidence; full investment accounting and accepted production feeds remain
future parity work.

## Legacy migration rules

1. Preserve every source primary key in a migration-reference field or mapping.
2. Do not infer accounting opening balances from operational rows without an
   approved opening-balance process.
3. Do not dual-write the same business aggregate during cutover.
4. Convert money to fixed-point minor units using an explicit currency and
   rounding policy.
5. Convert soft-deleted and voided records into explicit target lifecycle states.
6. Quarantine records that fail target invariants; never silently coerce them.
7. Keep source attachments, audit entries, and migration decisions searchable.
8. Reconcile counts and totals by entity, project, counterparty, account, period,
   currency, and source module.

## Immediate mapping backlog

- extract a sanitized schema snapshot and route inventory from the ERP;
- extend executable fixtures to split expenses, loans, invoices, workflow cases, and supplier risk history;
- map `wf_*` approval definitions into a target workflow aggregate;
- map CBS subject/version/R0 records into persistent target cost structures;
- persist tender-award → commitment and milestone → payment-application links;
- attach source supplier signature-check/rescore evidence to the derived risk
  read model and obtain owner approval for the procurement cohort;
- translate expenses, loan offsetting, and employee finance;
- map invoice, receivable collection, tax, and journal events without double
  recognition (opening receivable/payable links are already explicit);
- import investment Excel fixtures and compare deterministic analytics;
- produce migration fixtures and reconciliation reports for each source-to-target
  vertical scenario.
