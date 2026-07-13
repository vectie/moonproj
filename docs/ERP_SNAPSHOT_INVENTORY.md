# ERP Snapshot Inventory

Recorded: 2026-07-13  
Source: `../erp/erp_new/backup/erp-v0.1.0-snapshot.db`  
Target: this repository's migration rehearsal

This repository keeps a metadata-only inventory of the local ERP backup. It
records table counts and mapping status, not raw rows. Password hashes,
attachments, and authentication/network secrets are deliberately excluded from
the repository. A separate controlled export can preserve redacted row
payloads outside the repository for migration review.

The source file is a SQLite database with 26 application tables and 120 total
rows. Its SHA-256 is:

```text
4ff5dd0ad0b75c6cfc572f99047fe41c5df4b8c48d3877f707fe063aec7dea03
```

Five mapped table families account for 19 rows. Sixteen additional table
families have typed preservation envelopes covering 101 rows, but are not yet
target-owned state machines. Five tables are present but empty. The distinction
is executable in `SnapshotInventory` rather than being an informal estimate.

`Mapped` means that a target-domain translator API exists; it does not mean
that every source row is already accepted. For example, contract rows still
need a reviewed counterparty identity map when the source only supplies a
provider name. `Typed staged` means the source shape can be preserved and
reconciled, not that it may bypass target authority or workflow rules.

The counts are encoded in `migration/erp/snapshot.mbt` as
`sanitized_v0_1_0_snapshot()`. That function compiles the inventory into a
record-count shadow plan, so a missing importer is an explicit parity failure
instead of an invisible omission.

