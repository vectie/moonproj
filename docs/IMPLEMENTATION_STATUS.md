# Implementation Status

Recorded: 2026-07-13  
Reference plan: [MIGRATION_PLAN.md](MIGRATION_PLAN.md)

Source translation: [ERP_TRANSLATION_MAP.md](ERP_TRANSLATION_MAP.md)

This is an implementation ledger, not a replacement-readiness claim. The
existing ERP remains authoritative.

## Completed slices

| Slice | Package | Evidence |
|---|---|---|
| Legal-entity validation | `foundation` | Entity ID, name, and currency validation tests. |
| Local RBAC and delegated authority directory | `foundation/access` | Versioned roles, exact-scope permissions, principal/actor assignments, assignment caps, revocation, effective-dated delegation, bounded `AuthorityGrant` issuance, and exact-scope separation-of-duties rules are implemented and tested; legacy `sys_role`/permission migration remains pending. |
| Organization hierarchy | `foundation/organization` | Business-unit/company hierarchy, parent validation, duplicate protection, and scoped activation. |
| ERP business-unit promotion | `migration/erp` + `foundation/organization` | Source business units require explicit principal/scope mappings and per-unit creation grants; parent-before-child ordering and orphan rejection are enforced. |
| Evidence and audit trail | `foundation/evidence` | Provenance/hash-backed evidence lifecycle and append-only audit replay protection. |
| Scoped authority | `foundation` | Principal/actor/capability/scope/amount checks and denial tests. |
| Fixed-point money | `finance` | Minor-unit arithmetic and currency checks. |
| Chart of accounts and period book | `finance/accounting` | Account ownership, period open/soft-close/close, currency/account checks, ledger posting gate, and a reconciled-close method that refuses to close without balanced subledger/control reports. |
| Accounting event links | `finance/accounting` | Source aggregate → validated journal links with append-only replay protection by both event identity and source aggregate identity. |
| Accounting event envelopes | `finance/accounting` + `persistence/store` | Validated source-to-journal links serialize to schema-bound records for reconciliation and migration batches. |
| Journal invariant | `finance` | Balanced, single-currency, positive-posting validation. |
| Append-only ledger boundary | `finance` | In-memory append-only posting contract with duplicate-entry rejection. |
| Versioned schema contract | `persistence/schema` | Forward-only sequential migration steps with checksum and replay rejection. |
| Record-store and snapshot adapter | `persistence/store` | Append/read envelope plus deterministic JSON snapshot, file round-trip, and validated backup/restore path with source identity and schema migration checks. |
| Atomic migration batches | `persistence/store` | All-or-nothing batch append contract with duplicate and empty-batch guards. |
| Durable file transaction journal | `persistence/store` | Pending-snapshot write-ahead path, validated reopen/recovery, and source-identity enforcement; a production database still owns physical durability guarantees. |
| Aggregate projection revisions | `persistence/store` | Immutable aggregate snapshots with expected-revision sequencing, source-event idempotency, latest-revision lookup, and snapshot reconstruction. |
| SQL migration catalog and command boundary | `persistence/sql` | Versioned up/down DDL for the generic envelope plus aggregate projections, accounting links, and migration receipts; parameterized insert commands, duplicate guards, explicit commit/rollback plans, and executors against both the immutable record store and durable file boundary. A production database driver remains outside this package. |
| SQLite durable migration rehearsal | `scripts/company_sqlite_rehearsal.py` | Applies the four company SQL gates transactionally to a SQLite database, inserts the sanitized raw-envelope cohort with uniqueness checks, records an immutable migration receipt, reopens for integrity/count verification, and makes an identical replay idempotent. This is a rehearsal adapter, not yet the production service driver. |
| Shared SQLite driver boundary | `scripts/company_sqlite_driver.py` + `scripts/company_sqlite_driver_smoke.py` | Centralizes WAL, foreign keys, busy timeout, immediate transactions, catalog migration, rollback, reopen, integrity, and backup behavior; it executes the exact parameterized `persistence/sql` company-record insert shape through an allow-list. The smoke gate proves an intentional failed transaction leaves zero rows and a successful command transaction commits one. This is the local service-driver prototype, not a managed production database deployment. |
| PostgreSQL target adapter | `scripts/company_postgres_target_apply.py` + `scripts/postgres_target_schema.sql` | Applies the validated redacted raw-envelope cohort to PostgreSQL only, with the version-4 catalog, JSONB payloads, conflict checks, transaction-bound inserts, logical row hashes, durable migration receipt, and idempotent replay. The local PostgreSQL 18 target contains 120 raw records; reviewed projection and accounting cohorts are applied through separate adapters. |
| PostgreSQL aggregate projection adapter | `scripts/company_postgres_projection_apply.py` | Persists native domain-promotion receipts to PostgreSQL with immutable aggregate revisions, source-event conflict checks, cohort-scoped `Projected` receipts, table locking, and idempotent replay. The reviewed typed cohorts are executable against the same PostgreSQL catalog; cash, accounting posting, and target ownership remain separate gates. |
| PostgreSQL accounting-link adapter | `scripts/company_postgres_accounting_link_apply.py` | Persists native accounting-link receipts with event/source/journal/principal uniqueness and conflict checks, cohort-scoped `AccountingLinked` receipts, and idempotent replay. It records traceability only; it does not post journals, release cash, or close periods. |
| PostgreSQL typed-cohort rehearsal | `scripts/company_postgres_cohort_rehearsal.sh` + `scripts/company_postgres_projection_parity.py` | Re-runs raw staging, ten core typed cohorts, the source-bound investment-model evaluation, and optional CBS, workflow-assignment, delivery-progress, reviewed delivery-recognition, advance-offset, and payment-accounting cohorts against PostgreSQL, compares every receipt by target/source identity, and replays each cohort. The configured local target remains at 120 raw records, 109 aggregate projections, 7 accounting links, and 19 receipts until the new evaluation cohort is rerun; the next typed rehearsal adds one `investment_model_evaluation` projection. Reviewed delivery recognition remains opt-in because the available report has no accepted value. |
| Rabbita ERP UI clone | `frontend/main` + `frontend/public` + `frontend/README.md` | Designer-facing ERP shell is ported with Rabbita 0.12.4 and Warren-compatible JS build output: source login gradient/copy, 220/64px dark navigation, nested ERP menu hierarchy, header actions, dashboard KPI/funnel/risk layout, and mobile drawer behavior. Major ERP route families render source-shaped fixtures for projects/plans/workflow, AI, sales, cost/procurement, finance, analysis, and system administration; representative project, contract, expense, loan, and supplier detail/new flows open as responsive forms. Inbox, attachments, health, users/roles, profile, notifications, OCR, and webhook routes now have distinct source-shaped screens, the report center opens a read-only `/share/:token`-shaped cost report preview, and detail routes accept arbitrary source IDs with the source dashboard redirect aliases retained. The dashboard calls the fixed PostgreSQL read-model summary endpoint with an offline snapshot fallback; command/mutation API wiring and final page-by-page parity remain pending. |
| PostgreSQL read-model development API | `scripts/company_postgres_read_model_server.py` + `frontend/main` + `moonbit-community/rabbita/http` | Read-only `/api/health`, `/api/company/summary`, `/api/company/receipts`, and `/api/company/projections` endpoints query the PostgreSQL catalog through allow-listed SQL. The built Rabbita dashboard reports the live read-model connection and falls back to reviewed fixtures on failure. This is a development adapter, not the production authenticated service. |
| Managed production deployment contract | `scripts/company_production_deployment_check.py` + `scripts/company_production_service_check.py` + `docs/PRODUCTION_DEPLOYMENT_GATE.md` | Credential-free manifest validation requires a managed PostgreSQL engine, DSN environment reference, bounded pool, verified TLS, encryption at rest, cross-region backup, restore objectives, rollback, observability, structured operations/security/finance approval records, and a separate authenticated fixed-read service boundary with no arbitrary SQL/mutation routes. The examples are intentionally unapproved; provider provisioning remains open. |
| Durable native-promotion projections | `scripts/company_sqlite_projection_apply.py` + `scripts/erp_migration_rehearsal.sh` | Persists validated native promotion candidates as immutable aggregate revisions in the same SQLite transaction boundary, records a projection receipt, verifies integrity, and makes an identical replay insert zero rows. A production connection pool/service remains pending. |
| Native projection parity gate | `scripts/company_sqlite_projection_parity.py` + `scripts/erp_migration_rehearsal.sh` | Reopened SQLite projections compare exactly with the native receipt by source identity and target type; the mapped cohort reports `shadow_verified` with 19/19 items and fails with explicit missing/extra findings for a mismatched cohort. |
| Cohort-scoped receipt replay | `scripts/company_sqlite_projection_apply.py` + `scripts/company_sqlite_accounting_link_apply.py` | Projection and accounting receipt hashes are scoped to their source snapshot/mapping cohort, so a later offset cohort may append rows without invalidating an earlier receipt; rerunning the complete multi-cohort wrapper inserts zero projections/links and preserves all receipts. |
| Native accounting-link receipt and durable apply | `scripts/erp_accounting_link_plan.py` + `cmd/accounting_link` + `scripts/company_sqlite_accounting_link_apply.py` | The allow-listed source-to-journal boundary now covers commitment, advance/offset, settlement, expense, delivery progress/recognition, receivable opening/collection, payable opening/payment, tax, financing, investment acquisition/valuation, asset, cash, and bank-statement source types. It still requires explicit candidate/mapping principal, amount, and currency equality; the existing commitment/advance receipt persists three links transactionally as `AccountingLinked`, while synthetic settlement, receivable, delivery-recognition, tax, financing, and investment-valuation smokes prove native receipt generation and missing-amount quarantine. It does not post cash or infer accounting policy. |
| PostgreSQL accounting-link cohort rehearsal | `scripts/company_postgres_accounting_cohort_rehearsal.sh` + `scripts/company_postgres_accounting_link_apply.py` | Runs any reviewed domain receipt through the allow-listed planner, native validator, PostgreSQL traceability apply, and idempotent replay. The synthetic receivable smoke inserted one link then replayed zero and was cleaned up; the production target remains at 7 reviewed links and 19 receipts. |
| Settlement-request accounting-link cohort | `scripts/fixtures/payment_accounting_link_mapping.json` + `scripts/erp_accounting_link_plan.py` + `scripts/erp_migration_rehearsal.sh` | A separately scoped seventh-argument map validates 3 requested-settlement/payment-application journals against the typed payment receipt, persists 3 additional links transactionally (7 total in the extended run), reconciles source/principal/amount/currency, and keeps cash release and period posting false. |
| Reconciled period-close control | `finance/accounting` + `finance/reconciliation` + `scripts/company_period_close_control.py` | Native `AccountingBook.close_reconciled` refuses to close without balanced reports; the rehearsal now locks all cohorts to one source snapshot, records mapping versions and a deterministic evidence hash, and emits a `ready_for_reconciled_close` artifact while keeping `close_authorized=false`, cash release false, and period posting false. |
| Accounting/subledger reconciliation evidence | `scripts/company_sqlite_accounting_reconciliation.py` + `scripts/erp_migration_rehearsal.sh` + `ERP_SETTLEMENT_ACCOUNTING.md` | Reconciles base, advance/offset, and synthetic receivable-collection/payable-payment links back to promoted source candidates, principal, amount, currency, and durable event/source/journal rows; reports `reconciled` while explicitly keeping `cash_released=false` and `period_posted=false`. |
| SQLite backup/restore parity gate | `scripts/company_sqlite_backup_restore.py` + `scripts/erp_migration_rehearsal.sh` | Backs up the final rehearsal database, reopens the restored file, verifies integrity and schema version, and compares logical digests and counts for raw records, aggregate projections, accounting links, receipts, and schema rows. |
| Cutover readiness evidence gate | `scripts/company_migration_cutover_gate.py` + `scripts/erp_migration_rehearsal.sh` | Combines source staging, schema scope, target counts, all cohort parity reports, including source CBS-budget and warning scans, replay evidence for every optional receipt, SQL-driver smoke, backup/restore, period-close snapshot/evidence-hash checks, and the task-state exception-review artifact into a decision artifact. The full fixture reports `ready_for_business_acceptance` with `cutover_authorized=false`; project-1 task-state, managed-production deployment, and schema-only coverage remain explicit exceptions. |
| ERP schema-scope evidence gate | `scripts/erp_schema_gap_report.py` + `scripts/company_migration_cutover_gate.py` | Compares the authoritative `erp_new` initializer with the exported fixture (75 schema definitions / 26 present / 49 schema-only), assigns every table a baseline capability ID and migration action, and carries the scope gap into the cutover artifact as an explicit open exception; it never treats the fixture as full ERP coverage. |
| Credential-free full-export contract | `scripts/erp_export_contract.py` + `docs/ERP_FULL_EXPORT_CONTRACT.md` | Verifies per-table hashes, row counts, safe paths, primary-key identity, recursive secret rejection, and 75-table coverage before staging; the current snapshot is correctly reported as `source_export_incomplete` with 49 missing tables. |
| ERP source-export request | `scripts/erp_source_export_request.py` + `docs/ERP_SOURCE_EXPORT_REQUEST.md` | Generates an exact read-only, credential-free request for all 49 absent tables, including wave, capability, primary-key, hash, and redaction requirements; it remains `awaiting_source_export`. |
| ERP MySQL metadata probe | `scripts/erp_mysql_inventory.mjs` + `docs/ERP_MYSQL_SOURCE_PROBE.md` | Uses the configured ERP source only for table/row-count/primary-key metadata, never payloads or credentials; the configured endpoint currently returns `ECONNREFUSED`, so the SQLite snapshot remains authoritative. |
| Migration completion audit | `docs/MIGRATION_COMPLETION_AUDIT.md` | Separates repository-verified requirements from the incomplete source export, provider approvals, business acceptance, shadow operation, and ownership-transfer gates. |
| Source row-coverage ledger | `scripts/erp_row_coverage.py` + `docs/ERP_ROW_COVERAGE.md` | Reads source identities and all native promotion/evidence receipts, accounts for aggregated workflow/investment/parameter rows, and verifies all 120 available rows have disposition coverage without authorizing promotion. |
| Business-acceptance packet | `scripts/company_business_acceptance_check.py` + `docs/BUSINESS_ACCEPTANCE_PACKET.md` | Validates five named business/finance/operations/migration-owner decisions against the source snapshot and technical evidence; the example remains `acceptance_pending` and cannot authorize cutover. |
| Read-only shadow-period contract | `scripts/company_shadow_period_check.py` + `docs/SHADOW_PERIOD_CONTRACT.md` | Binds legacy authority, disabled target mutations, comparison dimensions, duration, parity, row coverage, accounting no-effect, and rollback evidence; the example remains `shadow_pending_owner`. |
| ERP schema-only cohort plan | `scripts/erp_schema_cohort_plan.py` + `docs/ERP_SCHEMA_COHORTS.md` | Orders all 49 absent tables into seven capability/dependency waves with explicit credential, token, attachment, email, and retention actions; the rehearsal and cutover gate verify the plan while keeping authorization false. |
| ERP foundation-security schema mapping | `scripts/erp_schema_cohort_mapping.py` + `docs/ERP_FOUNDATION_SECURITY_COHORT.md` | Maps all six first-wave tables to evidence, parameters, identity security, RBAC, and preference boundaries; the current snapshot has zero rows, so the artifact is `mapped_scope_only` and cannot authorize promotion. |
| ERP workflow-control schema mapping | `scripts/erp_schema_cohort_mapping.py` + `docs/ERP_WORKFLOW_CONTROL_SCHEMA_COHORT.md` | Maps seven approval/runtime-assignee/warning tables to workflow and intelligence boundaries; custom SQL is not executed implicitly, and zero available source rows keep the artifact non-promotable. |
| ERP cost-investment schema mapping | `scripts/erp_schema_cohort_mapping.py` + `docs/ERP_COST_INVESTMENT_SCHEMA_COHORT.md` | Maps nine CBS and investment-model tables to governed configuration/evidence boundaries; no budget, accounting, formula, or investment effect is inferred, and zero source rows keep the artifact non-promotable. |
| ERP procurement-contract schema mapping | `scripts/erp_schema_cohort_mapping.py` + `docs/ERP_PROCUREMENT_CONTRACT_SCHEMA_COHORT.md` | Maps seven supplier/tender/contract/milestone tables to procurement and contract boundaries; awards do not create commitments or payments, and zero source rows keep the artifact non-promotable. |
| ERP sales-receivables schema mapping | `scripts/erp_schema_cohort_mapping.py` + `docs/ERP_SALES_RECEIVABLES_SCHEMA_COHORT.md` | Maps eight customer/invoice/refund/revenue tables to sales, payable, receivable, and tax boundaries; collection, revenue, tax, and cash remain separate, and zero source rows keep the artifact non-promotable. |
| ERP delivery-treasury schema mapping | `scripts/erp_schema_cohort_mapping.py` + `docs/ERP_DELIVERY_TREASURY_SCHEMA_COHORT.md` | Maps eight delivery/treasury/marketing tables; evidence, acceptance, planning, dispatch, and spend remain separate, and zero source rows keep the artifact non-promotable. |
| ERP reporting-notification schema mapping | `scripts/erp_schema_cohort_mapping.py` + `docs/ERP_REPORTING_NOTIFICATION_SCHEMA_COHORT.md` | Maps four message/email/report/share tables; tokens are excluded, templates are allow-listed, and zero source rows keep the artifact non-promotable. |
| ERP relationship/orphan audit gate | `scripts/erp_relationship_audit.py` + `scripts/erp_migration_rehearsal.sh` + `scripts/company_migration_cutover_gate.py` | Executes 60 reviewed source relationships across the 26-table fixture, checks 216 non-empty references, and currently finds zero orphans. The report is source-side evidence and does not imply target ownership. |
| ERP route-surface inventory gate | `scripts/erp_route_inventory.py` + `scripts/erp_migration_rehearsal.sh` + `scripts/company_migration_cutover_gate.py` | Parses the actual ERP route directory into capability-tagged handler records: 30 route files, 338 `r.get/post/put/patch/delete` handlers, and 28 `r.use` middleware registrations. Every route carries a `specify_and_scenario_verify` migration action. |
| End-to-end ERP rehearsal | `scripts/erp_migration_rehearsal.sh` | Runs backup extraction, redacted export, raw staging, and durable SQLite apply as one repeatable read-only-source command; a second run inserts zero rows. |
| Mapped-cohort promotion plan | `scripts/erp_promotion_plan.py` + `docs/ERP_PROMOTION_MAPPING.md` | Reads the real sanitized export, applies explicit principal/counterparty/employee/currency/cost mappings and fixed-point policy, emits 19 candidate items, and quarantines unresolved mappings instead of guessing. |
| Mapped-cohort domain promotion | `cmd/promote` + `migration/erp` | Native MoonBit command refuses quarantined plans and applies the 19 ready candidates through business-unit, project, contract, cost, and advance domain importers, emitting a source/mapping/count receipt. |
| Typed workflow-definition promotion | `scripts/erp_workflow_promotion_plan.py` + `cmd/promote` + `migration/erp` | Actual export rows produce 2 ready process definitions and 12 ordered steps under explicit capability mappings; a missing step mapping quarantines its process before domain import. |
| Typed project-lifecycle promotion | `scripts/erp_lifecycle_promotion_plan.py` + `cmd/promote` + `migration/erp` | Actual export rows produce 2 ready project masters and 2 lifecycle cohorts; explicit stage mappings replay `proj-0001` to development and `proj-0002` to design under project-scoped authority. Missing stage mappings quarantine before domain import. |
| Typed project-task structure promotion | `scripts/erp_task_promotion_plan.py` + `cmd/promote` + `migration/erp` | Actual export rows produce 2 ready project task plans containing 7 and 2 dependency-ordered tasks. Structure is promoted under `project:task:add`; source state/progress remains evidence because the fixture's child-state history conflicts with target dependency replay. |
| Typed cohort durable projection/parity runner | `scripts/erp_typed_cohort_rehearsal.sh` + `scripts/erp_mapping_variant.py` | Eight separately versioned business cohorts plus the clean project-2 task-state cohort and a typed-evidence cohort promote 74 accepted typed items into SQLite projections; every reopened cohort reports exact `shadow_verified` parity, and a second run inserts zero projections. |
| Typed evidence preservation cohort | `scripts/erp_typed_evidence_promotion_plan.py` + `cmd/promote` + `persistence/store` | Nine task snapshots, one task report, six workflow assignees, fourteen lifecycle-instance history rows, seven lifecycle catalog rows, and three proceeding rows are preserved as 40 evidence-only projections. Secret-shaped fields are rejected, source identity is checked, and no authority, workflow, or economic state is inferred. |
| Typed investment-model promotion and evaluation | `scripts/erp_investment_promotion_plan.py` + `cmd/promote` + `cmd/investment_model_eval` + `investment/model` | Actual export rows produce 1 ready investment model with 26 indexes under explicit version/index authority; the follow-on evaluator classifies numeric/date/source values, checks three parent totals, derives four explicit ratio metrics, and persists a source-bound analytics-only projection without execution, position, accounting, or cash effects. Unknown formula semantics remain preserved evidence. |
| Typed commitment-state/payment promotion | `scripts/erp_payment_promotion_plan.py` + `cmd/promote` + `migration/erp` | An explicit contract-state map replays 2 commitments through performed, turns 4 payment-plan rows into planned milestones, and turns 3 applications into requested settlements; approval, cash release, reconciliation, and accounting remain separate target events. Missing state mapping quarantines the cohort. |
| Credential-free user promotion | `scripts/erp_user_promotion_plan.py` + `cmd/promote` + `migration/erp` + `foundation` | Actual export rows promote 5 user identities with principal/business-unit/department assignment and enabled state. Passwords, network data, authentication timestamps, and legacy super-user privilege remain excluded or evidence-only. |
| Explicit audit-record promotion | `scripts/erp_audit_promotion_plan.py` + `cmd/promote` + `migration/erp` + `foundation/evidence` | Actual export rows promote 2 audit records only with explicit target/outcome mappings and actor-scoped append grants; missing mappings quarantine, and redacted network fields remain excluded. |
| Parameter/dictionary promotion | `scripts/erp_parameter_promotion_plan.py` + `cmd/promote` + `migration/erp` + `foundation` | Actual export rows promote 2 opaque dictionaries with 8 options under explicit principal/scope grants: 5 `cost_subject` options plus 3 `expense_proceeding` options from `vys_proceeding`; no CBS, accounting, tax, expense-state, or authority meaning is inferred. |
| Task-state/progress exception gate | `scripts/erp_task_state_promotion_plan.py` + `scripts/erp_task_state_exception_review.py` + `cmd/promote` + `migration/erp` | Target dependency simulation quarantines 2 inconsistent child states for `proj-0001`; the clean `proj-0002` cohort replays 2 states natively. A review-only artifact records exact conflicts and requires a named decision; no source state is coerced around a missing dependency. |
| ERP delivery-progress draft cohort | `scripts/erp_delivery_progress_plan.py` + `cmd/delivery_progress` + `operations/delivery` + `persistence/store` | The fixture's `jd_task_report` row can become one explicitly mapped `Draft` progress report with evidence and zero completed value; acceptance, recognition, cost/budget effects, and task-state mutation remain false and exact parity/replay are supported. |
| ERP reviewed delivery-recognition cohort | `scripts/erp_delivery_recognition_plan.py` + `cmd/delivery_recognition` + `operations/delivery` + `persistence/store` | A separately reviewed acceptance mapping requires acceptance evidence, a positive measured amount, and explicit ledger accounts; native promotion emits a `pending_posting` `delivery_recognition` projection with `posted=false`, `cash_released=false`, and `period_closed=false`. No available source row is promoted through this gate yet. |
| ERP fixture importer and migration envelopes | `migration/erp` | Representative project, contract, cost, supplier, tender, milestone, invoice, expense, and employee-loan row translation; typed task/progress, payment, workflow, lifecycle, investment-index, parameter, proceeding, user/audit, and loan-offset envelopes; explicit project-plan and workflow-domain importers; schema-bound JSON envelopes; and raw-row staging for unmapped tables. |
| ERP snapshot inventory | `migration/erp` | Metadata-only inventory of the available 26-table/120-row SQLite backup, with mapped, typed-staged, planned, and empty dispositions and a full-table executable shadow plan. |
| Credential-safe ERP row export | `scripts/erp_snapshot_export.sh` | Deterministic read-only export of all 26 snapshot tables with secret-key redaction, stable row ordering, per-table hashes, and a source-hash manifest; output remains outside target ownership. |
| Raw staging-envelope bridge | `scripts/erp_snapshot_stage_raw.sh` | Consumes only the redacted export, emits one `legacy/raw/<table>` envelope per source row, preserves exporter primary-key identity, and fails closed on secret-shaped fields or missing IDs. |
| Raw staging batch contract | `migration/erp` | Enforces unique table/primary-key and source identities before opaque raw envelopes can enter a manifest. |
| Migration manifest and atomic apply | `migration/manifest` | Per-source disposition, quarantine reason, canonical source-identity checks, target-envelope matching, all-or-nothing store apply, and rollback states. |
| Shadow parity report | `migration/parity` | Count/minor-unit comparison metrics with exact, tolerance, and mismatch classifications plus an explicit acceptance gate. |
| Migration receipt and rollback gate | `migration/run` | Immutable baseline/applied receipt, parity certification, and fail-closed rollback when post-apply writes are detected. |
| Reproducible shadow plan | `migration/shadow` | Derives record-count metrics from the target store and combines them with provided source control totals for repeatable parity certification. |
| Opening control totals | `migration/control` | Validates non-negative, unique domain control totals and compiles them into reproducible shadow expectations for opening-state reconciliation. |
| Budget reservation | `finance` | Reserve, consume, release, and overrun tests. |
| Commitment lifecycle | `operations/commitment` | Draft → submitted → approved → performed → settled plus cancellation guard. |
| ERP contract promotion | `migration/erp` + `operations/commitment` | Contract rows require explicit legal principal, project scope, counterparty identity, and amount-bounded creation grants before becoming commitments. |
| Budget linkage | `operations/commitment` | Explicit commitment-to-budget reservation, consumption, release, currency, and amount checks. |
| Commitment recognition | `operations/commitment` | Performed commitment → expense/payable balanced recognition journal. |
| Commitment/settlement/expense accounting-event adapters | `operations/commitment` + `operations/settlement` + `operations/expense` + `finance/accounting` | Validated source-to-journal events can be appended with source-identity replay protection; posting authorization remains local to the accounting book. |
| Commitment aggregate projection | `operations/commitment` + `persistence/store` | Commitment snapshots serialize to immutable, revisioned projections with identity checks and source-event replay anchors. |
| Settlement and payment projection | `operations/settlement` | Performed commitment → authorized payment release → balanced payable/cash journal. |
| ERP payment-application import | `migration/erp` + `operations/settlement` + `cmd/promote` | A source payment application becomes a requested settlement only against an explicitly replayed performed commitment; source approval/payment flags never release cash implicitly. |
| ERP advance-offset promotion | `scripts/erp_advance_offset_promotion_plan.py` + `cmd/promote` + `migration/erp` | The fixture promotes one advance plus one explicitly mapped `cb_loan_offset` row; the native importer applies 150,000 minor units only after matching the imported loan, employee, principal, scope, and amount-bounded offset authority. |
| Settlement aggregate projection | `operations/settlement` + `persistence/store` | Requested/approved/released settlement snapshots persist as immutable revisioned projections with source-event anchors. |
| Project lifecycle | `operations/project` | Ordered project stages with scoped authority and lifecycle events. |
| ERP project-master promotion | `migration/erp` + `operations/project` | Project rows require explicit legal-principal/project-scope mappings and matching creation grants; BU relationships are not treated as ownership automatically. |
| ERP lifecycle import | `migration/erp` | Explicit source-stage mapping replays only the ordered current target stage and leaves historical status/progress in the source envelope. |
| Project plan and task dependencies | `operations/project` | Dependency-gated task start, bounded progress, completion, blocking, and cancellation states. |
| ERP task-state import | `migration/erp` | Current `pending`/`in_progress`/`done`/`blocked` state replay is explicit, dependency ordered, and separately authorized from structural task import. |
| Project and plan aggregate projections | `operations/project` + `persistence/store` | Project lifecycle and task-plan snapshots persist stages, tasks, costs, dependencies, and progress as immutable projections. |
| Marketing campaign and placement | `operations/marketing` | Campaign budget, activation/completion, placement lifecycle, lead capture, and spend-cap controls. |
| Supplier and tender control | `operations/procurement` | Supplier qualification/blacklist states and planning → publishing → bidding → award → completion tender flow. |
| Supplier/tender aggregate projections | `operations/procurement` + `persistence/store` | Supplier qualification and awarded tender snapshots persist as immutable revisioned projections with bid/evaluation evidence. |
| Tender award-to-commitment boundary | `operations/procurement` + `operations/commitment` | An awarded qualified-supplier tender can create a draft commitment only through separate `tender:award-to-commitment` and `commitment:create` grants; no award, payment, or accounting effect is inferred implicitly. |
| Contract milestones | `operations/contract` | Time/progress/event-triggered milestone eligibility, achievement, payment, overdue, and cancellation states. |
| Contract milestone projections | `operations/contract` + `persistence/store` | Planned/eligible/reached/paid milestones persist plan, actual amount, trigger, and state as immutable projections. |
| Milestone-to-settlement boundary | `operations/contract` + `operations/settlement` + `persistence/store` | A reached milestone can create a requested settlement with a retained milestone ID through separate milestone and settlement grants; separate immutable milestone and settlement projections preserve the link while approval, release, cash, and accounting remain distinct. |
| Delivery progress and outputs | `operations/delivery` | Evidence-backed progress reports and deliverable acceptance/remediation states. |
| Delivery aggregate projections | `operations/delivery` + `persistence/store` | Accepted progress and deliverable snapshots persist evidence IDs, value/progress, and state as immutable projections. |
| Delivery-to-recognition boundary | `operations/delivery` + `finance/accounting` + `finance/cost` | Accepted, evidence-backed progress supplies the cost-forecast progress input and can construct a validated source-to-journal recognition event; journal posting, cash, tax, and revenue policy remain separate. |
| Dynamic cost | `finance/cost` | Deterministic `B = D + E + F + G` fixed-point component calculation. |
| ERP dynamic-cost promotion | `migration/erp` + `finance/cost` | Cost cohorts retain source cost identity and project scope while validating component arithmetic; duplicate IDs and negative components fail closed. |
| Dynamic-cost aggregate projection | `finance/cost` + `persistence/store` | Four-component breakdown and total persist as immutable source-linked cost envelopes. |
| Cost forecast | `finance/cost` | Target/committed/actual cost forecast linked to accepted progress with signed variance. |
| Cost-forecast aggregate projection | `finance/cost` + `persistence/store` | Progress-linked forecast-at-completion and signed variance persist as revisioned projections. |
| Sales agreement | `operations/sales` | Reserved → signed → fulfilled customer agreement lifecycle. |
| Sales-to-receivable boundary | `operations/sales` + `finance/receivable` | A fulfilled sales agreement can open a receivable through separate sales-recognition and receivable-opening grants; collection cash and revenue accounting remain separate. |
| Invoice-to-receivable boundary | `operations/invoice` + `finance/receivable` | An accepted invoice can open a receivable through separate invoice-recognition and receivable-opening grants, retaining the invoice as source identity; collection cash and revenue accounting remain separate. |
| Customer, reservation, mortgage, refund | `operations/sales` | Customer state, reservation conversion, mortgage approval/release, and refund approval/payment controls. |
| Receivable | `finance/receivable` | Open, partial, complete, and over-collection-controlled customer balances, with explicit opening receivable-to-revenue and separate collection cash-settlement accounting-event adapters. |
| Receivable aggregate projection | `finance/receivable` + `persistence/store` | Open/collected snapshots persist as immutable revisioned projections with source-event anchors. |
| Payable | `finance/payable` | Supplier obligation, partial/full payment, overpayment, and void controls, with explicit opening expense-to-payable and separate payment cash-settlement accounting-event adapters. |
| Payable aggregate projection | `finance/payable` + `persistence/store` | Open/paid/voided snapshots persist as immutable revisioned projections with source-event anchors. |
| Invoice lifecycle | `operations/invoice` | Issue, accept, void, partial payment, full payment, and overpayment controls. |
| Invoice aggregate projection | `operations/invoice` + `persistence/store` | Draft/accepted/paid/voided snapshots persist as immutable revisioned projections with source-event anchors. |
| Employee advance | `finance/employee_finance` | Open, partial repayment, full repayment, and scoped offset controls. |
| ERP employee-advance promotion | `migration/erp` + `finance/employee_finance` | Loan rows require explicit legal principal, employee identity/scope, currency, and amount-bounded creation grants; source BU identity is not reused as ownership. |
| Employee advance projections | `finance/employee_finance` + `persistence/store` | Advance amounts, repayments, employee identity, and balance state persist as immutable projections. |
| Expense claim | `operations/expense` | Multidimensional allocation, approval state, and deterministic advance offsetting. |
| Expense projection and recognition journal | `operations/expense` + `persistence/store` | Allocations, advance offsets, approval state, and balanced expense-recognition journal persist with source identity. |
| Weighted workflow | `operations/workflow` | Step-specific authority, weighted approvals, duplicate-action and wrong-step guards. |
| ERP workflow-definition cohort promotion | `migration/erp` + `operations/workflow` | Process definitions receive isolated ordered source steps and explicit local capability mappings; source labels never become authority implicitly. |
| Workflow definition/instance projections | `operations/workflow` + `persistence/store` | Approval steps, actions, current step, and decision status persist as immutable projections. |
| ERP workflow-assignment cohort | `scripts/erp_workflow_assignment_plan.py` + `cmd/workflow_assignment` + `operations/workflow` + `foundation/access` + `persistence/store` | Six `wf_step_assignee` rows receive explicit actor identities, process scopes, and capabilities; native promotion validates typed process/step attachment evidence, projections persist configuration-only/non-authorizing markers, delegated decisions retain bounded effective-window/revocation evidence, and SLA policies retain due/overdue observation evidence without approval mutation. Exact parity/replay persists the cohort and decision-time capability checks remain mandatory. |
| CBS subject/version | `finance/cbs` | Draft/active/frozen subject dictionary with duplicate-code and target-total controls. |
| CBS aggregate projections | `finance/cbs` + `persistence/store` | Subject versions persist targets, hierarchy, state, and totals as immutable revisioned projections; subject-scoped budget ledgers persist reservation/consumption state separately. |
| CBS cost-subject link | `finance/cbs` + `persistence/store` | Active/frozen CBS versions accept scoped source-to-subject cost links with explicit source identity and immutable link projections; separate budget-ledger reservation/consumption and broader schema/source coverage remain distinct. |
| ERP CBS cost-link cohort | `scripts/erp_cbs_cost_link_plan.py` + `cmd/cbs_link` + `cmd/cbs_budget` + `persistence/store` | An eighth, independently mapped cohort translates all 7 non-empty `cb_cost` rows into explicit CBS subject links and one deduplicated `cbs_version` configuration projection, persists exact parity, and replays idempotently without budget consumption or accounting posting; an opt-in budget plan now persists subject-scoped control evidence. |
| Agent boundary | `intelligence/agent_port` | MoonClaw-neutral request/result contracts with authority ceiling and idempotency. |
| Warning findings | `intelligence/warning` + `cmd/warning` + `scripts/erp_warning_plan.py` + `persistence/store` | Deterministic cost-overrun finding plus scoped acknowledge/resolve/suppress lifecycle; the source planner scans explicitly named `cb_cost` leaf rows and persists immutable warning evidence with non-notification, non-workflow, non-cash, and non-accounting markers. |
| Investment analytics seed | `investment/analytics` | Deterministic moving average and trend fixture translated from Moonfish intent. |
| Investment mandate and proposal | `investment/domain` | Local mandate limits, deterministic analysis attachment, proposal approval, controlled execution, and position creation. |
| Investment mandate/proposal/position projections | `investment/domain` + `persistence/store` | Mandate limits, Moonfish analysis evidence, proposal states, executed positions, validated acquisition journals, and acquisition accounting-event links persist as immutable revisioned evidence. |
| Versioned investment model | `investment/model` + `persistence/store` | ERP version/index rows become a governed local model with duplicate/version checks, source-value preservation, explicit authority, and revisioned model/evaluation projections; numeric/date classification, parent-total reconciliation, and known ratio derivations remain analytics-only. |
| ERP investment-model cohort promotion | `migration/erp` + `investment/model` | Version mappings isolate index rows, require explicit principal/grants, and reject duplicate versions or stray indexes before promotion. |
| Investment portfolio and valuation | `investment/portfolio` + `cmd/investment_benchmark` | Mandate-bound position book, exposure limits, explicit quote valuation, deterministic period-scoped per-position performance attribution and benchmark active-return comparison, source-snapshot/mapping/evidence-bound external benchmark reconciliation with tolerance and analytics-only projection markers, missing-evidence guards, and gain/loss mark-to-market source-to-journal adapters with explicit valuation authority; cash and accounting-book posting remain separate. |
| Portfolio risk scenarios and projections | `investment/portfolio` + `persistence/store` | Shock-based stress reports, loss limits, portfolio position snapshots, and mandate breach flags persist as governed evidence. |
| Reconciliation report | `finance/reconciliation` | Expected-versus-actual lines and journal-side comparison with explicit currency and balance errors. |
| Consolidated reporting evidence | `finance/reporting` + `cmd/consolidated_report` + `persistence/store` | Source-snapshot-bound balanced sections combine into a deterministic `consolidated_report` projection with control totals, mapping versions, accounting-link counts, and explicit non-posting cash/period/tax flags. |
| Tax obligation | `finance/tax` | Rate-based calculation, review, filing, payment, voiding, authority-scoped events, and a reviewed-state tax-obligation recognition-event adapter that produces a balanced source-to-journal link without posting. |
| Tax obligation projections | `finance/tax` + `persistence/store` | Jurisdiction/category, rates, calculated amounts, filing state, and source references persist as immutable projections. |
| Tax filing aggregate | `finance/tax` + `persistence/store` | Reviewed obligations can create a separate period/authority-referenced filing record with prepared/submitted/accepted/rejected state and immutable projections; tax payment and ledger posting remain separate. |
| Cash and bank movement | `finance/treasury` | Account balance, inflow/outflow approval, release, overdraw protection, and reconciliation. |
| Cash account/movement projections | `finance/treasury` + `persistence/store` | Balances, bank references, release state, direction, and reconciliation events persist as immutable projections. |
| Bank statement import/reconciliation | `finance/treasury` + `persistence/store` | Statement lines validate account/currency/balance invariants, match released or reconciled cash movements exactly once, and can then match each line to a balanced accounting event by source identity; the aggregate persists imported/reconciled/ledger-reconciled evidence without releasing cash or posting journals. |
| Cash planning and dispatch | `finance/treasury` | Planned/confirmed/actualized cash plans and approved project-to-project fund dispatch. |
| Corporate financing facility | `finance/financing` | Facility approval, activation, draw limit, interest accrual, repayment, closure, and default controls, plus explicit draw/repayment source-to-journal adapters with stable action IDs; accounting-book posting remains separate. |
| Financing facility projections | `finance/financing` + `persistence/store` | Limits, draws, outstanding principal, rates, repayment, and default state persist as immutable projections. |
| Asset lifecycle and depreciation/disposal | `finance/assets` | Capitalization, activation, impairment/disposal states, residual-value controls, deterministic monthly depreciation, balanced depreciation and derecognition journals, revisioned asset-register projections, and depreciation/disposal accounting-event links. Period close integration and production asset-import cohorts remain pending. |

