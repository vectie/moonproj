# ERP Promotion Mapping Contract

Recorded: 2026-07-13

`scripts/erp_promotion_plan.py` converts the credential-safe ERP export into a
reviewable promotion plan for the first mapped economic cohort. It does not
write company aggregates. The resulting candidates still pass through the
MoonBit domain importers and authority grants before target ownership.

Run it with:

```text
scripts/erp_promotion_plan.py \
  /controlled/export \
  /controlled/mapping.json \
  /controlled/promotion-plan.json
```

The mapping file is a governance artifact and must be versioned, reviewed, and
approved with the migration receipt. It must explicitly provide:

- `principal_by_bu`: source business-unit to legal-principal mapping;
- `counterparty_by_provider`: source supplier-name to target-counterparty mapping;
- `employee_by_user`: source operator/user to target employee mapping;
- `currency_by_bu`: currency policy for monetary source rows;
- `money_policy`: `minor_units_per_unit`, `rounding` (`half_even`), and whether
  rounding is allowed;
- `cost_component_map`: explicit source-column mapping for `direct`, `indirect`,
  `contingency`, and `other`.
- `workflow_capability_by_step` (for the typed workflow cohort): every source
  workflow step to a local capability string.
- `commitment_state_by_contract` (for the payment cohort): explicit target
  commitment state, such as `performed`, for each contract whose state will be
  replayed.

Use a fresh work directory when changing a source snapshot or mapping version.
Reusing a directory with a different receipt cohort fails closed on the
projection-receipt conflict; rerunning the identical source/mapping cohort is
the supported idempotent replay path.

The tool currently plans 19 source rows: 7 business units, 2 projects, 2
contracts, 7 costs, and 1 employee advance. Each output item contains its
source identity, target candidate, transformation metadata, warnings, and a
`ready_for_domain_import` or `quarantined` disposition. Missing principal,
counterparty, employee, currency, project, or money-policy evidence is a
quarantine reason; no fallback identity or currency is inferred.

The current fixture demonstrates both gates:

- with explicit fixture mappings, 19/19 items are ready for domain import;
- removing counterparty and employee mappings produces 16 ready items and 3
  quarantined items.

When the mapping file is passed as the third argument to
`scripts/erp_migration_rehearsal.sh`, the wrapper invokes
`moon run --target native cmd/promote` after planning. The domain command calls
the target import APIs and writes a domain-promotion receipt containing 7
organization units, 2 projects, 2 commitments, 7 costs, and 1 advance. It
refuses any quarantined item before invoking an importer.

Employee advances with a non-zero source balance carry a warning requiring a
separate explicit offset event. They are not silently imported as repaid. The
separate `scripts/erp_advance_offset_promotion_plan.py` requires an
`advance_offset_by_id` map and the native command applies the offset only to
the matching imported advance; the fixture replays `off-001` for 150,000 minor
units.

The typed workflow cohort uses the native
`scripts/erp_workflow_promotion_plan.sh` and the same native `cmd/promote`
boundary. All 12 source steps require capability mappings; a missing mapping
quarantines the affected process definition.

The project/lifecycle cohort uses the native
`scripts/erp_lifecycle_promotion_plan.sh`.
Its mapping file reuses `principal_by_bu` and adds
`lifecycle_stage_by_code`; this is mandatory because the ERP's `acquisition`
and `planning` labels do not have a safe one-to-one meaning in the target.
The current fixture produces 2 project-master and 2 lifecycle candidates. The
native command imports the projects first, then replays the ordered current
stage under a `project:advance` grant. Historical dates, status, and progress
remain in the source lifecycle envelope rather than being silently converted
to target events. With the reviewed fixture map the final stages are
`development` for `proj-0001` and `design` for `proj-0002`; removing a stage
mapping quarantines the affected project before any receipt is written.

The task-structure cohort uses the native
`scripts/erp_task_promotion_plan.sh`. It
promotes 7 tasks for `proj-0001` and 2 tasks for `proj-0002` only after
dependency identities and parent ordering are checked. Source status and
progress remain in the typed envelope; they are not replayed automatically.
This is intentional: the fixture reports child task completion while a parent
task is still in progress, so target state replay would violate the local
dependency invariant and must remain a separate, reviewed exception cohort.

