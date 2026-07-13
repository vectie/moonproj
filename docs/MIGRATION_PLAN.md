# ERP-to-Company-Product Migration Plan

Status: active strangler-migration plan; no cutover authorized  
Recorded: 2026-07-14
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
page-by-page UI parity, runtime API/command wiring, and source-backed golden
workflows. The existing technical gates will be reused and extended only when
they protect one of those functional slices; additional standalone hardening
is not the current priority. The current fixture also proves
two balanced commitment links plus one employee-advance opening source-to-
journal link, transactionally persisted and idempotently replayed; they are
traceability receipts, not cash release or accounting-book posting.
The quarantined project-1 task-state exception is now also translated into one
durable `project_task_state_observation` projection on SQLite/PostgreSQL. It
retains every observed task row and exact dependency conflict, but leaves
`decision_required=true` and `target_state_mutated=false`; the named owner
decision remains a later gate.
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
preserved without becoming business state, and one quarantined project-1
task-state observation plus one source-bound investment evaluation, bringing
the typed-cohort total to 76 projections.
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
The reviewed accounting-posting cohort now sits explicitly after the
accounting-link receipt. A chart/period map must name the book, principal,
scope, accounts, and exact linked event IDs; `cmd/accounting_post` then calls
the native `AccountingBook.post` gate and persists two source-bound commitment
journal projections in the current rehearsal. SQLite/PostgreSQL parity and
zero-insert replay pass, while opening balances, broader source journals, tax,
cash settlement, period close, and production ownership remain separate gates.
The opening-control boundary now provides the next explicit gate: a reviewed
map compiles through native `migration/control`, preserves five synthetic
control candidates with exact tolerances and units, and passes SQLite and
PostgreSQL parity plus zero-insert replay. This proves the reconciliation
mechanism, not a production opening position. The real opening workbook,
finance-owner approval, entity/book/currency dimensions, and any subsequent
opening journal or subledger events remain required before accounting opening
state can be accepted.
The reviewed tax-filing boundary now supplies a separate institutional gate:
two synthetic obligations run through native calculation, review, filing
submission, and accepted/rejected outcomes with exact SQLite/PostgreSQL parity
and zero-insert replay. The cohort does not pay tax, post a tax journal, or
call an external authority. The available ERP snapshot has no tax rows, so a
sanitized tax export, source-to-obligation identity map, filing credentials,
finance-owner acceptance, and payment/ledger policy are still required.
The reviewed bank-statement boundary now imports one balanced synthetic
statement with two lines through native treasury validation and exact
SQLite/PostgreSQL parity plus zero-insert replay. It is evidence-only:
movement matching, statement-to-ledger reconciliation, cash release, bank
provider access, and accounting posting remain separate decisions. The
available ERP snapshot has no bank-statement rows, so production statement
export and owner acceptance remain open.
The reviewed financing-facility boundary now preserves one synthetic corporate
facility through native approval, activation, draw, repayment, and interest
accrual, with exact SQLite/PostgreSQL parity and zero-insert replay. It is
debt evidence only: lender calls, cash disbursement or settlement, accounting
posting, tax treatment, covenant tracking, and period close remain separate.
The available ERP snapshot has no financing-facility rows, so a sanitized
facility export, lender/principal identity map, finance-owner review, and
production debt policy are still required.
The reviewed asset-lifecycle boundary now preserves one synthetic fixed asset
through capitalization, activation, two depreciation periods, and disposal,
including exact depreciation/disposal journal validation and SQLite/PostgreSQL
parity with zero-insert replay. It is register and accounting evidence only:
journal posting, disposal cash settlement, tax basis, period close, and owner
acceptance remain separate. The available ERP snapshot has no asset rows, so a
sanitized register export, legal-owner map, account policy, and finance-owner
review are still required.
The reviewed treasury-plan boundary now preserves two synthetic cash plans and
one inter-project dispatch through native confirmation, actualization,
approval, and execution, with exact SQLite/PostgreSQL parity and zero-insert
replay. It is liquidity-intent evidence only: bank movement, cash release,
settlement, accounting/tax treatment, period close, and owner acceptance remain
separate. The available ERP snapshot has no `fund_plan` or `fund_dispatch` rows,
so a sanitized treasury export, project-scope map, and finance-owner review are
still required.
The reviewed invoice/subledger boundary now preserves two synthetic customer
invoices with their receivables and one supplier payable through native issue,
accept, collection, and payment controls. Exact SQLite/PostgreSQL parity and
zero-insert replay pass for five projections. It is subledger evidence only:
cash release, revenue/expense posting, tax settlement, period close, and owner
acceptance remain separate. The available snapshot has no accepted invoice
rows, so a redacted invoice map and finance-owner review are still required.
The reviewed procurement boundary now preserves two synthetic qualified
suppliers, one two-bid tender, and its performed commitment through separate
native authority checks. Exact SQLite/PostgreSQL parity and zero-insert replay
pass for four projections. It is obligation evidence only: cash release,
accounting posting, settlement, tax, period close, and owner acceptance remain
separate. The available snapshot has no supplier or tender rows, so a redacted
procurement export and business-owner review are still required.
The reviewed sales/receivables cohort now exercises one synthetic customer,
subscription conversion, fulfilled sales agreement, opened receivable,
mortgage lifecycle, refund approval/payment workflow, and source-evidence-only
revenue row. Exact SQLite/PostgreSQL projection parity and zero-insert replay
pass for seven projections. Collection, refund cash, revenue recognition,
accounting posting, period close, and owner acceptance remain separate; the
available snapshot has no accepted sales rows.
The reviewed marketing cohort now exercises one bounded campaign, one placed
channel allocation, and two catalog-evidence rows for channel/material data.
Exact SQLite/PostgreSQL projection parity and zero-insert replay pass for four
projections. Provider calls, budget-ledger consumption, cash release,
accounting posting, attribution policy, and owner acceptance remain separate;
the available snapshot has no accepted marketing rows.
The reviewed contract-milestone cohort now closes the lifecycle boundary left
by the typed payment promotion: one performed commitment drives a progress
milestone through eligible and reached, and that reached milestone creates a
requested settlement retaining its milestone ID. Exact SQLite/PostgreSQL
projection parity and zero-insert replay pass for three projections. Settlement
approval/release, cash movement, accounting posting, tax, period close, and
owner acceptance remain separate; the available source export is not complete
enough to claim production settlement rows.
The reviewed employee expense/advance-offset cohort now keeps an employee
advance, an approved allocated expense, and a separate bounded offset as three
identities. Exact SQLite/PostgreSQL projection parity and zero-insert replay
pass; the offset changes only the advance balance, while expense recognition,
cash settlement, accounting posting, tax, period close, and owner acceptance
remain separate. The available snapshot has no accepted expense rows.
The follow-on `scripts/company_expense_advance_accounting_rehearsal.sh` is
intentionally separate from that projection cohort. Its reviewed map binds
only advance issuance and advance-offset identities to explicit journals; it
does not link the expense claim because the offset journal already carries the
expense debit. Two links pass native validation, exact SQLite/PostgreSQL
identity parity, and zero-insert replay without posting the book, releasing
cash, or closing a period.
The same rehearsal emits backend-specific accounting reconciliation reports,
checking source identity, principal, amount, currency, event, and journal
continuity on both SQLite and PostgreSQL before the evidence can feed a
period-close control.
The close-control compiler deduplicates matching SQLite/PostgreSQL reports by
source snapshot and mapping identity, so backend verification strengthens the
evidence without inflating the economic link count.
The separate invoice/procurement accounting-link boundary now binds two
receivable openings, one payable opening, and one performed procurement
commitment through target-specific reviewed keys. Exact SQLite/PostgreSQL
identity parity and zero-insert replay pass for all four links. It remains
traceability evidence only: collection/payment cash, accounting-book posting,
tax settlement, period close, and owner acceptance remain separate. Production
invoice, payable, receivable, supplier, and tender exports are still required.
The separate reviewed tax/financing accounting-link boundary now binds two
tax-obligation recognition events plus one financing draw and one repayment
event through native event builders and explicit source-to-journal maps. Exact
SQLite/PostgreSQL identity parity and zero-insert replay pass for all four
links. Tax filing/payment, lender calls, cash release, accounting-book posting,
period close, and owner acceptance remain separate; the available ERP snapshot
has no accepted tax-obligation or financing-facility rows.
The reviewed investment-performance boundary now preserves one bounded
portfolio with two positions, explicit quote valuation, period return, and an
external benchmark observation through native mandate and analytics checks.
Exact SQLite/PostgreSQL parity and zero-insert replay pass for three
projections. It is analytics evidence only: position mutation, cash release,
accounting posting, period close, and owner acceptance remain separate. A real
source feed and investment-owner review are still required.
The separate reviewed investment-valuation boundary now reuses that bounded
portfolio and creates one explicit native mark-to-market accounting event. The
event is then bound through a separately reviewed accounting-link map; exact
SQLite/PostgreSQL identity parity and zero-insert replay pass for one link.
It remains traceability evidence only: the accounting book is not posted, cash
is not released, positions are not mutated, and period close is not authorized.
The available snapshot has no accepted valuation rows, so a real valuation feed,
policy, and investment-owner review remain required.
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
The PostgreSQL rehearsal now emits a cross-domain projection-parity report that
compares every supplied domain receipt’s source identity and canonical payload
between the isolated SQLite rehearsal and PostgreSQL; this is evidence of
target agreement, not an ownership or cutover authorization.
The first schema-only wave now has an explicit six-table target/security map.
Because the available snapshot has zero rows for `foundation-security`, this
artifact records semantic ownership and exclusion rules only; it does not
pretend that the wave has been imported.