To measure a newer read-only backup without exporting raw data, run
`scripts/erp_snapshot_inventory.sh /path/to/backup.db`. The script reports the
file hash, table counts, and total rows only. To compare the backup against the
full schema initializer, run
`scripts/erp_schema_inventory.sh /path/to/server/src/db/index.js /path/to/backup.db`.
For a deterministic, credential-safe row export for a controlled rehearsal,
run `scripts/erp_snapshot_export.sh /path/to/backup.db /controlled/output`.
It writes one redacted JSON file per source table plus a manifest containing the
immutable source hash, row counts, and per-table hashes. It never writes to the
ERP database and its output is staging evidence, not target-owned data.
The rehearsal also runs `scripts/erp_export_contract.py`, which verifies every
exported file and compares the bundle against all 75 schema tables. The current
artifact therefore reports 26 verified export tables and 49 missing tables as
`source_export_incomplete`; a future complete MySQL/JSON export can reuse the
same contract before any raw staging or domain promotion.
Then run `scripts/erp_snapshot_stage_raw.sh /controlled/output /controlled/staging.ndjson`
to produce 120 raw envelopes for this fixture. The staging step accepts only the
redacted export directory, derives identities from the exporter-recorded primary
keys, checks that secret-shaped keys are absent, and fails closed on missing
identities or duplicate source IDs.
For a durable database rehearsal, run
`scripts/company_sqlite_rehearsal.py /controlled/staging.ndjson /controlled/company.sqlite3`.
It applies the four versioned company schema gates, writes the 120 envelopes and
one migration receipt transactionally, reopens the database for integrity and
count checks, and treats an identical replay as an idempotent no-op. The result
is still staging evidence, not target-owned aggregates.
The complete flow can be run with
`scripts/erp_migration_rehearsal.sh /path/to/backup.db /controlled/work-dir`
and an optional third argument for the approved promotion mapping file. A
fourth argument supplies a separately reviewed accounting-link mapping. A
fifth argument supplies a separately reviewed employee-advance-offset mapping
and accounting map. A sixth argument supplies the reviewed typed-cohort map.
A seventh argument supplies a separately reviewed payment-application
accounting-link map; it only traces requested settlements and does not release
cash.
An eighth argument supplies the optional reviewed CBS cost-subject map; it
promotes only explicit `cb_cost` source-to-subject links and does not consume
budget or post accounting.
A ninth argument supplies the optional reviewed workflow-assignment map; it
promotes only explicit `wf_step_assignee` configuration and does not grant
permissions or approve workflow instances.
A tenth argument supplies the credential-free managed-production deployment
manifest; the wrapper validates its pool, TLS, encryption, backup, restore,
rollback, observability, and approval contract without reading a database
secret.
An eleventh argument supplies the reviewed `jd_task_report` delivery-progress
mapping; it creates draft progress reports only and never accepts delivery,
recognizes value, consumes cost, or mutates task state.
The nineteenth argument supplies a reviewed warning plan; it emits a
source-bound `warning_finding` projection and keeps notification delivery,
workflow mutation, and cash effects false.
The twentieth argument supplies a reviewed CBS budget plan. The optional
twenty-first argument instead supplies a source-bound CBS budget mapping; it
requires the eighth CBS cost mapping, derives an explicit plan from positive
`cb_cost.dfs_budget` values, and keeps each consume decision review-bound.
The optional twenty-second argument supplies a source-bound warning mapping; it
derives an explicit cost-overrun finding from named `cb_cost` rows and rejects
any mismatch between the mapping and positive overruns.
The optional twenty-third argument supplies a reviewed notification plan; it
creates a source-bound `notification_outbox` projection with explicit queue
intent, but no provider delivery, workflow mutation, cash release, or
accounting posting.
The optional twenty-fourth argument supplies a reviewed access plan; it
validates local roles, bounded permissions, exact-scope assignments, and
segregation-of-duties rules before creating one `access_directory` projection.
It never imports passwords or source super-user privilege.
The optional twenty-seventh argument supplies a reviewed tax-filing map; it
drives native tax calculation/review/submission and persists filing evidence
only. Tax payment, authority calls, cash release, and accounting posting remain
separate gates.
The optional twenty-eighth argument supplies a reviewed bank-statement map; it
validates balanced statement evidence only. Movement matching, bank-provider
calls, cash release, and accounting posting remain separate gates.
The optional twenty-ninth argument supplies a reviewed financing-facility map;
it validates facility lifecycle and interest evidence only. Lender calls, cash
disbursement/settlement, accounting posting, tax treatment, and period close
remain separate gates.
The optional thirtieth argument supplies a reviewed asset-lifecycle map; it
validates capitalization, depreciation, and disposal evidence only. Journal
posting, disposal cash settlement, tax treatment, and period close remain
separate gates.
The optional thirty-first argument supplies a reviewed treasury plan/dispatch
map; it validates liquidity planning and dispatch approval evidence only. Bank
movement, cash release, settlement, accounting/tax treatment, and period close
remain separate gates.
Every rehearsal also emits `schema-cohort-plan.json`, which orders all 49
schema-only tables into seven future migration waves. Every rehearsal also emits
`relationship-audit.json`, which checks the reviewed
source relationship map before raw staging and fails closed on orphaned values.
It also emits `route-inventory.json`, covering the 30 route files, 338 handlers,
and 28 middleware registrations used by the parity baseline.
When accounting mappings are supplied, it emits `period-close-control.json`
as a no-posting readiness artifact; it never closes a production period.
When
provided, the wrapper also emits `promotion-plan.json`; it never promotes
quarantined candidates automatically. With a complete mapping, it additionally
invokes the native MoonBit domain-promotion command and emits
`domain-promotion.json`; a quarantined plan fails before that file is written.
The wrapper then applies that receipt to the SQLite aggregate-projection table
and emits `projection-apply.json`; replay is idempotent and integrity-checked.
It also emits `projection-parity.json`; the cohort must be `shadow_verified`
before it can advance to a later ownership gate. With the fourth argument it
also emits an accounting-link plan/native receipt and transactionally applies
the reviewed source-to-journal identities; a replay is an idempotent no-op and
the link does not release cash. The wrapper then creates a backup and verifies
the restored database's schema, integrity, counts, and logical digest. With the
sixth typed-cohort argument it also emits `cutover-gate.json`, which can reach
`ready_for_business_acceptance` but never authorizes cutover automatically.