The investment-model cohort uses the native
`scripts/erp_investment_promotion_plan.sh` wrapper.
The reviewed `principal_by_bu` mapping authorizes one version with 26 indexes;
the index values are preserved as source representations. After native import,
`cmd/investment_model_eval` classifies explicit numeric/date values, checks
parent totals, and derives only the known ratio metrics under a separate
mapping-scoped receipt; unknown units, formulas, tax, financing, and accounting
semantics remain evidence rather than approved effects. A missing principal or
stray index quarantines the cohort before the native importer runs.

The payment cohort uses the native `scripts/erp_payment_promotion_plan.sh`
wrapper and requires an
explicit `commitment_state_by_contract` map. With the reviewed fixture map,
the two contracts replay through submit/approve/perform, the four payment-plan
rows become planned contract milestones, and the three payment applications
become requested settlements. No application is approved,
released, reconciled, or posted automatically; legacy payment flags remain
evidence. Removing one state mapping quarantines the related state and refuses
the entire native promotion.

The separate `scripts/erp_contract_milestone_plan.py` cohort is the reviewed
post-promotion lifecycle check. It drives one performed commitment through an
eligible/reached progress milestone and creates a requested settlement with the
milestone identity retained. It is intentionally separate from the source
payment promotion: approval, release, cash, accounting, tax, and period close
remain false, and the incomplete export does not establish production
settlement acceptance.

The accounting-link cohort is intentionally a separate review artifact. Run
`scripts/erp_accounting_link_plan.py` against the domain receipt with a mapping
file containing `accounting_by_source` entries for each source commitment. Each
entry must name the event, journal, principal, scope, debit/credit accounts,
amount, currency, and event type. Commitment entries are checked against the
imported commitment; employee-advance entries are checked against the imported
advance amount, principal, and currency. The planner quarantines any mismatch.
The native
`cmd/accounting_link` command validates a balanced journal and append authority
before writing `accounting-link-receipt.json`; the optional fourth wrapper
argument applies that receipt to durable SQLite links. The fixture has 3 ready
links (2 commitments and 1 advance opening). These links establish traceability only: no cash movement, period
posting, or accounting policy is inferred. The wrapper emits an accounting
reconciliation receipt for each link cohort; it checks mapped amount, principal,
currency, and durable-link identity while keeping cash release and period
posting false.

Pass the separate offset mapping as the fifth argument to the rehearsal
wrapper to run the `cb_loan_offset` cohort end to end. It emits its own native
promotion, projection-parity, accounting-link, and replay receipts so the
offset cannot be mistaken for the opening advance or for cash settlement.

The separate `scripts/erp_expense_advance_cohort_plan.py` boundary is the
reviewed employee-finance lifecycle check. It keeps an approved allocated
expense separate from the advance and applies one explicit offset through the
native expense/advance grants. The available snapshot has no accepted expense
rows, so the example remains source-shaped and non-posting.

Pass `scripts/fixtures/payment_accounting_link_mapping.json` as the seventh
wrapper argument to validate the three `cb_htfk_apply` requested-settlement
links against the typed payment receipt. The map is explicitly restricted to
`payment_application`; the native receipt and durable apply add three links
without releasing cash or posting a period.

Pass `scripts/fixtures/cbs_cost_link_mapping.json` as the eighth wrapper
argument to run the independent CBS cost-subject cohort. The planner requires
an explicit project/version/subject and source amount mapping for every
non-empty `cb_cost` row; the native receipt and durable projection add seven
source-to-subject links for the fixture without consuming budget or posting
accounting.

Pass `scripts/fixtures/workflow_assignment_mapping.json` as the ninth wrapper
argument to migrate the six `wf_step_assignee` rows. The map requires explicit
target identities, process scopes, and step capabilities; the native receipt
and durable apply retain workflow configuration without creating permissions.