## Current verification

The current scaffold has 242 passing MoonBit tests across the new packages. The
CLI demonstrates an authorized commitment through settlement and journal
validation, followed by a manifest-to-store migration apply and derived shadow
parity certification; it also reports the sanitized backup inventory as 26
tables, 120 rows, 19 rows covered by mapped import seams, and 101 rows covered by
typed preservation envelopes; the production-oriented SQL catalog has four
versioned gates. The ERP
fixture importer exercises representative project,
contract, and dynamic-cost translation. Snapshot/file persistence, tax
calculation, cash release, financing, investment approval, portfolio valuation, delivery evidence,
cost forecasting, backup/restore, accounting-event replay protection, audit replay protection, and reconciliation are covered by
package tests.
Delivery tests now require accepted, evidence-backed progress before creating
either a cost forecast input or a balanced delivery recognition event, and the
event can be appended as a source-identifiable accounting record without
posting it. CBS tests likewise require an active or frozen version and an
existing subject before a scoped source-to-subject cost link can be projected.
Opening control totals now compile into shadow expectations and reject duplicate
or negative controls before certification. The SQLite backup can now be exported
into a credential-safe, hashed row bundle for relationship review and later
typed/domain import, without putting raw source payloads into the repository.
The redacted fixture stages all 120 rows with 120 unique source IDs; those rows
remain quarantine evidence until a domain importer and authority grant promote
them. The SQLite rehearsal persists all 120 envelopes durably and reopens the
database with 120 unique records and one migration receipt; a second replay
inserts zero rows. The mapped-cohort planner produces 19 ready candidates with
the reviewed fixture mapping and quarantines 3 items when counterparty/employee
mappings are removed.
The native domain-promotion command then applies the complete plan and emits a
receipt with 7 organization units, 2 projects, 2 commitments, 7 costs, and 1
advance; it refuses the incomplete plan before writing a receipt.
The end-to-end wrapper now applies that domain receipt to 19 immutable SQLite
aggregate projections in one transaction, records a projection receipt, and
replays it with zero inserted projections and `PRAGMA integrity_check=ok`.
The projection parity report then classifies the cohort as `shadow_verified`
with exact counts of 7 organization units, 2 projects, 2 commitments, 7 costs,
and 1 advance; applying a workflow receipt to that database produces a visible
missing/extra mismatch instead of a false pass.
The accounting-link plan/native command then validates 2 explicit commitment
journals plus 1 employee-advance opening journal and the SQLite adapter
persists 3 source-to-journal links with `integrity=ok`; a second apply inserts
zero links. This is traceability only:
cash release, accounting-book posting, and subledger recognition remain
separate authority-bearing events.
The wrapper also backs up the final database and reopens the restored file;
the fixture reports `backup_restore_verified` with equal logical digests across
120 raw records, 19 projections, 3 accounting links, and 3 migration receipts.
With the fifth offset-cohort mapping, the same end-to-end run reaches 21
projections, 4 accounting links, and 5 migration receipts; both the economic
and offset cohorts report `shadow_verified`.
The shared SQLite driver smoke gate also proves rollback (`0` rows) and commit
(`1` row) on an isolated database with integrity `ok`; the committed row uses
the exact parameterized SQL command emitted by `persistence/sql`.
The managed-production deployment validator now rejects raw DSNs and incomplete
TLS, pooling, backup, restore, rollback, observability, or approval manifests;
the checked-in example remains owner-unapproved and therefore cannot authorize
deployment.
The cutover gate combines those checks into `cutover-gate.json`: the full
fixture is technically ready for business acceptance, but it deliberately
does not authorize ownership transfer while the project-1 task-state,
managed-production deployment, and 49 schema-only-table scope exceptions
remain open. The gate includes a `schema_scope` check so every rehearsal
records the 75/26/49 boundary explicitly.
The schema-cohort planner also records all 49 absent tables in seven ordered
waves, and the cutover gate verifies that planning artifact without treating it
as imported data.
The source-side relationship audit now runs before raw staging because the
legacy schema declares no foreign keys; it checks 60 reviewed relationships and
216 non-empty references with zero orphan values, and the gate records that
result as `relationship_integrity` evidence.
Its accounting reconciliation check requires every supplied reviewed link cohort
to report `reconciled` without cash release or period posting. The extended
seventh-argument run reaches 7 durable links and 16 migration receipts.
The same command promotes the typed workflow cohort as 2 definitions/12 steps
and refuses a plan with a missing capability mapping.
The lifecycle planner/command promotes 2 project masters plus their 2 ordered
lifecycle cohorts, yielding final stages `development` and `design`; a missing
stage mapping is refused before output.
The task planner/command promotes 2 dependency-ordered task structures (7 and
2 tasks) while leaving source status/progress in typed evidence; a missing
principal is refused before output.
The investment planner/command promotes 1 model with 26 indexes while
preserving source value representations; a missing principal is refused before
output.
The payment planner/command replays 2 explicit commitment state paths, creates
4 planned milestones and 3 requested settlements without releasing cash;
removing one state map is refused before output.
The native milestone boundary also persists a reached milestone and its
requested settlement as separate projections with the milestone ID retained;
approval, release, cash, and accounting remain independent events.
The user planner/command promotes 5 credential-free identities; the legacy
super-user account is represented without granting target super-user authority.
The audit planner/command promotes 2 login audit records only with explicit
target interpretation and actor grants; removing those mappings is refused
before output.
The parameter planner/command promotes 2 dictionaries with 8 options,
including the explicit `vys_proceeding` expense catalog; removing either
principal/scope mapping is refused before output.
The task-state planner identifies the two `proj-0001` dependency conflicts and
refuses the full mixed cohort; a project-2-only plan proves 2 state replays
and its project, task-plan, and task-state receipt persists as 3 exact-parity
projections. The inconsistent project remains quarantine evidence.
The separate advance-offset planner/native command promotes the fixture's
`loan-001` plus `off-001` cohort, applies 150,000 minor units only after the
target advance is created, and its two projections pass exact parity. Missing
or mismatched offset mappings are quarantined before any receipt is written.
The typed-cohort rehearsal then promotes and durably projects 34 additional
business items across workflow, lifecycle, task structure, investment, payment,
credential-free users, audit, parameter, and clean project-2 task-state
cohorts, plus 40 redacted typed-evidence rows from task snapshots/reports,
workflow assignees, lifecycle-instance history, lifecycle-stage catalog, and
proceeding catalog, for 74 typed items in total. Each cohort has its own
mapping version and exact parity report; the complete database reaches 51
projections and 13 migration receipts before task-state; with the clean
project-2 state and typed-evidence cohorts it reaches 95 projections and 16
receipts. A second full run is idempotent.
With the optional eighth CBS cost-link mapping, the same target database
reaches 103 projections and 17 migration receipts; all seven `cb_cost` links
and the deduplicated `cbs_version` configuration report exact
`shadow_verified` parity and a second apply inserts zero rows.
With the optional ninth workflow-assignment mapping, it reaches 109 projections
and 18 migration receipts; all six assignee rows report exact parity and a
second apply inserts zero rows. Assignments remain configuration, not
authority. The typed investment cohort then adds one
`investment_model_evaluation` projection and one mapping-scoped receipt; the
next complete typed run therefore reaches 110 projections.
The assignment planner refuses missing source users, target identities,
processes, scopes, or capability mappings before native promotion.
With the optional eleventh delivery-progress mapping, the evaluation-aware
rehearsal reaches 111 projections and an exact `progress_report` parity/replay result;
the native receipt records `acceptance_created=false` and
`recognition_created=false`. The current complete SQLite run also derives a
source-bound CBS budget plan from the five positive `cb_cost.dfs_budget`
amounts, reaching 112 projections, 7 durable accounting links, and 21
migration receipts; the CBS budget ledger remains reservation evidence with
accounting and cash effects false. A source-bound warning scan over the two
explicit positive `cb_cost` component overruns adds one warning projection and
reaches 113 projections and 22 receipts while notification, workflow, cash,
and accounting effects remain false.
Access tests also reject incompatible role assignments both when a new role is
assigned and when a separation rule is added after existing assignments.
They also prove delegation effective windows, amount ceilings, revocation, and
wrong-actor rejection.

