# ERP-to-Company-Product Migration Plan

Status: active strangler-migration plan; no cutover authorized  
Recorded: 2026-07-15
Source: working site ERP in `../erp/erp_new`  
Target: standalone company product in this repository

## 1. Objective

Build and adopt a standalone company operating system that preserves the broad
operational capability of the current ERP and adds complete institutional,
accounting, treasury, financing, tax, and investment models.

The program must protect the working site. The current ERP remains authoritative
until an explicitly named capability passes specification, parity, migration,
shadow, operational, user-acceptance, and rollback gates.

## 1a. Runtime language constraint (2026-07-15)

The company product target is pure MoonBit plus shell orchestration. MoonBit
owns the domain packages, PostgreSQL adapter, authenticated HTTP service,
gateway/session boundary, migration commands, and Rabbita frontend. Shell
scripts may compose compiled MoonBit commands, set environment/credentials,
start local processes, and run external PostgreSQL operational tools; they must
not contain business rules or replace the product runtime.

Python is not part of the target architecture or active migration execution.
The existing Python migration rehearsals, PostgreSQL service, gateway, source
probes, and smoke tests are frozen historical/comparison artifacts only. Do not
import or execute them. Implement MoonBit equivalents behind the same
contracts, and compare their receipts, response envelopes, authorization, and
replay behavior against immutable fixtures or previously recorded evidence.
There is no dual-runtime shadow phase. No new Python runtime surface may be
added, and Python must be removed from the supported build, test, deployment,
and browser-start paths before production identity is enabled.

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
schema-only tables requiring later cohorts. The 2026-07-14 audit has now
completed the bounded page-by-page sidebar/read wave, connected the
evidence-ready PostgreSQL service/read-model paths, and verified local command
runtimes through expense, contract, and payment-application lifecycles. The
next hard gates are managed
production identity, the complete credential-safe source export, source-backed
golden workflows, and named-owner acceptance of the remaining external effects.
The existing technical gates will be reused and extended only when they
protect one of those functional slices; additional standalone hardening is not
the current priority. The current fixture also proves
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

**Production gate audit (2026-07-14).** The credential-free deployment
manifest validates as PostgreSQL-only with a bounded pool, verified TLS,
cross-region backup/restore, rollback, and observability requirements, but its
authoritative result is `ready_for_owner_review` with all three approval roles
missing: `finance`, `operations`, and `security`. The companion service gate
is `ready_for_service_review`, exposes only the fixed read-model allow-list,
has no mutation endpoints or arbitrary SQL, and remains deployment- and
identity-gated. No DSN, password, or provider credential is copied into this
repository or used to claim production readiness.
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

**Migration-plan checkpoint (2026-07-14).** The source snapshot was re-counted
with `scripts/erp_snapshot_inventory.sh` and still hashes to
`4ff5dd0ad0b75c6cfc572f99047fe41c5df4b8c48d3877f707fe063aec7dea03`: 26 tables
and 120 rows. The current empty-data boundaries are now explicit: expense
tables (`vcb_expense`, `cb_expense_detail`, `cb_expense_split`) and workflow
instance/action tables contain zero rows, while supplier tables
(`srm_provider`, `srm_category`) are absent from the snapshot. The target
parity register currently records 56 browser routes and 338 source API
handlers (182 mutations), with 54 connected browser states, 0
fixture-backed read-only states, 2 public states, and all 156 source GET/HEAD
handlers connected through reads or explicit safety boundaries. The newly connected
AI analytics, AI Hub observation, webhook configuration, report-builder, and cost-dashboard read families are
included in those counts; their source tables are currently empty and are not
treated as provider, draft, notification, or report-template authority.

The source-handler action register now marks the ERP `GET /srm/providers` and
`GET /srm/providers/:guid` reads as connected through separate
`/api/company/srm/providers[/{guid}]` boundaries; the supplier statistics
overview is connected through `/api/company/srm/stats/overview` as well, and
the provider risk-detail read is connected through
`/api/company/srm/providers/<guid>/risk`.
The ERP supplier mutation handlers are now implemented in the native MoonBit
service as bounded source aliases: `POST
/api/company/source/srm/providers` and `PATCH`, `PUT`, or `DELETE`
`/api/company/source/srm/providers/<guid>` translate provider fields into
idempotent command-owned supplier projections. Direct supplier create and
`update`, `submit_review`, `review`, `blacklist`, and `void` commands use the
same PostgreSQL receipt/audit/revision boundary. Source-shaped list/detail
readback merges those projections with explicit `source_kind=command`, while
imported providers remain read-only; populated-source qualification,
signature, risk rescore, and external provider effects remain gated.
The supplier signature-check handler now has a source-compatible missing-
provider boundary and an explicit populated-provider procurement gate. A
command-owned supplier projection also returns a `derived_command_preview`
with local risk derivation, but it is non-authorizing, non-persistent, and
does not invoke a provider. The
admin backup handler now has a PostgreSQL target-format export boundary; it
does not invoke the source MySQL dump process or return binary data.
The route-level count now includes the connected `/srm/providers/:guid`
source-detail read; the list remains a connected command-form page with a
separate source master read.

The source reconciliation inventory is now observable at
`/api/company/source/migration/schema-coverage`. It reports the hash-bound
75-table schema, 26-table rehearsal snapshot, 49 schema-only tables, per-table
raw-envelope counts, and explicit `source_export_incomplete`,
`promotion_authorized=false`, and `cutover_authorized=false` state. This makes
the remaining export gap measurable from the PostgreSQL service without
fabricating empty rows or treating the rehearsal snapshot as complete. The
Rabbita System Health page now renders the same scope evidence, so operators
can see the migration boundary without leaving the company product.

The marketing action register is now split by ownership rather than flattened
into a generic read-only status. All thirteen source marketing handlers have a
target boundary: the four GET families preserve imported coverage, while the
four POST families plus campaign update/delete, placement effect, channel
delete, and material delete persist local command projections through the
PostgreSQL service and trusted gateway. Service and gateway smoke evidence
covers campaign create/replay/update/delete, placement create/effect, channel
create/delete, and material create/delete. This closes only the local command
boundary; it does not claim provider calls, budget reservation, CBS spend,
accounting/tax posting, attribution, or production identity.

The latest bounded target reads are now part of the execution baseline, but
not accepted production behavior: `/profile` reads the imported user and
initiated documents; `/expenses` and `/expenses/:guid` read the source
`vcb_expense`/detail/split family; `/dynamic-cost` reads all seven `cb_cost`
rows using the source formula; and `/cost-dashboard-v3` reads the source
CBS/version hierarchy with truthful zero-row coverage when those tables are
absent. Local expense/loan commands and the designer fallback remain separate
from those source reads. This changes the
next step from “add another screen” to “accept the connected batch through the
real identity boundary and named owners, then obtain the missing export before
opening broad fixture-backed surfaces.”

The supplier provider list is now an additional bounded source read:
`/srm/providers` loads `/api/company/srm/providers`, which reproduces the ERP
provider-list shape from imported `srm_provider`, `srm_provider_bu`,
`srm_category`, and related contract envelopes. The detail read also returns
linked business units and historical contract evidence. The statistics read
also reproduces enabled-provider, rating/source, category, and top-business
aggregates. These reads return source coverage and `authorizing=false`; the
source list/statistics remain empty and detail returns a covered 404 when the
imported source supplier table is absent. Provider command aliases are merged
into list/detail only as command-owned, source-shaped projections; they do not
turn into imported `srm_provider` rows. The local `/api/company/suppliers`
command projection remains the authority boundary for supplier lifecycle
commands. The supplier risk board is
now an additional bounded source read: `/srm/risk-board`
uses the ERP risk calculation over imported `srm_provider`, `cb_contract`, and
`cb_contract_milestone` envelopes, returns source coverage, and explicitly
marks the response non-authorizing. With the current snapshot it returns zero
risk rows because the supplier and milestone tables are unavailable; the
provider detail now has the same bounded per-provider risk read, returning
score/rating/tags and contract/overdue counts from imported rows without
creating a qualification decision. The existing local supplier
projection/risk endpoint remains separate.

The cashflow route is now a connected finance read family: `/cashflow` loads
`/api/company/cashflow/forecast` plus the source inflow summary, while the
authenticated service/read-model adapter exposes `/forecast-v3`,
`/forecast/detail`, `/inflow`, `/net`, and `/gap-alert` for drill-downs. The
reads reproduce ERP payment-plan/application, expense/loan, revenue,
milestone, and v3 CBS semantics from imported envelopes and carry explicit
coverage; empty source tables contribute zero rather than fixture cash. This
is read-only liquidity evidence. A signed `/api/company/cashflow/ai-explain`
candidate (and `/source` alias) now produces a deterministic native summary of
supplied series/gap evidence; it never calls a provider, persists prompts, or
creates cash/accounting/tax effects. Cash release, accounting, tax, bank
settlement, provider-backed explanation, browser production identity, and
finance-owner acceptance remain separate gates.

CBS is the next connected finance master-data family. The service and
read-model adapter now expose source-compatible R master, dictionary,
F-balance, version/compare, R0 queue, approval-rule, change, and source
contract reads under `/api/company/cbs/*`; Rabbita `/cbs/dict`, `/cbs/versions`,
`/cbs/r0-queue`, and `/cbs/approval-config` consume the dictionary/R0 read and
show source provenance. The controlled export has two unclassified contracts
but no CBS dictionary/version/rule rows, so empty and covered-not-found states
are preserved. CBS writes, budget reservation, accounting, cash, tax,
production identity, and owner acceptance remain gates.

The next CBS command checkpoint is now native as well. Signed
`POST /api/company/cbs/approval-rules` plus `PUT`/`DELETE` on a rule GUID
persist a local approval-configuration projection with immutable revisions,
audit receipts, request-equal idempotent replay, imported-row protection, and
merged list/pick readback. The pick surface chooses the highest configured
threshold at or below the requested amount. This slice is deliberately
configuration-only: it does not authorize a business action, synchronize
workflow steps, reserve or consume budget, or create cash/accounting/tax
effects. A source-backed shell smoke covers create, replay, list, pick, update,
and tombstone behavior; populated-source authorization and workflow ownership
remain separate migration gates.

Fund planning is now a connected read-and-local-command family after CBS:
`/fund/plan` loads source-compatible project/period plans, gap analysis, and
dispatch evidence from `/api/company/fund/{plans,gap-analysis,dispatches}`.
The current export has no fund rows, so planned cash, gaps, and dispatches are
shown as empty source state instead of designer numbers after a successful
read. PostgreSQL now owns bounded plan create/update/delete and dispatch
create/approve projections with signed actor/capability/scope checks,
idempotent receipts, aggregate revisions, audit events, and source-shaped
`sourceKind=command` readback. Imported rows remain read-only and every local
result is explicitly cash/accounting/tax-neutral. Browser finance-owner
acceptance, production identity, cash release, settlement, accounting, tax,
and owner acceptance remain gates.

The warning center is now an observed source-quality read family with a bounded
state-command overlay. `/warning` and `/warning-rules` load
`/api/company/warning/badge`, the filtered list, and rule summaries; scans,
custom rules, templates, and tickets remain explicit empty reads because their
source tables are absent. The current export yields one deterministic W005
observation from project/cost evidence. Imported findings stay read-only;
resolve/ignore writes only a `warning_state` command projection, idempotency
receipt, and audit event, with no notification, ticket, provider, cash,
accounting, or tax effect. Production identity, browser interaction, warning
owner acceptance, rule configuration, scans, notifications, and tickets remain
gates.

The custom-rule preview gap is now closed as a native candidate. Signed
super-user `POST /api/company/warning/custom-rules/preview` (and `/source`)
accepts only a single read-only SELECT/WITH template, returns a source-shaped
empty result plus a digest, and explicitly does not execute SQL or persist
findings. The warning smoke covers valid and rejected templates; browser
warning-owner acceptance and any real query execution remain gated.

The attachment center now has a bounded source-metadata read family. `/attachments`
loads `/api/company/attachments/all` and `/api/company/attachments/stats`, with
`/list` available for business-linked evidence queries. The adapter reports
`attachment`/`sys_user` coverage, counts, AI metadata, and an explicit
`binary_storage=not_imported`/`downloadable=false` boundary. The current
PostgreSQL export has no attachment rows, so the screen shows an empty source
state after a successful read rather than designer files. Upload, binary
download now has a source-compatible missing-record boundary, while real
binary serving, deletion, OCR re-extraction, production identity, and owner
acceptance remain separate gates. Signed `POST /api/company/attachments/re-extract/:guid`
and `/source` now preserve the source missing-record response and expose a
dry-run OCR candidate for imported rows; no binary is read, no OCR provider is
called, and no attachment metadata is persisted. Signed upload and delete
routes now return explicit object-store candidates without consuming multipart
bytes or deleting binaries. Provider-backed extraction, binary ownership, and
attachment-owner acceptance remain gates.