### Current findings and revised execution order

The current repository is a verified migration foundation, not a clean
replacement of `erp_new`. The findings that now control sequencing are:

**Source-data checkpoint (2026-07-13).** The available
`../erp/erp_new/backup/erp-v0.1.0-snapshot.db` was inspected against the source
loan routes, workflow engine, and MySQL initializer. It contains one
`vcb_loan_simple` row and one `cb_loan_offset` row, but zero
`wf_process_instance` rows and zero `wf_step_action` rows. The source schema
defines `srm_provider` and `srm_category`, but those tables are absent from the
backup. The one loan row also has no `process_instance_guid`. The configured
live MySQL endpoint remains unavailable, so this backup is still the only
credential-safe source payload. Consequently, workflow approval/synchronization
and supplier-backed reporting cannot be reconciled from the available data.
Do not seed approval, supplier, or risk state locally; obtain a complete
redacted export (or an owner-approved empty-data disposition) before claiming
those capabilities as source parity.

1. **Visual UI port, not final UI parity.** Rabbita has the source login,
   navigation, dashboard, major route families, and representative forms, but
   many views are fixture-backed/read-only and no page-by-page screenshot,
   interaction, or route-action comparison has been accepted.
2. **Connected local slices, not accepted production workflows.** The local
   PostgreSQL service and Rabbita gateway now exercise bounded expense,
   contract, payment-application, procurement, sales/receivables, invoice,
   core-report, and employee-loan read/command slices. Procurement covers supplier
   lifecycle/risk reads, tender planning/award, and contract splits; sales
   covers customer, reservation, agreement, mortgage, refund, receivable, and
   revenue evidence reads; employee loans preserve source balances and offset
   evidence, and now expose local create/submit/bounded-offset/draft-update/
   void commands with native employee-scoped authority evidence, idempotent
   receipts, immutable revisions, and audit evidence. Workflow synchronization
   remains gated because the source backup has zero process-instance/action
   rows and the source loan has no process-instance identity. This is still local-only
   evidence: the gateway session and actor assertion are not the production
   identity boundary, and no browser acceptance or named-owner sign-off has
   been recorded.