This does not yet prove full ERP parity, production accounting posting,
durable target-owned persistence/economic acceptance of the promoted cohort,
promotion of the remaining typed-staged rows, or production readiness.

## Next implementation slices

1. Put the PostgreSQL raw-envelope, aggregate-projection, and accounting-link
   adapters behind the selected production service/database pool with
   production backup/restore verification. The credential-free service gate
   now validates the required pool/auth/read-only boundary; the versioned SQL catalog,
   reference executor, in-memory batch, file journal, SQLite rehearsal
   boundary, PostgreSQL target boundary, cohort receipts, and mapped-cohort
   planner are executable. Production pooling, encryption, retention, and
   restore runbooks remain open.
2. Reconcile the quarantined task-state/progress exception with the business
   owner; retain source evidence for rows that lack target domain state or
   approved authority. The full task-state plan now emits a review-only
   artifact with observed rows and exact dependency conflicts. Workflow-
   definition, project-lifecycle, task structure, investment-model,
   commitment-state/payment, user, audit, parameter, and draft delivery-
   progress promotion now have durable projection/parity rehearsal gates;
   task-state replay remains a reviewed exception cohort.
3. Complete remaining cross-domain persistence links: workflow notification
   delivery and broader CBS configuration. Typed workflow-assignment
   attachment, effective-dated delegation/revocation evidence, and
   non-authorizing projection evidence are implemented, as is a separately
   reviewed pending-posting delivery recognition projection (the available
   source row remains quarantined). The reviewed CBS cost-link cohort now covers the seven fixture
   cost rows, a source-bound CBS budget planner now records five explicit
   `cb_cost.dfs_budget` reservations while the synthetic ledger exercises
   consumption controls, and a source-bound warning scan records the two
   explicit component overruns; full CBS schema/source coverage, real budget
   ownership, and notification routing remain open. Invoice/receivable and milestone/settlement projections now
   retain separate identities and cross-domain source links in the same store
   boundary.
4. Extend the reviewed accounting-link/subledger reconciliation gate from the
   two commitment events and one advance-opening event to advance offsets,
   loans, tax, financing, procurement, receivable collections, and payable
   payments; explicit receivable-collection and payable-payment event adapters
   and allow-list entries are now in place, while reviewed source cohorts and
   investment performance/valuation links remain to be reconciled. Opening
   receivable/payable recognition links are covered.
5. Add external bank/filing adapters and richer report access/consolidation;
   bank-statement import/reconciliation plus statement-to-ledger evidence, tax
   filing records, and disposal derecognition journals/accounting-event links
   are now implemented, while period-close integration still needs production
   statement and subledger evidence.
6. Complete a reviewed external benchmark/performance cohort and extend the
   explicit investment formula catalog around the persistent model, mandate,
   proposal, position, risk, valuation, and deterministic period-performance
   projections; numeric/date classification, parent-total checks, and four
   known ratio derivations are now source-bound analytics evidence, while
   source-feed acceptance, richer formula vocabulary, and full
   performance/accounting reconciliation remain open.
7. Add sanitized ERP export fixtures, opening-balance workbooks, and
   cross-domain parity reports for each migration cohort.