**AI explanation candidate checkpoint (2026-07-16).** Native MoonBit now
translates the source cashflow and investment `POST /ai-explain` handlers behind
the signed PostgreSQL service. Cashflow explanations summarize supplied series
and gap evidence; investment explanations summarize the current imported
version/profit read model. Both preserve a source-compatible envelope and
explicitly report `provider_execution=false`, `persisted=false`, and
`authorizing=false`; the dedicated shell smoke proves the live PostgreSQL
boundary. This is an analytics candidate only: no LLM/provider call, prompt
retention, financial mutation, browser action, or owner authorization is
enabled. Browser/finance-owner acceptance and any provider integration remain
open migration gates.

**Investment Excel index-upsert checkpoint (2026-07-16).** Native MoonBit now
translates the source `POST /excel-imports/:importGuid/index-upsert` handler
and its `/source` alias as a signed, PostgreSQL-backed dry-run candidate. The
default response preserves the imported preview plan and adds `dryRun`,
`force`, `wouldInsert`, and `wouldUpdate` markers; a missing import keeps the
source 404. `dryRun=false` returns an explicit investment-owner acceptance
gate, so no Excel index is inserted or updated and no audit/provider/cash,
accounting, or tax effect occurs. Browser acceptance, workbook data, formula
reconciliation, and the durable upsert transaction remain open.

The adjacent source `POST /excel-imports/:importGuid/plan-lines/import` handler
now has the same native treatment. Default dry-run responses preserve the
source summary and expose `replaceExisting`, `inserted`, `replaced`, and
`wouldInsert`; `dryRun=false` is rejected until an investment owner accepts
the durable line write/replace transaction. Missing imports retain the source
404 and no provider, audit, financial, or tax effect is created.

The subject-mapping `PUT /projects/:projGuid/subject-mappings` mutation is
also exposed as a signed dry-run candidate. It validates a non-empty `items`
array, returns the existing grouped mapping observation plus `wouldUpdate`,
and rejects `dryRun=false` until an investment owner accepts mapping writes.

The `PUT /plan-lines/:lineGuid` edit route is now also a signed native
dry-run candidate. It validates source status values, preserves the missing
line boundary, returns the current row plus the requested patch, and rejects
non-dry-run edits until an investment owner accepts imported plan-line
mutation.

The workbook upload route now reports an explicit signed binary boundary: the
native service does not accept multipart content, parse XLSX bytes, or persist
an import. This keeps the source route visible while reserving parser,
workbook ownership, and investment-owner acceptance for a separate gate.

The marketing screen is now a bounded source/read-command family. `/marketing`
loads `/api/company/marketing/{campaigns,placements,channels,materials}` with
project/state filters and explicit source-table coverage. Imported source rows
remain read-only; local campaign, placement, channel, and material commands are
authority-bound, idempotent, PostgreSQL-owned projections with audit receipts,
and their source-shaped readback is marked `sourceKind=command`. The current
export has no marketing rows, so source coverage remains empty while local
commands stay visibly separate from imported ERP data. Provider execution,
CBS/spend consumption, accounting/tax, attribution, production identity, and
owner acceptance remain gates.

The invoice action register now has a bounded local command boundary alongside
the source reads. `POST /api/company/source/invoice/in` and `/out` register
authority-checked PostgreSQL projections with deterministic invoice identity,
tax-amount calculation, idempotent receipts, aggregate revisions, and audit
events; the matching `DELETE` paths tombstone only local projections. The
source-shaped invoice reads and monthly tax ledger merge those command rows as
`sourceKind=command` while preserving imported coverage separately. OCR and
verification, tax filing, accounting posting, cash settlement, production
identity, and finance-owner acceptance remain gates.

The delivery action register now reflects the runtime already present in the
PostgreSQL service: source progress creation/reporting and output
creation/confirmation map to evidence-gated, authority-checked local commands
with idempotent receipts, immutable revisions, and audit events. The source
progress delete handler now maps to a local tombstone command: it can delete
only command-owned progress projections, records the reason and audit receipt,
and filters the tombstone from subsequent reads; imported observations remain
read-only. Source-row coverage, browser acceptance, and operations-owner
approval remain open.

**Delivery tombstone checkpoint (2026-07-14).** The command-owned progress
delete boundary is now verified end to end. The service smoke creates a local
progress projection, deletes it with an idempotency key, replays the same
request, and confirms the tombstone is absent from the progress readback; the
trusted gateway smoke repeats the same boundary through the Rabbita-facing
gateway. Shell-only native gateway/source-read smoke, `moon test` (252
portable / 261 native tests), and the route-parity regeneration all pass. This
closes only local progress
projection deletion: imported ERP progress remains immutable, and delivery
recognition, workflow, cash, accounting, tax, production identity, browser
interaction, and operations-owner acceptance remain gated.

The sales action register now maps source-equivalent customer create/update,
subscription create/convert, mortgage create/approve/release, refund
create/approve, and revenue create/update/confirm/delete actions to PostgreSQL
command runtimes. Revenue commands require an explicit authority grant,
idempotency key, and actor/scope match; their source-shaped readback is marked
`source_kind=command`, and deletion only tombstones local projections. Customer
destructive deletion remains gated in favor of an explicit archive command.
Cash release, accounting/tax effects, source identity mapping, browser
acceptance, and sales/finance-owner approval remain open.

The expense action register now maps source-equivalent create, draft update,
submit-for-approval, reject, resubmit, approve, and draft/rejected void
actions to the native MoonBit PostgreSQL expense command runtime. The native
service also serves the imported expense list/detail and calculation-only
budget preview; `scripts/company_postgres_expense_smoke.sh` proves replay and
the full local lifecycle. The service preserves the source alias, requires
the actor assertion to match the local applicant for update/void, and keeps
imported source rows, workflow synchronization, budget checks, cash,
accounting, tax, and finance-owner acceptance separate.

The contract action register now maps source-field create, draft/submitted
update, submit, reject, resubmit, approve, and void aliases to the native
MoonBit PostgreSQL contract command runtime. The native service preserves
BU/project/provider/amount/CBS fields, source-shaped readback, deterministic
idempotency, aggregate revisions, and audit receipts; imported contracts remain
read-only and void is a local tombstone. The shell-only
`scripts/company_postgres_contract_smoke.sh` and native gateway smoke prove
replay, the full local lifecycle, signed forwarding, and tombstone readback.
CBS/budget enforcement, payment execution, cash, accounting, tax, production
identity, and contract-owner acceptance remain separate gates.

The budget action register now maps `POST /api/company/budget-check` to a
PostgreSQL-backed, source-shaped headroom preview. It reads imported `cb_cost`
rows, reports target/used/remain and over-budget indicators, and explicitly
marks the response calculation-only, non-authorizing, non-persisting, and
non-consuming. No receipt, reservation, auto-offset, workflow transition,
cash movement, accounting entry, or tax effect is created; production
identity and finance-owner browser acceptance remain open.

The fund action register now maps plan create/update/delete and dispatch
create/approve to the local PostgreSQL planning command runtime. Each command
is authority-checked, idempotent, revisioned, and audited; imported
`fund_plan`/`fund_dispatch` rows remain immutable source evidence, while local
projections are merged into the source-shaped reads with explicit command
provenance. The command boundary does not reserve budget, release cash, post
accounting, calculate/file tax, or synchronize workflow. Browser interaction,
production identity, and finance-owner acceptance remain open.

The project-plan action register now maps task create/update/delete and task
report to a PostgreSQL-owned planning boundary. Imported `jd_task` rows remain
read-only; local task projections require project-scoped authority,
deterministic idempotency, immutable revisions, and audit receipts, while task
reports require explicit evidence and never mutate the imported task or
trigger workflow, cash, accounting, or tax. Signed `/api/company/plan/ai-suggest-plan`
and `/source` now return a deterministic seven-node schedule candidate with
calculated end dates; no LLM/provider call, plan persistence, or task mutation
is performed. Provider execution and browser/operations-owner acceptance remain
open.

**Tender mutation audit checkpoint (2026-07-14).** The target has a verified
local tender command runtime for planning-draft creation and the forward-only
`planning -> publishing -> bidding -> awarded -> completed` state machine,
plus cancellation. It requires idempotency, immutable revisions, audit
receipts, qualified-supplier and matching-bid evidence for award, and has no
implicit cash, accounting, tax, or settlement effect. Source-field create and
split aliases are now implemented at `/api/company/source/tender/tenders` and
`/api/company/source/tender/splits`; they return source-shaped responses,
merge command projections into source-shaped reads with provenance, and pass
service/gateway replay smoke. `DELETE /tenders/:guid` now maps to an idempotent
local tombstone for command-owned tenders only; imported projections remain
read-only and disappear from target/source-shaped readback after deletion.
Source-compatible `POST /awards` and `PUT /tenders/:guid/state` aliases now
reuse the native award evidence and forward-only state graph; command-owned
awards merge into source-shaped readback. Arbitrary state overwrite, hard
delete, award-to-commitment, and production owner acceptance remain policy
gates. Service smoke covers source state/award alias replay and readback in
addition to target/source deletion and filtering.

**Contract mutation checkpoint (2026-07-14).** The source cost contract
`POST /api/company/source/cost/contracts`, `PUT .../:guid`, and `DELETE .../:guid`
handlers now translate into the native PostgreSQL contract projection. Create
preserves the ERP BU/project/provider/amount/CBS field family and requires the
source `rCode`/`l3Code` inputs; updates are
idempotent and limited to command-owned draft/submitted contracts; imported
ERP contracts remain read-only. Delete is a local tombstone, and source-shaped
contract list/readback merges command rows with explicit provenance and
no-cash/accounting/tax markers. CBS/budget enforcement, payment execution,
browser acceptance, production identity, and
operations-owner approval remain separate gates.

**MDM project mutation checkpoint (2026-07-14).** The source MDM project
`POST /api/company/source/mdm/projects`, `PUT .../:projGuid`, and
`DELETE .../:projGuid` handlers now translate into a command-owned PostgreSQL
`project` projection. Create preserves the source project identity, code/name,
business-unit scope, level, dates, status, and seven pending lifecycle stages;
update is limited to command-owned projects; and delete is a local tombstone.
Service and trusted-gateway smoke cover create/replay, source-shaped readback,
imported-project write rejection, update, and tombstone filtering. The command
does not mutate imported projects, task state, workflow, budget/CBS,
accounting, cash, or tax; browser/production identity and MDM/operations-owner
acceptance remain separate gates.

**Dynamic-cost mutation checkpoint (2026-07-14).** The source cost
`POST /api/company/cost/dynamic-cost` handler now translates cost hierarchy and
amount fields into an idempotent local `dynamic_cost_command` projection.
`PUT`/`DELETE /api/company/source/cost/dynamic-cost/:guid` update or tombstone
only command-owned rows; imported `cb_cost` rows remain read-only. The dynamic
cost read merges command rows with `sourceKind=command` and explicit
no-cash/accounting/tax markers. Remarks writes, CBS/budget ownership, browser
acceptance, production identity, and operations-owner approval remain separate
gates.

**Native dynamic-cost command checkpoint (2026-07-15).** The dynamic-cost
source command family is now implemented in the native MoonBit company service.
`POST /api/company/cost/dynamic-cost` normalizes the ERP camel-case fields into
an idempotent local `dynamic_cost_command` projection, while `PUT` and `DELETE`
source aliases update or tombstone only command-owned rows. Native validation
checks project scope, identifiers, non-negative fixed-point amounts, imported
row protection, replay request equality, immutable revisions, and audit
receipts. The source-shaped read and remarks observation merge active command
rows, and the shell-only service smoke plus native gateway smoke prove the
create/replay/update/imported-guard/void lifecycle with no budget, CBS,
accounting, cash, tax, or provider effect. Those external effects, browser
acceptance, production identity, and operations-owner approval remain separate
gates.