| Source table | Rows | Target record type | Status |
|---|---:|---|---|
| `audit_log` | 2 | `legacy/audit_event` | Typed staged |
| `cb_contract` | 2 | `legacy/contract` | Mapped |
| `cb_cost` | 7 | `legacy/cost` | Mapped |
| `cb_expense_detail` | 0 | `legacy/expense_detail` | Empty source |
| `cb_expense_split` | 0 | `legacy/expense_split` | Empty source |
| `vcb_expense` | 0 | `legacy/expense` | Empty source |
| `cb_htfk_apply` | 3 | `legacy/payment_application` | Typed staged |
| `cb_htfkplan` | 4 | `legacy/payment_plan` | Typed staged |
| `cb_loan_offset` | 1 | `legacy/advance_offset` | Mapped (separate offset cohort) |
| `ep_project` | 2 | `legacy/project` | Mapped |
| `jd_task` | 9 | `legacy/task` | Typed evidence projection |
| `jd_task_report` | 1 | `legacy/task_report` | Typed evidence projection |
| `mu_business_unit` | 7 | `legacy/business_unit` | Mapped |
| `my_biz_param_option` | 5 | `legacy/parameter` | Typed staged |
| `proj_lifecycle_instance` | 14 | `legacy/project_lifecycle_instance` | Typed evidence projection |
| `proj_lifecycle_stage` | 7 | `legacy/project_lifecycle_stage` | Typed evidence projection |
| `sys_user` | 5 | `legacy/user` | Typed staged |
| `tzsy_plan_index` | 26 | `legacy/investment_index` | Typed staged |
| `tzsy_version` | 1 | `legacy/investment_version` | Typed staged |
| `vys_proceeding` | 3 | `legacy/proceeding` | Typed evidence projection |
| `vcb_loan_simple` | 1 | `legacy/advance` | Mapped |
| `wf_process_def` | 2 | `legacy/workflow_process_definition` | Typed staged |
| `wf_process_instance` | 0 | `legacy/workflow_process_instance` | Empty source |
| `wf_step_action` | 0 | `legacy/workflow_step_action` | Empty source |
| `wf_step_assignee` | 6 | `legacy/workflow_step_assignee` | Typed evidence projection |
| `wf_step_def` | 12 | `legacy/workflow_step_definition` | Typed staged |

## Interpretation

The backup is a small operational fixture, not the complete production
database. It is valuable because it exposes the actual schema and relationship
shapes, including project lifecycle, workflow, cost, payment-plan, loan-offset,
investment-index, and audit tables that were not represented by the first
fixture importers.

The ERP schema initializer defines 75 tables in
`../erp/erp_new/server/src/db/index.js`. The backup contains 26 of those tables,
so 49 schema tables are absent from this particular fixture. The absent families
include sales (`sale_*`), supplier/SRM (`srm_*`), tendering, invoices,
marketing, treasury plans, project delivery, investment model imports, warning
and notification tables, attachments, roles, reports, and CBS configuration.
The full schema definition—not the small backup—is therefore the authoritative
capability inventory for migration scope.

The current promotion rehearsals cover the five mapped families, workflow
definitions/steps, project masters/lifecycle instances, dependency-ordered
task structures, one investment model, four planned milestones, explicit
commitment/payment transitions, five credential-free user identities, two
explicitly mapped audit records, and two opaque parameter dictionaries with
eight options (including the three-row expense-proceeding catalog), plus a
dependency-checked task-state gate. They also preserve 40 non-empty typed rows
(including task snapshots and lifecycle-instance history) as queryable evidence projections
without treating them as business state. The next migration
cohort should therefore proceed in this order:

1. reconcile the quarantined task-state/progress exception with the business
   owner;
2. retain the zero-orphan relationship report, review the redacted export for
   semantic findings, and require the full 26-table shadow plan to pass before
   calling the snapshot reconciled.

The source backup remains read-only. No production ERP writes or destructive
changes are part of this inventory step.