3. **Delivery is locally connected but not source-complete or accepted.** The
   target `operations/delivery` package, PostgreSQL service/read-model routes,
   and Rabbita `/project/progress` and `/project-plan` states now cover
   source-preserving task/report reads plus evidence-gated progress/output/
   task-report commands. Smoke evidence covers transitions and idempotent
   replay. The available export still has no `proj_progress` or `proj_output`
   rows, and production identity, browser acceptance, and named operations
   ownership remain open. Task-state, output confirmation, recognition, cash,
   tax, and close remain separate gates. See
   [`ERP_DELIVERY_RUNTIME_AUDIT.md`](ERP_DELIVERY_RUNTIME_AUDIT.md).
   Project master/detail reads now preserve the two available projects and
   lifecycle/task evidence through `/projects`; project and plan mutations
   remain separate and source-owner acceptance is still open. Source-compatible
   project-plan task/detail/summary reads now preserve seven tasks, one report,
   and five key nodes without enabling task mutations. See
   [`ERP_PROJECT_RUNTIME_AUDIT.md`](ERP_PROJECT_RUNTIME_AUDIT.md).
   The source MDM business-unit tree is also connected as a read-only
   hierarchy (seven imported rows); legal-principal ownership and organization
   mutations remain gated. See [`ERP_MDM_RUNTIME_AUDIT.md`](ERP_MDM_RUNTIME_AUDIT.md).
   The available budget dictionaries are now source-compatible reads as well
   (five cost-subject options and three proceedings); expense and dictionary
   writes remain gated. See [`ERP_BUDGET_RUNTIME_AUDIT.md`](ERP_BUDGET_RUNTIME_AUDIT.md).
   Investment feasibility reads are also connected for the available cohort
   (one version, 26 indices, five dimensions, and profit summary); import,
   activation, valuation, cash, accounting, and tax remain gated. See
   [`ERP_INVESTMENT_RUNTIME_AUDIT.md`](ERP_INVESTMENT_RUNTIME_AUDIT.md).
   The source-compatible dynamic-cost read is now connected as a separate
   cost slice: Rabbita `/dynamic-cost` loads all seven imported `cb_cost` rows,
   preserves the source A/B/C/D/E/F/G/H formula, and reports the imported
   summary and coverage. This does not make the broader cost dashboard
   complete: `/cost-dashboard-v3` still needs the source
   `investment/projects/:projGuid/profit-actual-v2` hierarchy, CBS version
   selection, and the missing budget/expense/change tables before it can be
   promoted beyond the designer fixture. See
   [`ERP_DYNAMIC_COST_RUNTIME_AUDIT.md`](ERP_DYNAMIC_COST_RUNTIME_AUDIT.md).
   Admin dictionary, bounded quality, audit, health, user-roster, and
   imported-profile reads are connected
   for the available governance rows (one group, five options, twelve quality
   rules with four unavailable dependencies, five imported users, two audit
   events, 29 health-table coverage rows, and an empty BPM pool); super-user
   scope, writes, role tables, retention, source completeness, and
   security-owner acceptance remain gated. See
   [`ERP_ADMIN_RUNTIME_AUDIT.md`](ERP_ADMIN_RUNTIME_AUDIT.md).