**Contract-milestone mutation checkpoint (2026-07-14).** The source cost
milestone family now has a bounded PostgreSQL command projection. `POST
/api/company/source/cost/contracts/:guid/milestones` translates one milestone
or a batch into immutable local projections with deterministic idempotency;
`PUT`/`DELETE /api/company/source/cost/milestones/:guid` update or tombstone
only command-owned rows; and `POST .../:guid/trigger-event` reaches pending
event milestones. Source-shaped contract detail/readback merges command
milestones with `sourceKind=command`, the early-payment check reads them, and
the native MoonBit service smoke covers replay, update, trigger, and tombstone
readback. The supported runtime is now `cmd/postgres_company_service` plus
`scripts/company_postgres_milestone_smoke.sh`; the Python implementation is
frozen comparison evidence only. Imported contracts and milestones remain
read-only, and these commands remain explicitly cash/accounting/tax-neutral;
payment release, budget/CBS enforcement, workflow-driven progress, browser
acceptance, production identity, and operations-owner approval remain separate
gates.

**Native contract-milestone command checkpoint (2026-07-15).** The native
MoonBit service now owns the source milestone aliases rather than forwarding
them to the frozen bridge. `POST /api/company/source/cost/milestones` and
`POST /api/company/source/cost/contracts/:guid/milestones` accept one or a
bounded batch, normalize fixed-point amount/percentage fields, allocate stable
sequence and identifier defaults, and persist `contract_milestone_command`
revisions with a command receipt and audit event. `PUT` updates mutable fields,
`DELETE` writes a local tombstone, and `POST .../:guid/trigger-event` reaches
only pending event nodes. The command detail read already merges the latest
imported and local projections; the new shell-only smoke proves health
capabilities, replay, source-shaped detail, update, trigger, and delete. No
cash, accounting, tax, provider, budget, or workflow effect is enabled by this
slice.

**Payment-application mutation checkpoint (2026-07-14).** The source cost
payment-application create/update/delete family now has a bounded alias over
the existing PostgreSQL payment-application projection. `POST
/api/company/source/cost/payment-applies` translates ERP camel-case fields,
creates an idempotent local draft, and submits it into the expected approval
state; `PUT` and `DELETE` aliases update or void only command-owned rows.
Source-shaped list readback merges those projections with imported applications
and carries command provenance plus explicit `cash_effect=false`,
`accounting_effect=false`, and `tax_effect=false` markers. Payment release,
imported-row edits, browser acceptance, production identity, and finance-owner
approval remain separate gates; milestone create/update/trigger/void now has
its own cash/accounting/tax-neutral checkpoint above.

**Native payment command checkpoint (2026-07-15).** The payment-application
command family is now implemented in `cmd/postgres_company_service` rather than
the frozen bridge. Native MoonBit preserves direct create/submit/reject/
resubmit/approve/update/void transitions, source-field create auto-submit,
deterministic replay, imported-row protection, immutable revisions, audit
receipts, and signed gateway forwarding. The shell-only
`scripts/company_postgres_payment_smoke.sh` proves the full local lifecycle and
no-cash/accounting/tax markers. Payment release, provider effects, production
identity, and finance-owner acceptance remain gated.

**Native invoice command checkpoint (2026-07-15).** The native MoonBit
company service now owns `POST /api/company/source/invoice/in`,
`POST /api/company/source/invoice/out`, and the matching `DELETE` tombstones.
It normalizes ERP invoice fields, calculates fixed-point tax amounts, requires
an active signed principal/scope/capability grant, rejects imported-row edits,
enforces request-equal idempotency, and persists immutable `invoice_in` or
`invoice_out` revisions with command receipts and audit events. Existing native
invoice/tax-ledger reads merge active command projections with imported rows
and omit deleted commands. `scripts/company_postgres_invoice_smoke.sh` covers
authority, fallback IDs, replay/collision, tax readback, and tombstones, while
the gateway smoke covers trusted forwarding. Tax filing, accounting posting,
cash settlement, OCR/verification, production identity, and finance-owner
acceptance remain separate gates; the Python bridge is comparison evidence
only.

**Native sales-revenue command checkpoint (2026-07-15).** The native MoonBit
company service now owns `POST /api/company/sales/revenues`, `PUT` updates,
`POST .../:id/confirm-received`, and `DELETE` tombstones for local revenue
projections. It normalizes the ERP field aliases and fixed-point amount forms,
requires an active signed principal/scope/capability grant, rejects imported
revenue mutation, enforces request-equal idempotency, preserves expected /
received transitions, and persists immutable `sale_revenue` revisions with
command receipts and audit events. The source sales read merges active command
projections with imported rows and keeps `source_kind=command`; the new
`scripts/company_postgres_sales_revenue_smoke.sh` covers authority, replay,
update, confirmation, source readback, and tombstoning, and the gateway smoke
covers trusted forwarding. Revenue recognition, collection/cash, accounting,
tax, production identity, and finance-owner acceptance remain separate gates;
the Python bridge is comparison evidence only.

**Native tender/contract-split command checkpoint (2026-07-15).** The native
MoonBit company service now owns tender planning drafts, publish/open-bidding/
award/complete/cancel/delete transitions, local contract-split creation, and
the source-field tender/split aliases. It preserves fixed-point amount and
percentage normalization, matching-bid evidence, immutable revisions, audit
receipts, request-equal replay, imported-row protection, and the existing
source-shaped tender/split response envelopes. `POST /api/company/source/
tender/tenders`, `DELETE .../tenders/:id`, and `POST .../splits` now forward
through the native gateway; the tender smoke covers lifecycle, replay, source
readback, split creation, aliases, and tombstones, while the gateway smoke
covers trusted forwarding. Award-to-commitment, arbitrary legacy state
overwrite, standalone source-award insertion, cash, accounting, tax,
production identity, and procurement-owner acceptance remain separate gates;
the Python bridge is comparison evidence only.

**Native marketing command checkpoint (2026-07-15).** The native MoonBit
company service now owns source-compatible campaign, placement, channel, and
material reads plus the bounded marketing command family. It preserves the ERP
field aliases, project/state/campaign filters, fixed-point budget/placement/
material amounts, campaign/channel joins, placement effect metrics, immutable
revisions, audit receipts, request-equal replay, imported-row protection, and
command-owned tombstones. Campaign/placement/channel/material creates,
campaign update, placement effect, and campaign/channel/material delete routes
are covered by native service, trusted gateway, source-read, and marketing
shell smoke. Provider execution, R19 budget-ledger consumption, attribution,
cash, accounting, tax, production identity, and finance-owner acceptance remain
separate gates; the Python bridge is comparison evidence only.

**Native fund plan/dispatch command checkpoint (2026-07-15).** The native
MoonBit company service now owns source-compatible fund plans, period gap
analysis, and dispatch observations, plus local plan create/update/delete and
dispatch create/approve commands. It preserves project/period/direction
filters, imported project identity checks, fixed-point amounts, creator/state
guards, immutable revisions, audit receipts, request-equal replay, imported-row
protection, and explicit cash/accounting/tax-neutral markers. Native service,
trusted gateway, source-read, and fund shell smokes cover the plan and dispatch
lifecycles. Bank settlement, cash release, accounting, tax, production
identity, browser acceptance, and finance-owner approval remain separate gates;
the Python bridge is comparison evidence only.

**Native delivery/progress command checkpoint (2026-07-15).** The native
MoonBit company service now serves merged `/api/company/delivery/{progress,
outputs,tasks,task-reports,plan-summary,overview}` reads alongside the
source-only progress/output observations. Progress create/report/accept/reject/
delete, output create/confirm, and evidence-gated task-report commands persist
idempotent PostgreSQL receipts, immutable revisions, and audit events while
remaining delivery/cash/accounting/tax neutral; imported ERP rows remain
read-only. Native service, delivery, source-read, and trusted-gateway shell
smokes cover replay, state transitions, merged readback, and tombstoning. A
credential-safe source `proj_progress`/`proj_output` cohort, browser acceptance,
production identity, and operations-owner approval remain separate gates; the
Python bridge is comparison evidence only.

**Native project-plan task checkpoint (2026-07-15).** The compiled MoonBit
company service now owns the source-compatible project master/detail, lifecycle,
task list/detail, key-node summary, and delay-impact reads. It also owns local
project-plan task create/update/delete projections and the evidence-gated
`/api/company/plan/tasks/:guid/report` alias. Imported `ep_project`, lifecycle,
`jd_task`, and `jd_task_report` rows remain read-only; local commands require a
signed actor, project-scoped capability, deterministic idempotency, immutable
revisions, and audit receipts, with workflow, delivery, cash, accounting, and
tax effects explicitly false. `scripts/company_postgres_project_plan_smoke.sh`,
the source-read smoke, and trusted-gateway smoke run the native path using
shell orchestration only. Browser production-identity acceptance, evidence
capture in the full designer flow, source promotion, AI scheduling, and
operations-owner approval remain separate gates; the Python bridge is frozen
comparison evidence only. The project-plan smoke also proves the deterministic
AI suggestion candidate and its explicit no-provider/no-persistence markers.

Notification is now a bounded source-read family rather than a delivery
integration. `/inbox` loads user-scoped messages and unread counts;
`/notify-config` chains subscriptions, redacted configuration status,
email-outbox metadata, digest preview/log evidence, and provider discovery.
The current export has no notification source rows, so successful reads show
explicit empty-source states while five imported users remain available for
scope coverage. Signed-user subscription create/update/delete aliases and
message read/read-all aliases now persist idempotent local projections with
source-shaped readback, tombstones, and imported-message read overlays. A
super-user, allow-listed `PUT /api/company/notify/config` candidate also
persists redacted key status and replay/audit evidence without binding
credentials or invoking providers. Imported
`sys_warning_subscription`/`sys_message` rows remain read-only and
delivery/provider/accounting/cash/tax effects remain false. Managed
credentials, delivery, digest dispatch, provider calls, consent/retry policy,
production identity, browser acceptance, and owner acceptance remain separate
gates. `scripts/company_postgres_notification_smoke.sh` proves
create/replay/list, source-alias update/delete, message read/read-all, config
candidate/replay/readback, invalid-channel rejection, secret redaction, and
PostgreSQL cleanup without Python.

The next admin read family covers OCR configuration status and error-log
metadata. `/ocr-config` loads provider definitions, current scene, and
redacted key status without invoking an OCR provider; `/error-log` loads
bounded error rows while redacting IP addresses and stack traces. The current
export has no `sys_param` or `sys_error_log` rows, so successful reads preserve
definition/empty-source states. OCR execution, configuration writes, error-log
retention, production identity, and super-user ownership remain separate gates.

AI analytics is now a source-observation family. `/ai-stats` loads
overview/activity/badge reads over confirmed AI drafts, query logs, correction
logs, workflow auto-skips, and user labels. The export has no AI analytics
rows, so successful reads show empty-source state while preserving
`authorizing=false`, `persisted=false`, and `provider_execution=false`.
LLM/OCR execution, draft promotion, workflow authority, prompt retention,
production identity, and AI-owner acceptance remain separate gates.

The AI Hub is now a separate source-observation family. `/ai-hub` loads the
source-compatible usage-stats, drafts, query-log, corrections, and
correction-stats reads through PostgreSQL. Signed `/api/company/ai-hub/explain`
and `/source` now provide a deterministic table-summary candidate with no
LLM/provider call, prompt persistence, or authority effect. The current export has no
`ai_draft`, `ai_query_log`, `ai_correction_log`, `ai_query_session`, or
`ai_query_turn` rows (and no AI confirmation audit rows), so the screen shows
explicit empty-source history and usage counts while preserving the designer
workbench. Intake, confirm, discard, natural-language query, explain, rule,
approval-draft, global-ask, query-session, and command routes remain gated;
provider/LLM/OCR execution, draft promotion, prompt retention, and AI-owner
acceptance are not inferred from a successful read. The nine mutation routes
now return a signed `ai_hub_command_candidate` gate with no request-body
consumption, provider/query execution, draft persistence, workflow authority,
or financial effect; durable AI-owner acceptance remains open.

Webhook configuration is now a bounded notification family. `/webhook-config`
loads `/api/company/webhook/config` over the three source `sys_param` platform
names, enabled flags, and redacted URL/secret status. Signed super-user
`PUT /api/company/webhook/config/:platform` (and `/source`) candidates preserve
optional URL/secret and `__keep__` semantics with idempotent redacted
projections and audit receipts; they never bind credentials or deliver.
The export has no `sys_param` rows, so successful reads show explicit
empty-source metadata while preserving `authorizing=false`,
`persisted=false`, and `provider_execution=false`. Managed credential
ownership, test delivery, overdue scans, production identity, and
notification-owner acceptance remain separate gates. The pure-shell
`scripts/company_postgres_webhook_smoke.sh` covers create/replay/update,
source aliases, redaction, invalid-platform rejection, and the dry-run
`/scan-overdue/preview` no-source contract. The preview reads imported ticket,
warning, user, and parameter evidence but never mutates tickets or invokes a
provider.