Pass a reviewed production deployment manifest as the tenth wrapper argument
to validate the managed-database contract. The validator checks the DSN
environment reference, pool, TLS, encryption, backup, restore, rollback,
observability, and owner-approval requirements without reading credentials.
The example manifest is intentionally unapproved.
Pass the reviewed production-service manifest as the sixteenth wrapper
argument (with the deployment manifest still supplied as argument ten) to
validate the authenticated fixed-read service boundary. It requires private
TLS-terminated binding, schema-matched readiness, bounded reusable pooling,
explicit HTTPS origins, and no arbitrary SQL or mutation routes; it remains
`ready_for_service_review` until the deployment gate is authorized.
Pass a reviewed consolidated-report plan as the seventeenth wrapper argument
to emit a source-snapshot-bound `consolidated_report` projection. Every
section must already be reconciled; the report remains non-posting and keeps
cash, period, and tax effects false.

Pass `scripts/fixtures/delivery_progress_mapping.json` as the eleventh wrapper
argument to translate the one `jd_task_report` row into a draft
`progress_report`. The map must explicitly identify the task's target project,
principal, scope, currency, value, and evidence references. The native receipt
retains report date/operator/summary provenance and sets acceptance and
recognition false; source task state remains a separate dependency gate.

The sixth wrapper argument supplies `typed_cohort_mapping.json` (or an
equivalent reviewed map). `scripts/erp_typed_cohort_rehearsal.sh` creates
cohort-specific mapping versions, promotes eight typed cohorts plus the clean
`proj-0002` task-state cohort through the native command, persists each
receipt, and requires exact reopened parity. The inconsistent `proj-0001`
task-state rows remain quarantined.
The same runner preserves 40 non-empty typed rows as
`typed_evidence` projections (task snapshots/reports, workflow assignees,
lifecycle history/catalog, and proceedings). These projections are queryable
evidence only and cannot create authority, workflow state, or accounting
meaning.

Run `scripts/erp_access_plan.py` against the complete export with a reviewed
access map, then pass its plan (or the checked-in synthetic
`scripts/fixtures/access_plan.example.json`) as the twenty-fourth SQLite
wrapper argument or twenty-second PostgreSQL cohort-runner argument to run the
reviewed access boundary. The native importer creates one exact-scope
`access_directory` projection after applying role, permission, and
segregation-of-duties validation; it never imports passwords or source
super-user privilege.

The user cohort uses `scripts/erp_user_promotion_plan.sh` (native
`cmd/user_promotion_plan`). It promotes the five
credential-free user identities with explicit business-unit principal mappings,
department references, and enabled state. Password hashes, login-network data,
authentication timestamps, and the legacy `super_user` bit are not imported;
the latter remains evidence and grants no target privilege.

The audit cohort uses `scripts/erp_audit_promotion_plan.sh` (native
`cmd/audit_promotion_plan`). Because the source
login rows have no target identity, each audit row requires an explicit target
and outcome mapping plus an actor-scoped `audit:append` grant. The current
fixture promotes 2 audit records; redacted network fields remain excluded.
Without those mappings the cohort is quarantined rather than inventing audit
targets.

The parameter cohort uses the native `scripts/erp_parameter_promotion_plan.sh`
wrapper. Its
`parameter_by_name` mapping explicitly names the owning principal and scope;
the optional `parameter_source_by_name` mapping explicitly selects a source
catalog. The fixture promotes the original `cost_subject` dictionary with 5
options plus an `expense_proceeding` dictionary with 3 options sourced from
`vys_proceeding`. Values remain opaque configuration and are not silently
treated as CBS subjects, accounts, tax codes, expense state, or authority
rules; proceeding manager/department/cost metadata remains source evidence.

Task-state replay uses `scripts/erp_task_state_promotion_plan.sh`. It simulates
target dependency completion before promotion. The full fixture quarantines
`proj-0001` because `task-003-1` and `task-003-2` report completion/progress
while `task-003` remains in progress. The clean `proj-0002` cohort replays 2
task states successfully; the inconsistent project remains source evidence.