4. **Reporting is locally connected but source-incomplete and not accepted.**
   The five core report reads now run through the local PostgreSQL service,
   read-model adapter, and Rabbita `/reports` overview. Cost, contract, and
   project-stage rows are populated from source raw tables; supplier and
   approval sections correctly remain empty because the backup has no provider
   tables and zero workflow-instance/action rows. Templates, share links, production
   identity, browser acceptance, and report-owner reconciliation remain open.
   See [`ERP_REPORT_RUNTIME_AUDIT.md`](ERP_REPORT_RUNTIME_AUDIT.md).
4a. **The dashboard/cockpit now has a bounded v1 read slice, but is not
   accepted parity.** The source cockpit exposes seven GET handlers (overview,
   funnel, top anomalies, project KPI/anomalies, and v2/v3 group views) over
   30 unique tables. The target now exposes the first five as authenticated
   source-backed reads, and Rabbita loads the group overview, funnel, and
   anomaly rows while preserving the designer layout. Only 14 of the 30
   dependencies are present in the controlled export; 16 cross-domain tables
   needed by v2/v3 sales, funds, invoices, tenders, warnings, and CBS views
   are absent. Every response reports source coverage and missing tables; no
   synthetic revenue, cash, health, warning, or risk values are introduced.
   Production identity, browser scope acceptance, and v2/v3 source coverage
   remain open. Report reads do not constitute cockpit parity. See
   ERP_DASHBOARD_RUNTIME_AUDIT.md.
5. **Partial source, not full ERP data.** The authoritative ERP inventory is
   75 tables and 30 route files with 338 handlers; the controlled export has
   only 26 tables and 120 rows. The remaining 49 tables require a real
   credential-safe export before production migration claims can be made. In
   particular, the missing supplier tables and empty workflow tables are data
   availability gates, not permission to manufacture target rows.
6. **Technical safety is ahead of functional acceptance.** Local PostgreSQL
   parity, replay, backup/restore, and cutover evidence pass for supplied
   cohorts, but managed deployment, business acceptance, shadow operation, and
   ownership transfer remain open.

The source-to-target runtime inventory is now explicit: the ERP contains 56
browser routes, 338 API handlers, and 182 mutation handlers. The target matrix
currently records 31 connected browser states, 23 fixture-backed browser
states, no browser states classified as read-model-only, and two public
states. Its API matrix records 31 connected API groups and 25 fixture/no-source
groups across MDM
organization/project, budget dictionary, investment,
admin governance, dynamic cost, expense, contract, payment, procurement,
sales, invoice, delivery, dashboard v1, core reports, employee-loan, and
workflow-definition reads; the three dashboard aliases now represent the
bounded source-backed v1 read, while `/cost-dashboard-v3` remains in the
fixture-backed set because its source hierarchy is not yet available in
PostgreSQL. The remaining browser views and API groups are explicitly tracked
as fixture, public, or not-connected rather than counted as parity. Workflow definitions are
connected only as non-authorizing reads; instance/task actions remain gated. That gap,
rather than additional platform hardening, controls the next work.