The report builder is now a bounded reporting vertical. `/report-builder` loads
the source table/column/operator whitelist and saved-template list through
`/api/company/reports/templates/meta` and `/api/company/reports/templates`. The
export has no `sys_report_template` rows, so successful reads preserve the ten
source definitions and show an explicit empty-template state. Template create
and delete now use command-owned `report_template` projections with
idempotency/audit receipts; template run validates the same whitelist and
evaluates imported JSON envelopes in memory with `sql_executed=false`. Imported
templates remain read-only and no report command changes provider, cash,
accounting, or tax state. Native `POST /api/company/export/excel` now emits a
source-compatible multi-sheet XLSX with sanitized names, bounded 20-sheet / one
million-cell / 32KB-cell limits, and a pure MoonBit ZIP/XML writer; the shell
export smoke validates headers, ZIP integrity, Unicode values, and rejection of
empty sheets. PDF export, production identity, browser acceptance, managed
serving, and report-owner approval remain separate gates.

**Next-wave source audit (2026-07-14).** The route register initially had 56
source `GET`/`HEAD` handlers that were not marked connected. After the
evidence-ready batch, the identity/RBAC observation wave, the static
import-template read, the empty-safe investment import-history read, the
dashboard/admin observation wave, and the investment Excel observation wave,
5 remain; they
are not one uniform backlog. Four
groups are now explicit:

* **Evidence-ready reads:** contract/payment/milestone reads can use the
  non-empty `cb_contract`, `cb_htfk_apply`, `cb_htfkplan`, and `cb_cost` source
  envelopes; budget scope and loan-balance reads can use the imported
  `sys_user`, `mu_business_unit`, and `vcb_loan_simple` rows. The source service,
  read-model server, Rabbita loaders, and read-only smoke now cover this batch.
  Responses preserve source-compatible shapes, report coverage, and keep
  missing `cb_contract_milestone`, empty workflow-instance/action tables, and
  empty `proj_progress`/`proj_output` tables explicit; no read grants
  authority, persistence, provider execution, or cash. The available
  investment cohort also has one current `tzsy_version` and 26
  `tzsy_plan_index` rows, so its deterministic six-case sensitivity read is
  source-backed without activating or mutating the model.
  The source `GET /import/:bizType/template` handler is also connected as an
  exact static CSV read for the `project` and `contract` templates; it does not
  import rows or authorize the corresponding commands. The authenticated
  service and read-model smoke checks verify the BOM, header order, download
  disposition, and unsupported-business-type 400 boundary.
  The investment `GET /projects/:projGuid/excel-imports` list and the detail,
  bridge, index-preview, profit-table, plan-line-preview, plan-line list,
  subject-mapping, and profit-cockpit reads now have source-preserving
  boundaries. The current export has zero `tzsy_excel_import`, sheet, profit,
  plan-line, and mapping rows, so these routes return explicit empty data or
  source-style 404s with coverage rather than showing designer workbooks. The
  profit-actual now ports the source comparison when a plan exists: imported
  receipts/payments/expenses/contracts/loans are aggregated and sparse plan
  subjects are explicitly marked simulated. The current export still returns
  the source-style missing-plan boundary, and the seeded shell smoke proves the
  successful calculation without mutating finance state.
* **Defined-but-empty or absent source reads:** workflow instance/task views
  now have an empty-safe observation adapter over defined
  `wf_process_instance`/`wf_step_action` tables, but still zero rows;
  attachment download has a source-compatible missing-binary boundary and no
  imported `attachment` rows; invoice/tax,
  tender/award/split and several investment detail tables are absent or empty
  in this snapshot. Progress/output, sales customer/subscription/contract/
  mortgage/refund/revenue, tender/award/split, and supplier categories now have
  explicit empty-safe source adapters. Supplier evaluation-result and source
  dictionaries are definition observations rather than authorizing master data;
  they currently return six and four reviewed definitions respectively. Their
  missing source rows still block promotion where applicable. The remaining
  families may only be exposed as explicit empty-source observations after an
  adapter proves the boundary; no fixture rows may fill the gap.
* **Identity/RBAC and operational reads:** preferences and role/permission
  catalogs now have fixed, non-authorizing observation adapters; the current
  export reports an empty preference table and empty role-assignment tables
  while preserving the source permission definitions. Full health, redacted
  LLM status, and no-provider AI diagnostics now have PostgreSQL observation
  adapters; runtime metrics are unavailable and provider execution remains
  disabled. Attachment binaries and PostgreSQL backup export remain gated;
  provider signature checking has a missing-provider/gated boundary and a
  command-owned derived preview, but does not authorize an imported
  populated-provider decision. None of these observations
  grants authority just because a local target endpoint exists.
* **Provider/external reads:** LLM/OCR diagnostics now expose redacted,
  no-execution metadata, but populated-provider signature decisions and
  similar status/verification endpoints remain provider and credential gates.
  A successful metadata read does not authorize a provider call.

The remaining 182 mutation API handlers are therefore deliberately split between these
bounded read candidates and mutation/provider commands. New source-compatible
reads must report coverage, preserve redaction and 404 behavior, and mark
`authorizing=false`, `persisted=false`, and `provider_execution=false` where
those fields apply. This audit changes the next implementation wave from a
route-count sweep to production-identity acceptance for the completed batch and
the missing-table export gate for the remaining candidates.

**Evidence-ready read batch checkpoint (2026-07-14).** The following source
handlers are now connected in the action register as bounded, non-authorizing
reads: cost `/contracts`, `/contracts/:guid`, `/contracts/:guid/milestones`,
`/payment-applies`, `/dynamic-cost`, `/dynamic-cost/:guid/remarks`, and
`/milestones/:guid/check` (7); attachment `/list`, `/all`, and
`/stats` (3); invoice `/in`, `/out`, and `/tax-ledger` (3); budget
`/users-in-bu` and `/my-loan-balance` (2); and workflow
`/tasks/mine`, `/tasks/initiated`, `/instances/by-biz`, `/instances/:piGuid`,
and `/tasks/my-history` (5); delivery `/progress` and `/outputs` (2); sales
`/revenues`, `/customers`, `/subscriptions`, `/contracts`, `/mortgages`, and
`/refunds` (6); tender `/tenders`, `/awards`, and `/splits` (3); supplier
dictionary `/categories`, `/dict/eval-results`, and `/dict/sources` (3); and
investment `/projects/:projGuid/sensitivity` (1). The
PostgreSQL service and
read-model adapter return the imported contract/payment rows (2 contracts,
4 plans, 3 applications), the explicit empty milestone table, four scoped
budget users, a 3,500.00 loan balance for `limingjin`, empty invoice/tax
source tables, and empty workflow
instance/action observations with a source-compatible 404 for a missing detail,
and explicit empty `proj_progress`/`proj_output`, sales-table, and tender-table
observations, plus the source investment sensitivity envelope over one version
and 26 indices.
Rabbita now loads source contracts/payment applications, renders budget scope
and balance provenance on the expense surfaces, and chains all three workflow
observation lists after the definition read. The native shell-only
`scripts/company_postgres_source_read_smoke.sh` plus the existing attachment
and dynamic-cost probes pass without mutations; the older Python source-read
smoke is comparison evidence only. The dynamic-cost remark
observation preserves the imported `CB-101`/`建安工程` subject and remains
non-authorizing, while the milestone early-payment check preserves a covered
404 for the currently empty `cb_contract_milestone` table. Supplier category
reads preserve
the empty `srm_category` coverage, while evaluation-result and source dictionary
reads expose six and four reviewed, non-authorizing definitions respectively;
they do not imply that source master rows are present or writable. Investment
sensitivity exposes six deterministic scenarios and remains analytics-only;
it does not activate a version, call a provider, or write finance state.
These are still local evidence: production identity, browser acceptance, named
owner reconciliation, and the missing 49-table export remain open.

The native MoonBit service now also owns the source-shaped contract/payment
observation boundary (`/api/company/source/cost/contracts[/{id}[/milestones]]`
and `/api/company/source/cost/payment-applies`). Imported rows, command
projection merge, source coverage, URL-decoded filters, detail plans/applies,
and the empty milestone response are parsed-equal to the frozen Python bridge
on the live PostgreSQL target. This removes Python from the supported runtime
path for this vertical; Python is retained only as historical comparison
evidence until the remaining service/gateway surfaces are ported.

The same native service now owns `/api/company/source/budget/users-in-bu` and
`/api/company/source/budget/my-loan-balance`, including hierarchical BU/department
scope, explicit user resolution, loan-state filtering, coverage, and the
non-authorizing scope markers. The four-user BU scope and 3,500.00 loan
observation are parsed-equal to the bridge and covered by the shell-only smoke.
Workflow task/instance observations are now native as well: pending,
initiated, history, business-instance lookup, and instance detail preserve the
empty `wf_process_instance`/`wf_step_action` boundary, explicit scope, and
source-compatible 404/null behavior without enabling approval or assignment.
The native service also owns the dynamic-cost read and source remark boundary,
including the seven-row A/B/C/D/E/F/G/H calculation, command projection merge,
rounded summary metrics, and missing-subject 404. These are read-only and do
not reserve budget, mutate CBS, post accounting, release cash, or write tax.
Delivery progress/output observations are native too, with project/period/state
filters and explicit empty `proj_progress`/`proj_output` coverage; they remain
read-only and separate from local delivery command projections.

Receivable and invoice observations are now native as well. The MoonBit service
serves `/api/company/receivables[/{id}]`, `/api/company/invoices[/{id}]`,
`/api/company/source/invoice/{in,out}`, and `/tax-ledger`, preserving the ERP
projection fields, source coverage, monthly tax envelope, command provenance,
and missing-detail behavior. Live PostgreSQL responses are parsed-equal to the
frozen Python bridge, and the shell-only source-read smoke covers the whole
slice. This is still observation-only: invoice registration, OCR/verification,
tax filing, accounting, cash, and production identity remain gated.

The six ERP sales source families are native as well: customers,
subscriptions, contracts, mortgages, refunds, and revenues. Their source
filters, identity/default mapping, amount display, coverage metadata, empty
states, and command-owned revenue readback now run in MoonBit/PostgreSQL and
match the frozen bridge under the shell-only smoke. Revenue lifecycle writes,
cash/accounting/tax effects, production identity, and sales-owner acceptance
remain separate gates.

Tender-plan, tender-award, and contract-split observations are native as well.
MoonBit merges the current command-owned tender/split projections, preserves
source filters and provenance, and keeps procurement/cash/accounting/tax
effects disabled. Supplier category, evaluation-result, and source dictionaries
also run natively with explicit empty-table/definition metadata. Native
supplier/provider command replay, source readback, imported-row protection,
and lifecycle evidence are covered by the service and gateway smokes.
Populated-source signature/qualification decisions, risk rescore, provider
execution, production identity, and owner acceptance remain gated. The native
provider list/detail/risk observations preserve the active command-owned
supplier cohort, imported-row provenance, source coverage, and missing-provider
semantics.

**Native supplier/provider command checkpoint (2026-07-15).** The native
MoonBit company service now owns direct supplier create/update/submit-review/
review/blacklist/void and source-compatible provider POST/PATCH/PUT/DELETE
aliases. Each command requires a signed actor and idempotency key, validates
the ERP field family, protects imported rows, persists immutable supplier
revisions, command receipts, and audit events, and returns source-shaped
provider readback with `sourceKind=command`. Blacklist and void are local
non-authorizing lifecycle states; no provider call, qualification grant,
signature, risk rescore, budget, accounting, cash, or tax effect is implied.
`scripts/company_postgres_supplier_smoke.sh` and the gateway smoke provide the
shell-only replay/collision/update/review/blacklist/void evidence. The frozen
Python service remains comparison material only.

**Representative browser acceptance checkpoint (2026-07-14).** A local
read-model server was run against PostgreSQL with the Warren-built Rabbita
assets, and the in-app browser completed a real fixture-login and navigation
pass. The login screen accepted the documented local `admin` fixture; the
dashboard then showed the PostgreSQL read-model connection, two source-backed
projects, contract/payment KPIs, and the source-derived risk table. The same
session opened project master data (15 design rows plus the imported
PostgreSQL project evidence), project plan (7 imported tasks with explicit
zero source progress/output rows), dynamic cost (7 imported `cb_cost` rows,
including `CB-101`), and investment (26 imported indicators plus six
source-backed sensitivity cases). This validates the representative shell,
navigation expansion, loading states, provenance text, and read-only tables;
it is not yet page-by-page route acceptance or production-identity approval.

The first pass also found that the read-model server was missing the
`/api/company/projects` list/detail routes even though the service adapter and
Rabbita loader already agreed on that contract. That gap was corrected in the
read-model server and rechecked in the browser: the PostgreSQL table now shows
the two imported projects (`proj-0001` and `proj-0002`) with lifecycle and task
counts, rather than silently relying on the design snapshot.

A second navigation pass exercised the sales/customer, cost-dashboard v3,
fund-plan, invoice, expense, and employee-loan states. Each observed source
request returned successfully after the project-route fix; source-empty
families remained visibly empty (`sales`, CBS, fund, invoice, and expense),
while the existing designer rows stayed labeled as design/fixture data. The
loan view also kept imported loan evidence separate from local command rows.
This is stronger than a static render check, but it still does not authorize
mutations, reconcile fixture totals to production, or replace the required
page-by-page route and named-owner acceptance.

**Frontend/read-model contract audit checkpoint (2026-07-14).** A fixed-path
read audit of the Rabbita loaders found two runtime gaps that the earlier
screen sample did not exercise: `/api/company/workflow/process-defs` and
`/api/company/business-units/tree` were missing from the development
read-model server even though their service adapters and frontend loaders were
present. Both routes are now connected as fixed PostgreSQL reads, including
the workflow preview path (`/process-defs/:processKey/preview`) with
source-style 404 behavior for an unknown process. The workflow endpoint
returns the two imported definitions, twelve steps, six assignee links, and
explicit zero instance/action coverage; the business-unit endpoint returns
one root and seven imported nodes. The browser `/tasks` state now shows
those definitions and keeps pending/initiated/history source observations
empty, rather than falling back to approval fixtures. The hierarchy endpoint
is source-verified directly; its full organization-screen/browser scope pass
remains open.

**Investment import/cockpit audit checkpoint (2026-07-14).** The remaining
investment GET backlog was checked against the source route implementations,
not just the route count. The Excel import-history list is now an empty-safe
observation; bridge/index-preview/profit-table/
plan-line/subject-mapping and profit-cockpit handlers depend on absent
`tzsy_excel_import`, `tzsy_excel_sheet`, `tzsy_profit_table`,
`tzsy_plan_line`, and `tzsy_subject_mapping` source tables. The source
profit-cockpit itself returns `41002` when no imported profit table exists; the
migration keeps that covered boundary rather than substituting designer values.
The source profit-actual route additionally simulates sparse sales/expense/CBS
inputs. Native MoonBit now ports that calculation as an observation: real
receipts, paid applications, expenses, contracts, and loans are distinguished
from progress/mapping fallback values with `simulated=true`; no plan still
returns source-style `41002`. `scripts/company_postgres_investment_actual_smoke.sh`
proves the populated path. The missing export, formula reconciliation, and
owner acceptance remain open; the current 26-index/version/sensitivity plus
empty import-history/actual-plan observations remain the production evidence.

The browser pass also found an inherited source-contract inconsistency that
must be reconciled before investment acceptance: the investment summary card
renders the imported `CO.IRR` value of `14.8%`, while the source sensitivity
route (and the PostgreSQL adapter that mirrors it) searches only for index names
matching `售价|收入` and `成本`. The current imported labels are `可售货值` and
`成本结转`, so the six sensitivity rows display a `-100%` baseline despite
the summary card's `14.8%`. This is reproducible in the original ERP route as
well as the port; it is recorded as a source/UI reconciliation defect, not
silently “fixed” in the migration adapter. The investment owner must choose a
canonical label/metric mapping, then the source, adapter, UI, and smoke test
must agree before that route can move from `connected_investment_read` to
accepted behavior.

**Broader browser acceptance checkpoint (2026-07-14).** The same local
PostgreSQL read-model session, using the documented `admin` fixture only,
exercised the remaining visible operational and governance surfaces: AI
workspace and analytics, supplier library and risk board, report center and
report builder, warning center, inbox, attachment center, notification
configuration, audit log, error log, system health, users/roles, data backend,
OCR configuration, and the three-platform Webhook configuration. Every
observed GET in this pass returned HTTP 200; the stopped server log is retained
as the route evidence. The pages consistently exposed source provenance and
truthful empty/missing-table states: AI pages showed zero source activity with
provider execution disabled; supplier pages showed no imported providers but
did show the six evaluation and four source dictionary definitions; reports
showed an empty core source read while designer templates remained visibly
fixture/design data; warning center showed one imported `W005` observation and
twelve rules; inbox, attachments, notification queues, and delivery logs were
empty; audit showed the two imported login rows; and OCR/Webhook screens showed
redacted metadata only. No mutation or provider call was made.

Two important non-parity states were made explicit by this pass. The health
screen's table/BPM coverage is source-backed; the newly connected full-health
service read still reports uptime, memory, storage, and queue metrics as
unavailable, and browser mounting/production acceptance remains open. The users/roles
screen has the five imported identities, an explicit `NO_SOURCE_ROWS` role
state, and the source-defined 11-module permission catalog; these are
observation metadata, not an authorization source. Attachment binaries,
notification delivery, OCR
recognition, Webhook delivery, and all configuration writes remain gated by
identity/provider/operational authorization. This is browser evidence for the
bounded read wave, not production acceptance or a claim that the remaining
operational handlers are implemented.

**Identity observation checkpoint (2026-07-14).** The service and development
read-model now expose fixed PostgreSQL reads for source `GET /auth/prefs` and
`GET /rbac/me`. The imported `admin` identity returns an empty preference map
with zero `sys_user_pref` coverage, and the RBAC observation returns the
imported identity with empty roles/permissions and `NO_SOURCE_ROWS` for
`sys_role`/`sys_user_role`. Both responses explicitly report
`authorizing=false`; role administration, token binding, and production
authorization remain gated. The parity matrix and service smoke now cover
these routes, making the missing role/preference export a measurable source
gate rather than an unimplemented HTTP hole.

**Preference command checkpoint (2026-07-14).** Source `PUT`/`DELETE`
`/auth/prefs/:key` now have a narrow translation seam at
`/api/company/source/auth/prefs/:key`. The development gateway binds the
command to the signed source `user_code`; set/delete requests persist
idempotent `user_preference` aggregate revisions and audit receipts, and
`GET /api/company/auth/prefs` merges active command values while preserving
source coverage and tombstone provenance. Imported `sys_user_pref` rows are
never overwritten, and the command is explicitly non-authorizing and neutral
to provider, accounting, cash, and tax effects. Trusted-gateway replay/read
back evidence is present; managed identity, browser acceptance, and
security-owner approval remain open gates.

**Role/catalog observation checkpoint (2026-07-14).** The same bounded read
wave now covers source `GET /rbac/roles`, `GET /rbac/roles/:code`, and
`GET /rbac/permission-catalog`. The current export has five imported users but
zero `sys_role`/`sys_user_role` rows, so the Users/Roles screen displays an
explicit `NO_SOURCE_ROWS` role state rather than inventing the former design
roles. The permission catalog preserves the source-defined 11 modules and
their permission counts as definition metadata only; it does not grant local
authority. Signed native role upsert/delete and imported-user role assignment
commands now persist command-owned authority candidates, enforce enabled
super-user actors, replay idempotently, and merge into role/user/me reads;
`scripts/company_postgres_rbac_smoke.sh` covers the full local slice. These
commands deliberately set `authorization_candidate=true` while retaining
`authorizing=false`; user create/update/toggle/reset-password candidates now
persist only digest-backed credential metadata (never plaintext). Password
binding, production identity/token binding,
provider-backed authorization, owner reconciliation, and the complete
credential-safe export remain open gates.

**Trusted-upstream identity rehearsal checkpoint (2026-07-15).** The native
MoonBit gateway now has an opt-in identity-bound mode for the production integration
seam. It accepts `X-Moonproj-Identity`, a Unix timestamp, and an HMAC-SHA256
signature over `user_code:timestamp`; assertions older than 60 seconds or with
invalid signatures are rejected. Before creating the HttpOnly session, the
gateway calls the authenticated PostgreSQL profile read and requires the
asserted `sys_user` to exist and be enabled. The resulting session actor is
the source `user_code`, not the former fixed `rabbita-user` fixture. The
shell-only native gateway smoke verifies valid login/forwarding, secure trusted
login, command allow-list rejection, logout, and missing-session rejection.
This materially improves the identity seam, but the local session store is
still in-memory and the managed issuer/audience, token rotation, deployment,
and security-owner approval gates remain open.

**Dashboard/admin observation checkpoint (2026-07-14).** The authenticated
PostgreSQL service now exposes the source cockpit v2 scope (`buGuid`/`projGuid`)
with KPI, payment-trend, stage-distribution, and warning observations over the
currently imported rows. It also exposes source-shaped full-health, redacted
LLM-status, and AI-diagnostic reads. The service smoke verifies project-scoped
v2/v3 values, the attachment download boundary, and all three diagnostic
responses; health runtime metrics are explicitly unavailable and no provider
ping is performed. The parity matrix now has explicit boundaries for every
source GET/HEAD handler, including the PostgreSQL backup-export boundary and
supplier signature-check boundary. Rabbita now mounts the v2 response as a
read-only KPI/trend/stage/warning panel and mounts the v3 aggregate sections
on `/dashboard-v3`; the v3 observation still reports the 16 absent
cross-domain tables explicitly. Production identity, browser scope
acceptance, and owner reconciliation remain open.

**Investment Excel observation checkpoint (2026-07-14).** The service now
preserves the source boundary for import detail, bridge-plan, index-upsert
preview, profit-table, plan-line preview/list, subject mappings, and profit
cockpit. With no imported workbook, sheet, profit-table, plan-line, or mapping
rows in PostgreSQL, detail/bridge/preview/profit/cockpit requests return the
source-style missing-record boundary, while plan-line and mapping reads return
empty data with coverage metadata. Smoke evidence covers all of these paths
without upload, write, provider execution, or designer fixture substitution.
Profit-actual now runs through the native bounded imported-real/simulated read;
dashboard v3 and investment actual-profit are mounted as read-only panels, and
the seeded shell smoke proves the calculation. Formula reconciliation,
production identity, owner acceptance, attachment download,
PostgreSQL backup export, and supplier signature checking have explicit
boundaries. None is an accepted production capability.

**Investment lifecycle command checkpoint (2026-07-15).** Native MoonBit now
translates the low-risk investment version/index lifecycle handlers: create,
activate, and delete local versions plus create, update, and delete local
indices. Commands require a signed enabled user, use request-equal idempotent
company-command receipts, immutable aggregate revisions, audit events, and
source-shaped readback. Imported `tzsy_version`/`tzsy_plan_index` rows are
protected as read-only; local projections merge into versions, grouped indices,
profit summary, and sensitivity reads. The lifecycle smoke proves create,
replay, current-version readback, index update/tombstone, and non-current
version deletion, with investment-only and no-provider/cash/accounting/tax
effects. Excel upload/import activation, formula/owner acceptance of
actual-profit simulation, valuation, browser identity, and investment-owner
acceptance remain separate gates.

**CBS version command checkpoint (2026-07-15).** Native MoonBit now translates
the source CBS draft/version lifecycle that can be safely owned locally:
`POST /api/company/cbs/versions/clone`, `freeze`, and `activate`, plus
`POST /api/company/cbs/dict` for adding a draft leaf, and
`POST /api/company/cbs/dict/batch-adjust` for the source percentage adjustment.
Clone copies the source-shaped subject dictionary into command-owned
projections; freeze, activate, and adjustment create immutable revisions and
activation de-overlays; dictionary and version reads merge those projections
and expose command provenance. Signed enabled-user checks, request-equal
idempotency, audit receipts, imported-row guards, two-decimal adjustment
rounding, and explicit `cbs_effect=true`/`budget_consumption=false` markers are
covered by `scripts/company_postgres_cbs_smoke.sh`. Imported CBS rows remain
read-only. R0 resolution now records an auditable, dictionary-aware local
intent with `resolution_pending` fallback and imported-contract protection;
it does not mutate CBS contracts or consume budget. Budget
reservation/consumption, demo-contract legacy/clear, approval/change writes, accounting,
cash, tax, browser identity, and owner acceptance are still separate gates;
the controlled export currently has no imported CBS version or subject rows.