Execute the remainder in this order:

1. Build on `docs/ERP_UI_PARITY_MATRIX.md` / `.json`, the source-to-target
   page/route/action parity matrix and finish the visual/interaction comparison
   for every ERP route family. Record each route as `matched`, `intentionally
   changed`, `blocked by missing source`, or `not implemented`; do not call the
   UI complete from screenshots of only the dashboard.
2. Obtain and validate the missing 49-table credential-safe MySQL/JSON export
   before opening another broad surface. The export must include empty tables,
   primary-key metadata, hashes, redaction results, and an owner-approved
   disposition for any still-empty workflow or supplier tables. Do not promote
   or fabricate approval, supplier, or risk rows from the current backup.
3. Close the procurement acceptance gap after the source-data decision.
   The local supplier lifecycle/risk reads, tender planning/award/complete,
   and contract-split reads/creates now pass PostgreSQL smoke and Rabbita
   command-state checks. Remaining procurement work is the source signature-
   check and external risk-rescore integration (or an owner-approved derived
   replacement), a redacted source export, supplier identity mapping, browser
   acceptance, award-to-commitment acceptance, and procurement-owner sign-off.
   Imported rows remain read-only and no award creates a commitment implicitly.
4. Treat the employee-loan command boundary as a finance-owner acceptance
   slice: verify authority grants, applicant ownership, replay/conflict
   behavior, bounded offset projections, and imported-row read-only behavior.
   Do not enable workflow synchronization until source `wf_process_instance`
   and `wf_step_action` rows, state mapping, and a named workflow owner are
   available. The Rabbita loan
   editor now emits the local create/submit/update/void commands; browser
   acceptance through production identity remains open.
5. Replace the local session/actor adapter with the reviewed production
   identity, token issuer, rotation, persistence, deployment, and rollback
   boundary for every connected slice. Browser acceptance must exercise the
   real gateway session and visible durable state changes.
6. Finish delivery/progress acceptance before opening another broad surface.
   The local PostgreSQL reads, evidence- and authority-checked
   progress/output/task-report commands, gateway forwarding, and Rabbita
   `/project/progress` and `/project-plan` states now work and pass smoke/replay.
   Obtain source `proj_progress`/`proj_output` rows (or an owner-approved
   redacted cohort), run browser acceptance through the production identity
   boundary, and obtain operations-owner approval for task-state conflicts.
   Keep the existing designer layout, but do not count local synthetic rows as
   source import parity. Recognition, budget/cost, cash, tax, and period-close
   effects remain separate gates.
7. Finish report acceptance and then expand runtime vertical slices to the ERP
   parity floor. The five core report reads and `/reports` overview now work;
   obtain the missing supplier/workflow source rows (or owner-approved redacted
   cohort), run browser/report-owner reconciliation, and keep templates/share
   links separate. Synthetic rehearsals remain design evidence until real
   source rows and user acceptance are attached. See
   `docs/ERP_REPORT_RUNTIME_AUDIT.md`.
8. Accept the connected dynamic-cost slice through production identity and
   finance-owner reconciliation, then treat `/cost-dashboard-v3` as a separate
   dependency wave. Implement its read adapter only after the source
   `profit-actual-v2`, CBS version, budget, expense, and change-table exports
   are present (or explicitly dispositioned); do not fill the missing hierarchy
   with dashboard fixtures and do not call the v3 screen parity complete.
9. Accept the bounded dashboard gate in
   `docs/ERP_DASHBOARD_RUNTIME_AUDIT.md`
   through production identity, entity scope, and operations/finance KPI
   reconciliation. Then obtain the missing sales/fund/invoice/tender/warning/
   CBS tables (or owner-approved dispositions) before implementing v2/v3.
   Do not treat `/api/company/summary`, report reads, or the offline fixture
   fallback as cockpit parity.
10. Run named-owner acceptance and a read-only shadow period for each accepted
   wave; only then approve managed production deployment, rollback, and
   ownership transfer. Keep the existing parity/cutover gates as evidence
   controls, not as substitutes for functional work.

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

## 9. Initial program actions (historical baseline)

The actions below record how the program was originally started. They are
retained as an audit trail; execution now follows **Current findings and
revised execution order** above, with functional UI/API parity ahead of
additional standalone hardening.

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