**Budget expense command checkpoint (2026-07-15).** Native MoonBit now
translates the source-shaped budget expense mutation boundary: create a Draft
expense with detail and four-dimension split rows, edit Draft fields, submit a
Draft for approval, and void Draft/Rejected expenses. Local expense, detail,
and split aggregates use immutable revisions, signed enabled-user checks,
request-equal idempotency, audit receipts, imported-row protection, and
source-shaped merged list/detail readback. `POST
/api/company/budget/expenses/:guid/auto-offset` now computes the source FIFO
approved-loan plan and updates only a command-owned Draft expense; loan
balances remain unchanged until a later workflow-authorized step. The boundary
still keeps `budget_effect`, `budget_consumption`, cash, accounting, tax, and
workflow-engine synchronization false or gated. The budget-expense smoke
proves create, replay, readback, auto-offset/replay, update, submit, and void;
the controlled export still has zero imported expense rows.

**Mutation-boundary checkpoint (2026-07-16).** The native service now exposes
explicit authenticated candidates for every remaining source mutation family
and a bounded R0 resolution intent.
`POST /api/company/budget/expenses/:guid/sync-from-workflow` returns a 409 until
workflow source rows exist. Demo-contract legacy/clear, contract
approval/payment, and change writes return a `cbs_mutation_boundary_candidate`
409 with no persistence or financial effect; demo-contract create persists a
budget-check-pending local projection, and R0 resolution persists an auditable
`cbs_r0_resolution` intent without mutating imported contracts or financial
effects. Project and contract batch imports
now validate source references and commit command-owned projections with list
readback and idempotent replay; production identity and operations-owner
acceptance remain. Destructive sales-customer delete returns a
`sales_customer_delete_candidate` 409 because the product policy is archive,
not hard delete. Auth logout/profile now persist signed local command
projections and overlay `/auth/me` readback; login/password writes return an
`auth_lifecycle_candidate` 409 until production identity, password/session
storage, and security-owner acceptance are available. The parity ledger now
has zero `not_connected` API handlers; these candidate states remain explicit
acceptance gates rather than functional-parity claims.

**Report-builder command checkpoint (2026-07-15).** The report-builder
boundary is now native MoonBit rather than a Python-only comparison surface.
Metadata preserves all ten source table definitions and eight operators;
signed `POST /api/company/reports/templates` and owner-scoped `DELETE
/api/company/reports/templates/:id` persist command-owned revisions, replay
receipts, audit events, and tombstones while imported `sys_report_template`
rows remain read-only. `POST /api/company/reports/templates/run` validates the
same table/field/operator allow-list and filters imported JSON envelopes in
memory, returning `sql_executed=false` and explicit source coverage. The
shell-only `scripts/company_postgres_report_template_smoke.sh` proves
metadata, create/replay, merged readback, filtered execution, delete, and
tombstone behavior. Native XLSX export is covered by
`scripts/company_postgres_report_export_smoke.sh`; PDF export, production
identity, browser acceptance, managed serving, and report-owner approval remain
separate gates.

**Report-share command checkpoint (2026-07-15).** Native MoonBit now ports the
bounded share lifecycle from `share.js`: signed create/list/revoke commands
persist command-owned `report_share` revisions, idempotency receipts, and audit
events, with owner/super-user revoke checks and expiry/access-count readback.
Public metadata/data reads omit bearer authentication but require forwarded TLS,
serve only the five allow-listed core reports, and record access revisions.
`scripts/company_postgres_report_share_smoke.sh` proves create/replay/list,
public meta/data, access counting, revoke, and revoked-link rejection. The token
is deterministic SHA-256 evidence for this local boundary; production credential
issuance/rotation, managed public serving, report export, identity, and owner
acceptance remain separate gates.

**Page-by-page browser acceptance checkpoint (2026-07-14).** After the
representative checks above, the same logged-in local session exercised every
visible Rabbita navigation group through sidebar actions (not direct URL
loads). The results are now recorded as bounded UI/read-model evidence:

* AI: `AI 驾驶舱`, `AI 工作台`, and `AI 工作大盘` rendered their funnel,
  workspace, usage, and activity states with provider execution still disabled.
* Project: `项目主数据`, `项目计划`, `工程进度`, and `我的待办` rendered;
  project/plan/progress/task-definition reads stayed source-backed or
  explicitly empty where the export has no progress/output/task rows.
* Sales: all six pages (`客户档案`, `认筹登记`, `签约管理`, `按揭办理`,
  `销售回款 (R6)`, `营销管理`) rendered the PostgreSQL sales observation
  headings and their customer, reservation, agreement, mortgage, receivable,
  revenue, campaign, placement, channel, and material sections.
* Cost/procurement: `成本驾驶舱`, `投资收益`, `合同台帐`, `付款申请`,
  `动态成本`, `合约规划`, `供应商库`, and `风险面板` rendered; the CBS
  dictionary/version/R0/approval family also rendered with the truthful
  `PostgreSQL CBS 字典 (0)` state. Imported dynamic-cost, investment,
  supplier-dictionary, and risk observations remained read-only.
* Finance: `资金计划`, `发票管理`, `我的报销`, and `我的借款` rendered;
  fund-plan and reimbursement source tables remain empty, while invoice,
  loan, and sales-source observations retain their provenance labels.
* Analysis: `报表中心`, `自定义报表`, and `异常预警` rendered their report,
  dataset/template, warning-list, and rule sections. Empty core report data
  and designer templates remain visibly distinct.
* System: `站内信`, `附件中心`, `通知配置`, `审计日志`, `错误日志`,
  `系统健康`, `用户/角色`, `数据后台`, `OCR 配置`, and `Webhook 三平台`
  all rendered; source metadata, empty queues, redacted provider state, and
  the 11-module permission catalog remained explicit.

Every sidebar navigation action in this pass reached a rendered page and the
server log recorded HTTP 200 for the observed read requests. This is now
page-by-page route/render acceptance for the bounded local read wave; it is
not screenshot-level visual parity, mutation acceptance, production identity
approval, provider authorization, or named-owner sign-off. Directly entering
`/projects` on the static development server still returns its expected
server-level 404 because the server has no SPA fallback; this does not affect
the sidebar-driven app routes and is kept as a deployment/cutover check.

**Plan update from the completed audit (2026-07-14).** The migration is no
longer blocked by an unidentified UI or read-route backlog. The bounded local
read wave has page-by-page sidebar evidence, PostgreSQL smoke evidence, and a
trusted-upstream identity rehearsal. It is still not production-ready: the
session store is local and in-memory, the managed issuer/audience/rotation and
deployment boundary is not accepted, and the current source export covers only
26 of 75 tables. The next work is therefore ordered by decision value rather
than raw route count:

**Source-export revalidation checkpoint (2026-07-14).** The controlled ERP
artifact was re-exported from
`../erp/erp_new/backup/erp-v0.1.0-snapshot.db` with
`scripts/erp_snapshot_export.sh`. The result is unchanged and hash-bound:
26 tables, 120 rows, and source SHA-256
`4ff5dd0ad0b75c6cfc572f99047fe41c5df4b8c48d3877f707fe063aec7dea03`.
Re-running the MoonBit schema-gap and `cmd/schema_cohort_plan` commands, plus
the MoonBit `cmd/source_export_request` command, through their shell wrappers,
against that manifest produces 75 schema
definitions, 26 present tables, 49 `schema_only` tables, seven ordered waves,
and an explicit 49-table request with state `awaiting_source_export`.
The request remains read-only and credential-free: empty tables, primary-key
metadata, per-table/source hashes, and recursive secret redaction are required;
no rows are promoted and no cutover is authorized. This confirms that the
remaining gap is missing source evidence, not an untracked implementation
backlog. The next source action is to obtain that redacted export (or an
owner-approved disposition for each absent table), validate it with
the MoonBit `cmd/export_contract`, then compare it against the immutable fixture before
any broader staging or workflow promotion.

**Execution-gate decision (2026-07-14 rerun).** A fresh repository audit keeps
the plan in the same controlled state: the parity register still reports 56
browser routes, 338 source handlers, and 182 mutations; every source
GET/HEAD handler has an explicit target boundary, but the matrix remains
`functional_parity_incomplete`. The local PostgreSQL service/gateway and
Rabbita build/test evidence remains valid for the bounded read and command
waves, while the source contract remains `source_export_incomplete` at 26/75
tables. Therefore steps 1–6 of this plan stay complete, step 7 (the
credential-safe export or owner-approved empty dispositions) stays active,
and production identity/shadow acceptance plus economic/provider effects stay
pending. Do not open another broad fixture-backed surface or enable a
mutation/provider effect until step 7 produces a validated artifact and the
named owner accepts its coverage.

**Rehearsal refresh (2026-07-14).** A new read-only run of
`scripts/erp_migration_rehearsal.sh` against the immutable snapshot completed
without source mutation: the export contract still verifies 26 tables and 120
rows, the schema gap remains 49 tables across seven waves, raw staging and
relationship audit pass, and the generated empty-table handoff contains 49
pending entries with `promotion_authorized=false` and
`cutover_authorized=false`. This strengthens the handoff evidence but does not
clear the source-export gate; the next valid input is still the redacted
source JSON/NDJSON export or a fully owner-approved disposition artifact. Any
MySQL extraction step belongs to the ERP source boundary only; it is not part
of the Moonproj target runtime.

**Native endpoint audit (2026-07-15).** The report, dashboard, workflow
definition, and primary investment-observation waves are no longer Python
runtime dependencies: `cmd/postgres_company_service` now owns the five
individual report reads plus `/reports/overview`, all seven dashboard/cockpit
GET reads, workflow definition/preview plus signed local workflow
start/approve/reject commands, and investment versions/indices/profit/
cost-dashboard/Excel-import/plan-line/subject-mapping/cockpit reads, cashflow forecast/inflow/detail/net/gap/v3, CBS observation reads, and
the native admin/notification/AI/attachment/webhook/RBAC/warning observation
reads plus warning resolve/ignore state commands, notification message/read-all
and subscription commands, and local RBAC role/assignment
authority-candidate commands, plus local investment version/index lifecycle
commands.
`scripts/company_postgres_source_read_smoke.sh` and
`scripts/company_postgres_dashboard_smoke.sh` exercise these boundaries with
PostgreSQL only. The gateway's GET forwarding is not proof of service coverage;
a path can be allow-listed and still return a native 404. The remaining
browser-visible families without native MoonBit service ownership are
actual-profit formula/owner acceptance and mutations, AI explain/provider
actions, Excel upload/import activation, CBS budget-reservation/
mutation surfaces, warning scans/provider actions, attachment binary/OCR
operations, notification/provider actions, RBAC password/identity writes and
production authorization binding, source workflow-engine
synchronization/full delegation semantics, report-builder PDF export and production
share-credential/managed-serving policy, and the remaining investment/cash/
provider effects.
Those surfaces stay explicitly gated rather than being represented by
designer fixtures or the frozen Python bridge.

The export contract now also checks every non-empty row for a non-null,
unique declared primary-key value before reporting content verification. This
strengthens the handoff without changing the current disposition: the
available SQLite artifact still verifies 120 rows but remains
`source_export_incomplete` until the 49 missing tables arrive.

The source handoff now also has a machine-checkable empty-table disposition
contract in `erp_empty_disposition.py` and
`ERP_EMPTY_TABLE_DISPOSITION.md`. It generates all 49 schema-only entries and
accepts an `owner_approved_empty` entry only with zero-row evidence, the exact
empty-table hash, a source snapshot hash, a named owner, a UTC approval time,
and rationale/evidence reference. A validated artifact can report
`owner_dispositions_complete`, but it always keeps promotion and cutover
authorization false; the owner-filled artifact is still required.

| Priority | Scope | Decision / exit evidence | Keep gated until |
| --- | --- | --- | --- |
| P0 | Production identity and shadow operation for connected reads | Managed issuer/audience, token rotation, persistent session/rollback, named owner acceptance, and a read-only shadow comparison | Security/operations owner approval and a complete credential-safe source export |
| P1 | Missing 49-table source export and reconciliation | Hash-verified, redacted export including empty tables and primary-key metadata; runtime `/api/company/source/migration/schema-coverage` evidence; source/UI metric-label reconciliation, including the investment IRR/sensitivity mismatch | Migration owner accepts coverage and metric semantics |
| P2 | Dashboard v3 and investment actual acceptance | The v3 observation and native profit-actual imported-real/simulated read are implemented; reconcile missing CBS/sales/fund/invoice/tender/warning dependencies or an explicit owner-approved empty disposition before exposing management KPIs, then approve source calculation semantics for actual-profit simulation | Finance/operations owner accepts formulas, source coverage, and the no-synthetic-KPI policy |
| P3 | Attachment binary completion and database backup | The attachment download boundary is connected for missing metadata/binary; bind real binary storage, retention, authorization, and PostgreSQL backup/restore policy to managed operations | Security/operations owner approval; do not return fixture or ad-hoc files |
| P4 | Supplier provider signature decision | The missing-provider boundary, populated-provider procurement gate, and non-authorizing command-owned derived preview are connected; bind provider credentials, imported-row risk calculation parity, timeout/retry, and audit trail before returning an imported-provider decision | Procurement/security owner approval and a real provider test contract |
| P5 | Mutations and external effects | Marketing and invoice local command cohorts now have authority, deterministic idempotency, aggregate revisions, audit receipts, source-shaped readback, and service/gateway replay evidence. Delivery progress/output create, report, confirmation, and command-owned progress tombstone actions are now explicitly registered against the evidence-gated command runtime; imported progress remains read-only. Sales customer/subscription/mortgage/refund actions and the revenue create/update/confirm/delete cohort now map to PostgreSQL command runtimes, and expense create/update/submit/void now maps to the source budget mutation boundary, while destructive customer deletion remains gated. Fund plan create/update/delete and dispatch create/approve now use the same local authority/idempotency/revision/audit boundary; imported fund rows remain read-only and commands are explicitly cash/accounting/tax-neutral. Project-plan task create/update/delete and evidence-gated task report now use a separate local planning projection; imported `jd_task` rows remain read-only and AI scheduling remains gated. Signed local workflow start/approve/reject commands now persist command-owned instance/action projections, owner checks, replay/audit evidence, and workflow-only effect markers; imported workflow rows and source-engine synchronization/delegation remain gated. MDM project create/update/delete aliases now use a command-owned project projection with lifecycle initialization, imported-project protection, source-shaped readback, replay, and tombstone evidence; task/workflow/budget/accounting/cash/tax effects remain gated. Tender planning/lifecycle commands, command-owned tender tombstone/delete, and contract-split commands are locally verified, and source tender create/split/delete aliases now return source-shaped readback with command provenance; arbitrary state overwrite, imported deletion, and standalone award semantics remain policy gates. Supplier source provider POST/PATCH/PUT/DELETE aliases now translate the ERP provider field family into command-owned supplier projections and merge source-shaped list/detail readback with replay evidence; imported providers remain read-only and qualification/signature/rescore/external effects remain gated. Payment-application source create/update/void aliases now reuse the native command projection, translate source fields, enter the submitted approval state, and preserve no-cash/accounting/tax markers. Contract source create/update/void aliases now reuse the native command projection, preserve BU/project/provider/amount/CBS fields, and return source-shaped readback with imported-row protection and tombstone semantics. Dynamic-cost source create/update/void aliases and contract-milestone create/update/trigger/void aliases now use the same command projection pattern with imported-row protection and source-shaped readback. Authenticated preference set/delete aliases now use a signed-user-scoped command projection with replay/audit evidence while imported preferences remain read-only and no identity, authorization, provider, accounting, cash, and tax effects are enabled. Notification subscription create/update/delete and message read/read-all aliases now use signed-user-scoped command projections with source-shaped readback, replay/audit evidence, tombstones, and imported-message overlays while imported notification rows remain read-only and delivery/provider/accounting/cash/tax effects remain false. Report-builder template create/delete commands now use command-owned revisions and report run evaluates only the source field whitelist without executing raw SQL; imported templates remain read-only and report exports remain gated. CBS/budget enforcement, payment execution, and external effects remain gated. Continue the same pattern for remaining mutation families and bind accounting/tax/cash/provider effects separately | Named business owner acceptance, production identity, and external-effect owner decisions; imported rows remain read-only |

This ordering supersedes the earlier route-count-first sequence. The remaining
GET/HEAD boundaries are explicit gates, not a reason to broaden the
surface with synthetic data or provider calls. The route matrix remains
`functional_parity_incomplete` until the connected read slices pass managed
identity, source reconciliation, browser interaction, and named-owner gates.

1. **Visual UI port, not final UI parity.** Rabbita has the source login,
   navigation, dashboard, major route families, and representative forms, but
   many views are fixture-backed/read-only. The bounded local read wave now
   has page-by-page sidebar/render evidence, but screenshot-level visual,
   interaction, and route-action comparison remains open.
2. **Connected local slices, not accepted production workflows.** The local
   PostgreSQL service and Rabbita gateway now exercise bounded expense,
   contract, payment-application, procurement, sales/receivables, invoice,
   fund planning, delivery/progress, project-plan task, core-report, and employee-loan read/command slices. Procurement covers supplier
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
   and five key nodes; local task create/update/delete and evidence-gated report
   projections are also connected while imported task rows remain read-only. See
   [`ERP_PROJECT_RUNTIME_AUDIT.md`](ERP_PROJECT_RUNTIME_AUDIT.md).
   The source MDM business-unit tree is also connected as a read-only
   hierarchy (seven imported rows); legal-principal ownership and organization
   mutations remain gated. See [`ERP_MDM_RUNTIME_AUDIT.md`](ERP_MDM_RUNTIME_AUDIT.md).
   The available budget dictionaries are now source-compatible reads as well
   (five cost-subject options and three proceedings); source-shaped expense
   create/update/submit/void commands are locally connected with detail/split
   readback, while dictionary mutation, budget reservation/consumption,
   automatic offset, and workflow synchronization remain gated. See
   [`ERP_BUDGET_RUNTIME_AUDIT.md`](ERP_BUDGET_RUNTIME_AUDIT.md).
   Investment feasibility reads are also connected for the available cohort
   (one version, 26 indices, five dimensions, and profit summary); import,
   activation, valuation, cash, accounting, and tax remain gated. See
   [`ERP_INVESTMENT_RUNTIME_AUDIT.md`](ERP_INVESTMENT_RUNTIME_AUDIT.md).
   The source-compatible dynamic-cost read is now connected as a separate
   cost slice: Rabbita `/dynamic-cost` loads all seven imported `cb_cost` rows,
   preserves the source A/B/C/D/E/F/G/H formula, and reports the imported
   summary and coverage. The separate `/cost-dashboard-v3` read now also
   consumes the source-compatible `profit-actual-v2` hierarchy and reports
   truthful zero-row coverage when CBS/version, budget, expense, and change
   tables are unavailable; it is connected observation evidence, not accepted
   production KPI parity. See
   [`ERP_DYNAMIC_COST_RUNTIME_AUDIT.md`](ERP_DYNAMIC_COST_RUNTIME_AUDIT.md).
   Admin dictionary, bounded quality, audit, health, user-roster, and
   imported-profile reads are connected. The source dictionary POST/PATCH
   handlers now have a bounded PostgreSQL command-owned overlay: an enabled
   imported super-user is required, imported rows stay read-only, replay writes
   only projection/receipt/audit evidence, and provider/cash/accounting/tax
   effects remain false. The Rabbita dictionary table is still read-only, so
   browser command controls and production identity are not yet accepted.
   for the available governance rows (one group, five options, twelve quality
   rules with four unavailable dependencies, five imported users, two audit
   events, 29 health-table coverage rows, and an empty BPM pool). The profile
   vertical also preserves the source user's initiated-document rows (zero
   expenses, one loan, and three payment applications for the imported
   `limingjin` identity); super-user
   scope, password/identity writes, audit/role retention, source completeness, and
   security-owner acceptance remain gated. See
   [`ERP_ADMIN_RUNTIME_AUDIT.md`](ERP_ADMIN_RUNTIME_AUDIT.md).
   The expense list now has a separate source-compatible read over
   `vcb_expense`; the current export returns zero rows and reports the empty
   table, while local expense commands remain isolated projections. Expense
   detail and approval synchronization still require source rows and workflow
   data. See [`ERP_EXPENSE_RUNTIME_VERTICAL.md`](ERP_EXPENSE_RUNTIME_VERTICAL.md).
4. **Reporting is locally connected but source-incomplete and not accepted.**
   The five core report reads now run through the native MoonBit PostgreSQL
   service and Rabbita `/reports` overview. Cost, contract, and
   project-stage rows are populated from source raw tables; supplier and
   approval sections correctly remain empty because the backup has no provider
   tables and zero workflow-instance/action rows. The shell-only source-read
   smoke proves the native report envelope. Native share create/list/revoke and
   public meta/data reads now have a shell smoke; production share credentials,
   managed serving, export, identity, browser acceptance, and report-owner
   reconciliation remain open.
   See [`ERP_REPORT_RUNTIME_AUDIT.md`](ERP_REPORT_RUNTIME_AUDIT.md).
4a. **The dashboard/cockpit now has bounded v1, v2, and v3 read slices, but is
   not accepted parity.** The source cockpit exposes seven GET handlers
   (overview, funnel, top anomalies, project KPI/anomalies, and v2/v3 group
   views) over 30 unique tables. The target exposes all seven as authenticated
   native MoonBit source-backed observations, and Rabbita loads the v1 group
   overview, funnel, and anomaly rows while preserving the designer layout.
   The shell-only dashboard smoke proves the imported KPI and scope values.
   Only 14 of the 30
   dependencies are present in the controlled export; 16 cross-domain tables
   needed by the full v3 view are absent. Every response reports source
   coverage and missing tables; no synthetic revenue, cash, health, warning, or
   risk values are introduced. Production identity, browser scope acceptance,
   v3 source coverage, and owner reconciliation remain open. Report reads do
   not constitute cockpit parity. See
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
currently records 54 connected browser states, no fixture-backed read-only
state, and two public states. Its API matrix records all 156 source GET/HEAD
 handlers with explicit connected reads or safety boundaries; the 182 mutation
 handlers remain separate across MDM organization/project, budget
dictionary and expense detail, investment and cost-dashboard v3,
admin governance, dynamic cost, expense, contract, payment, procurement,
supplier-provider, and supplier-risk,
sales, invoice, delivery, dashboard v1, core reports, employee-loan,
workflow-definition, AI analytics, AI Hub observation, webhook metadata,
   report-builder metadata, cost-dashboard v3, and dashboard-v2/v3 reads; the
   three dashboard aliases still represent the bounded source-backed v1 read;
   Rabbita also mounts the scoped v2 observation and the `/dashboard-v3`
   aggregate panel. The remaining browser views
and API groups are explicitly tracked
as fixture, public, or not-connected rather than counted as parity. Workflow definitions are
connected only as non-authorizing reads; instance/task actions remain gated. That gap,
rather than additional platform hardening, controls the next work.

**Runtime-language checkpoint (2026-07-15).** The export-contract,
schema-gap, schema-cohort-plan, schema-cohort-mapping, and
source-export-request Python bridge slices have been replaced in the active
rehearsal path. MoonBit `cmd/export_contract`, `cmd/schema_gap`,
`cmd/schema_cohort_plan`, `cmd/schema_cohort_mapping`,
`cmd/source_export_request`, and `cmd/route_inventory`, invoked through shell
wrappers, validate the same
manifest, table hashes, row counts, primary-key identities, recursive
redaction, capability mapping, seven-wave ordering, seven mapping outputs,
75-table coverage, 49-table request contract, and 30-file/338-handler/
28-middleware route baseline as the former Python checkers. Against the current
fixture all replacement outputs are byte-for-byte equivalent: 26 exported
tables, 120 verified rows, 49 missing schema tables, and
`source_export_incomplete` with promotion and cutover both false. The
remaining Python service, gateway, and rehearsal adapters stay frozen as
bridge evidence until their MoonBit equivalents are shadow-compared. The first
native PostgreSQL runtime slice is now also available as
`cmd/postgres_read_model`, invoked through
`scripts/company_postgres_read_model.sh`: fixed `summary`, `receipts`, and
`projections` reads execute through the inherited PostgreSQL environment and
match the Python read-model responses, including aggregate-type filtering, on
the live target. The native authenticated service slice
`cmd/postgres_company_service`, invoked through
`scripts/company_postgres_service.sh`, now adds mandatory bearer-token and
forwarded-TLS checks plus exact live parity for the profile, preference,
initiated-document, contract, payment-application, and payment-eligibility
observations; it remains capability-limited and read-only,
not yet the complete company service. The native gateway/session boundary is now
also available as `cmd/postgres_company_gateway`, invoked through
`scripts/company_postgres_gateway.sh`: it keeps the bearer token private,
establishes an HttpOnly session, signs the actor assertion, forwards the
allow-listed paths, serves the Warren bundle with SPA fallback, and verifies
the trusted-upstream HMAC identity against the native PostgreSQL profile. Its
shell-only smoke covers development login/logout, native read forwarding,
command allow-list rejection, secure trusted login, and missing-session paths.
The raw PostgreSQL target-apply boundary is now also native
MoonBit (`cmd/postgres_target_apply` plus
`scripts/company_postgres_target_apply.sh`): it validates the staging manifest,
applies the catalog/receipt transaction through `psql`, and has native replay
hash parity with the frozen Python adapter in an isolated PostgreSQL schema.
Native `cmd/postgres_projection_apply` now covers the validated domain-receipt
projection transaction as well, including deterministic event identity,
immutable revisions, cohort receipt, and replay-hash parity; the typed cohort
shell rehearsals use that wrapper. Native
`cmd/postgres_accounting_link_apply` covers the explicit event/source/journal
traceability transaction and replay hash as well; all PostgreSQL accounting
cohort wrappers now use the shell entrypoint. These three persistence adapters
remain effect-neutral and do not post journals, release cash, or close periods.

Execute the remainder in this order:

1. Build on `docs/ERP_UI_PARITY_MATRIX.md` / `.json`, the source-to-target
   page/route/action parity matrix and finish the visual/interaction comparison
   for every ERP route family. Record each route as `matched`, `intentionally
   changed`, `blocked by missing source`, or `not implemented`; do not call the
   UI complete from screenshots of only the dashboard.
2. Replace the local session/actor adapter with the reviewed production
   identity, token issuer, rotation, persistence, deployment, and rollback
   boundary for the currently connected bounded reads. Accept the imported
   profile/initiated-documents, expense-list, contract/payment, budget
   scope/balance, workflow observation, dynamic-cost, project/MDM,
   investment, governance, report, supplier-provider, supplier-risk, notification,
   OCR/error metadata, AI analytics, and webhook configuration reads through
   the real gateway session with named owner reconciliation. A truthful empty
   source response is an
   accepted read result only when the owner accepts the source coverage; it is
   not permission to seed fixture rows.
3. Obtain and validate the missing 49-table credential-safe source export
   (JSON/NDJSON) before opening another broad surface. If the working ERP
   produces that export from its MySQL database, MySQL remains source-only and
   is never a Moonproj runtime or deployment dependency. The export must include empty tables,
   primary-key metadata, hashes, redaction results, and an owner-approved
   disposition for any still-empty workflow or supplier tables. Do not promote
   or fabricate approval, supplier, risk, or expense rows from the current
   backup. Keep the current 26-table/120-row snapshot as the immutable
   rehearsal baseline and compare the new export before raw staging.
3a. **Runtime-language convergence (required before production identity).**
    Port `company_postgres_read_model_server.py`,
    `company_postgres_service.py`, and `company_postgres_dev_gateway.py` to
    MoonBit packages with the same fixed routes, PostgreSQL-only boundary,
    signed actor/session semantics, command receipts, and fail-closed error
    behavior. Port the source/export/rehearsal and smoke logic to MoonBit CLI
    commands. The supported implementation is pure MoonBit plus shell: shell
    may select binaries, pass PostgreSQL environment/credentials, start
    processes, and invoke `psql`, but it must not contain business logic or
    depend on Python. Existing Python services/smokes are frozen comparison
    artifacts only; no new Python path may be added or run. Compare native
    responses/receipts/replay against immutable fixtures or previously recorded
    evidence while each slice is ported. A release build must fail if a
    supported command, test, smoke, or deployment manifest invokes Python; the
    only supported runtime binaries are compiled MoonBit programs plus
    explicitly listed PostgreSQL tools invoked by shell.
    Native `cmd/postgres_read_model` covers the first three fixed read
    contracts, and native `cmd/postgres_read_model_server` now serves the first
    bounded HTTP read surface (`health`, `summary`, `receipts`, and filtered
    projections, plus method/OPTIONS handling). Both have exact live response
    parity with the frozen Python development adapter. Native
    `cmd/postgres_target_apply`, `cmd/postgres_projection_apply`, and
    `cmd/postgres_accounting_link_apply` cover the raw, aggregate, and
    accounting traceability transactions with replay-hash parity. Continue the
    port with `cmd/postgres_company_service`'s authenticated native slice
    (health, summary, receipts, projections, profile, preferences and signed
    preference set/delete commands,
    initiated-document, source-shaped contract/payment, and payment
    observations plus the native expense, contract, payment-application,
    contract-milestone, dynamic-cost, invoice, sales-revenue, tender,
    contract-split, marketing, and supplier/provider
    list/detail/command boundaries,
    budget-check preview, and idempotent expense/contract/payment-application/
    contract-milestone/dynamic-cost/invoice/sales-revenue/tender/
    contract-split/marketing/fund-plan/fund-dispatch/supplier
    create/update/submit/reject/resubmit/approve/void lifecycles, with the bounded
    gateway/session boundary now ported as
    `cmd/postgres_company_gateway`; continue with the remaining HTTP routes,
    service commands, gateway allow-list parity, rehearsal planners/parity
    tools, and fixture/replay checks before treating this convergence step as
    complete. Python remains historical evidence only and is not an accepted
    build, test, or deployment dependency.

3a.1. **No-Python execution gate (approved plan update, 2026-07-15).**
    From this checkpoint forward, every new or changed operational path must
    be implemented as a compiled MoonBit command/service and exposed through a
    small shell wrapper. Python files may be read as frozen comparison
    material, but they must not be imported, executed, or required by a local
    check, CI job, smoke test, release artifact, deployment manifest, or
    browser start command. The migration backlog is therefore explicit:
    (a) finish the remaining authenticated company-service reads and command
    lifecycles in `cmd/postgres_company_service` (invoice, sales-revenue,
    tender/contract-split, marketing, fund-plan/dispatch, delivery/progress/output/task-report, and supplier/provider commands are now native
    checkpoints; populated-source qualification,
    signature, and external effects remain separate gates),
    (b) port the remaining source-export, cohort-planner, parity, acceptance,
    and shadow/replay commands to MoonBit, and
    (c) replace each Python call in the legacy rehearsal drivers with the
    corresponding shell wrapper before that driver is admitted to the
    supported path. A release gate must scan executable scripts/manifests for
    `python`, `python3`, and Python module entry points and fail closed. The
    only permitted non-MoonBit executable in the target path is an explicitly
    documented PostgreSQL client/tool invoked by shell; no Python fallback or
    dual-runtime mode is planned.

    The current native gateway/session boundary and bounded company service
    (including the expense, contract, payment-application, contract-milestone,
    dynamic-cost, invoice, sales-revenue, tender, contract-split, marketing,
    fund-plan/dispatch, delivery/progress/output/task-report, and employee-loan
    read/create/submit/offset/update/void command lifecycles) are partial
    completion of this
    gate, not completion of the convergence step: remaining routes, command
    writes, provider/accounting/tax effects, and managed identity/rotation
    still require their own MoonBit implementation and parity evidence.

3a.2. **Executable runtime manifest (approved plan update, 2026-07-15).**
    `scripts/pure_moonbit_runtime_paths.txt` is the allow-list for supported
    runtime paths. `scripts/company_no_python_runtime_gate.sh` scans every
    listed MoonBit package and shell wrapper and fails closed on Python
    interpreter/module invocations. It is a release prerequisite and must run
    before browser start, smoke, deployment, or cutover checks. Shell wrappers
    may invoke compiled MoonBit binaries and explicitly documented PostgreSQL
    tools such as `psql`; they may not invoke a `.py` file or embed business
    logic. Legacy rehearsal shells that still call Python are quarantined and
    cannot be used to certify a cohort; each must be ported to MoonBit plus a
    shell wrapper before it can be added to the manifest.

    The current manifest covers the native PostgreSQL target/apply/read/service/
    gateway boundaries, expense/contract/payment/milestone/dynamic-cost/supplier
    smoke paths, source-export
    inventory commands, all `cmd` packages, and the Rabbita frontend package.
    The gate passing proves only that these paths are Python-free; it does not
    imply that the remaining ERP routes, external effects, managed identity,
    or owner acceptance are complete.
3b. **Completed locally (2026-07-15):** implement only the evidence-ready read
    batch identified by the source audit: contract/payment/milestone reads,
    budget user/loan scope, invoice in/out/tax-ledger reads, and workflow
    instance/task observation endpoints where the source tables are defined,
    plus explicit empty-safe progress/output, sales, tender, and supplier
    dictionary source reads, and the source-backed investment sensitivity
    observation.
    The native MoonBit service, read-model, Rabbita, and shell-only
    read-only smoke checks pass; the invoice/receivable slice is now included
    in that native boundary. At that checkpoint the parity action
    register marked 35 source GET handlers connected. Subsequent identity/RBAC,
    dashboard/admin, investment Excel, dashboard v3, attachment-boundary, and
    investment-actual, backup-boundary, and supplier-signature-boundary waves
    have expanded the connected read set; the current matrix leaves no source
    GET/HEAD handler without an explicit target boundary. Do
    not use any bounded read wave to unlock commands or to infer missing sales,
    invoice, supplier, tender, tax, or investment detail rows. The remaining
    gate is production identity, browser acceptance, owner evidence, and the
    missing-table export.
4. Close the procurement acceptance gap after the source-data decision.
   The local supplier lifecycle/risk reads, source-compatible provider-list/detail and risk-board reads,
   tender planning/award/complete,
   and contract-split reads/creates now pass PostgreSQL smoke and Rabbita
   command-state checks. Remaining procurement work is populated-provider
   signature decision parity and external risk-rescore integration, a
   redacted source export, supplier
   identity mapping, browser acceptance, award-to-commitment acceptance, and
   procurement-owner sign-off.
   Imported rows remain read-only and no award creates a commitment implicitly.
5. Treat the employee-loan command boundary as a finance-owner acceptance
   slice: verify authority grants, applicant ownership, replay/conflict
   behavior, bounded offset projections, and imported-row read-only behavior.
   Do not enable workflow synchronization until source `wf_process_instance`
   and `wf_step_action` rows, state mapping, and a named workflow owner are
   available. The Rabbita loan
   editor now emits the local create/submit/update/void commands; browser
   acceptance through production identity remains open.
6. Finish delivery/progress acceptance before opening another broad surface.
   The local PostgreSQL reads, signed-actor/evidence-checked
   progress/output/task-report commands, gateway forwarding, and Rabbita
   `/project/progress` and `/project-plan` states now work and pass smoke/replay.
   Obtain source `proj_progress`/`proj_output` rows (or an owner-approved
   redacted cohort), run browser acceptance through the production identity
   boundary, and obtain operations-owner approval for task-state conflicts.
   Keep the existing designer layout, but do not count local synthetic rows as
   source import parity. Recognition, budget/cost, cash, tax, and period-close
   effects remain separate gates.
7. Finish report acceptance and then expand runtime vertical slices to the ERP
   parity floor. The five core report reads and `/reports` overview now work
   through native MoonBit;
   obtain the missing supplier/workflow source rows (or owner-approved redacted
   cohort), run browser/report-owner reconciliation, and keep template/export
   plus production share credentials separate. Synthetic rehearsals remain design evidence until real
   source rows and user acceptance are attached. See
   `docs/ERP_REPORT_RUNTIME_AUDIT.md`.
8. Treat `/cost-dashboard-v3` as a separate acceptance wave after the
   connected dynamic-cost and v3 observation reads have been accepted through
   production identity and finance-owner reconciliation. The adapter already
   preserves the source `profit-actual-v2`/CBS hierarchy boundary and reports
   missing budget/expense/change tables explicitly; do not fill that hierarchy
   with dashboard fixtures and do not call the v3 screen parity complete until
   the source coverage and KPI reconciliation gate passes.
9. Accept the bounded native dashboard v1 and v2 gates in
   `docs/ERP_DASHBOARD_RUNTIME_AUDIT.md`
   through production identity, entity scope, and operations/finance KPI
   reconciliation. The v2 service read is mounted as a read-only observation;
   the v3 service observation is connected but remains gated as a management
   surface. Obtain the missing
   sales/fund/invoice/tender/warning/CBS tables (or owner-approved
   dispositions) before accepting v3 or expanding the remaining fixture-backed
   route families. Do not treat `/api/company/summary`, report reads, or the
   offline fixture fallback as cockpit parity.
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
