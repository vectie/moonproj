# PostgreSQL Target Setup

Recorded: 2026-07-15
Target: local PostgreSQL 18 for Moonproj

Moonproj now uses PostgreSQL as its only production target. The ERP's MySQL
database is source-only and is never used as a Moonproj target.

The target runtime is pure MoonBit plus shell orchestration. The current Python
PostgreSQL adapters and migration scripts are temporary bridge evidence; they
are not the supported production runtime and must be replaced by MoonBit
commands/services before deployment.

The local PostgreSQL service is running on `/tmp:5432`. A dedicated local role
and database were created:

```text
PGHOST=/tmp
PGPORT=5432
PGUSER=moonproj
PGDATABASE=moonproj
```

The password is not stored in this repository. Supply it through `PGPASSWORD`,
`.pgpass`, a secret manager, or the service environment when running a target
adapter.

The PostgreSQL-only production gate rejects `mysql` as a target engine. The
SQLite driver remains a deterministic local rehearsal adapter for tests and
backup/replay checks; it is not the production target.

## Target apply

The credential-free raw staging artifact can be applied to this target with
the native MoonBit wrapper `scripts/company_postgres_target_apply.sh`. It validates the staging manifest,
applies the version-4 catalog, inserts opaque `company_record` envelopes in a
transaction, and finalizes an idempotent migration receipt. Supply the
password through PostgreSQL's normal secret mechanism; it is not a script
argument or repository value:

```text
PGHOST=/tmp PGPORT=5432 PGUSER=moonproj PGDATABASE=moonproj \
  scripts/company_postgres_target_apply.sh /path/to/raw-staging.ndjson
```

The former `company_postgres_target_apply.py` remains only as frozen bridge
evidence for shadow comparison; it is no longer invoked by the PostgreSQL
cohort rehearsal.

The local target was verified on the available redacted ERP snapshot with
schema version `4`, `120` staged and durable raw records, `115` aggregate
projections, `7` reviewed accounting-event links, and `24` cohort receipts
before optional posting.
Replaying the same staging artifact and reviewed receipts inserted `0` rows
and did not create duplicate receipts. Native aggregate promotion receipts
are persisted through `scripts/company_postgres_projection_apply.sh`, and
reviewed accounting-link receipts through
`scripts/company_postgres_accounting_link_apply.sh`. Both native adapters lock
their target table, reject event/source/journal conflicts, preserve immutable
revisions or links, write a cohort-scoped migration receipt, and make an
identical replay insert `0` rows. They do not infer business effects, release
cash, or post journals. The former Python adapters remain frozen bridge
evidence for shadow comparison only.

The reviewed posting boundary is separate: compile an explicit chart/period
map with the current bridge planner, validate it through
`cmd/accounting_post`, then pass the resulting domain receipt to
`scripts/company_postgres_projection_apply.sh`. The posting projection and its
parity/replay evidence use the same immutable target boundary; they still do
not release cash, file tax, close a period, or authorize ownership transfer.

For local browser verification, the native
`scripts/company_postgres_read_model_server.sh` serves the same target through
fixed read-only endpoints (`/api/health`,
`/api/company/summary`, `/api/company/receipts`, and
`/api/company/projections`). It is a development adapter only; production
authentication, pooling, TLS, observability, and command endpoints remain
deployment gates. The former Python server remains frozen bridge evidence for
shadow comparison.

The native runtime slice is available without Python through
`scripts/company_postgres_read_model.sh summary|receipts|projections
[aggregate_type]`. The MoonBit command runs only fixed allow-listed queries via
`psql`, inherits PostgreSQL connection settings (`PGHOST`, `PGPORT`, `PGUSER`,
`PGDATABASE`, and `PGPASSWORD`), and has been shadow-compared against the
development HTTP adapter. The native HTTP server and CLI are intentionally
read-only and bounded; they do not replace the authenticated HTTP service or
gateway yet.
The authenticated bounded runtime remains `scripts/company_postgres_service.py`
as frozen bridge evidence while its MoonBit replacement is ported.
It keeps reusable PostgreSQL sessions behind a fail-closed pool, requires a
bearer token from an environment variable and forwarded TLS, exposes the four
fixed reads, and now provides the local expense, contract, and payment-application
command verticals documented in `ERP_EXPENSE_RUNTIME_VERTICAL.md`,
`ERP_CONTRACT_RUNTIME_VERTICAL.md`, and
`ERP_PAYMENT_APPLICATION_RUNTIME_VERTICAL.md`. Put
`scripts/company_postgres_dev_gateway.py` in front of the browser to establish
the local HttpOnly session and signed actor assertion. Run
`scripts/company_postgres_service_smoke.py` against the local target to verify
the lifecycle, idempotency, audit, missing-token, and forwarded-TLS contract;
managed provider deployment and token issuer/audience validation remain
separate gates.
The credential-free `company_production_service_check.py` now validates the
service boundary separately: bounded reusable pool, schema-matched readiness,
private TLS-terminated binding, authentication, fixed read endpoints, and no
arbitrary SQL or mutation routes. Its example remains owner-review evidence,
not a live deployment.

For a reviewed receipt, use the same PostgreSQL credential mechanism:

```text
PGHOST=/tmp PGPORT=5432 PGUSER=moonproj PGDATABASE=moonproj \
scripts/company_postgres_projection_apply.sh /path/to/domain-promotion.json

PGHOST=/tmp PGPORT=5432 PGUSER=moonproj PGDATABASE=moonproj \
  scripts/company_postgres_accounting_link_apply.sh /path/to/accounting-link-receipt.json
```

The repeatable cohort runner accepts the reviewed optional maps after the
core arguments. Supplying the CBS, workflow-assignment, delivery-progress,
advance-offset, and payment-accounting maps runs those cohorts through native
promotion, PostgreSQL parity, and replay as well:

```text
PGHOST=/tmp PGPORT=5432 PGUSER=moonproj PGDATABASE=moonproj \
  scripts/company_postgres_cohort_rehearsal.sh \
  /path/to/export scripts/fixtures/typed_cohort_mapping.json \
  /path/to/raw-staging.ndjson moonproj /tmp/moonproj-pg-rehearsal \
  scripts/fixtures/cbs_cost_link_mapping.json \
  scripts/fixtures/workflow_assignment_mapping.json \
  scripts/fixtures/delivery_progress_mapping.json \
  scripts/fixtures/advance_offset_mapping.json \
  scripts/fixtures/payment_accounting_link_mapping.json \
  "" "" "" "" "" "" "" \
  scripts/fixtures/cbs_budget_source_mapping.json \
  scripts/fixtures/warning_source_mapping.json \
  scripts/fixtures/accounting_link_mapping.json \
  scripts/fixtures/notification_plan.example.json \
  scripts/fixtures/access_plan.example.json \
  scripts/fixtures/accounting_posting_mapping.example.json \
  scripts/fixtures/opening_control_mapping.example.json \
  scripts/fixtures/tax_filing_mapping.example.json \
  scripts/fixtures/bank_statement_mapping.example.json
```

The seventeenth argument accepts the reviewed synthetic CBS budget plan. The
eighteenth argument can instead supply
`scripts/fixtures/cbs_budget_source_mapping.json`; when present, the CBS cost
mapping argument is also required and the runner derives a source-bound budget
plan from explicit positive `cb_cost.dfs_budget` values. These projections
remain budget-control evidence and do not post accounting or release cash.
The nineteenth argument can instead supply
`scripts/fixtures/warning_source_mapping.json`; the runner then derives a
source-bound warning from explicitly named positive `cb_cost` component
overruns. It preserves scan evidence but does not deliver notifications,
mutate workflows, release cash, or post accounting.

The twentieth argument supplies the reviewed base accounting-link map. When it
is present, the PostgreSQL cohort runner promotes the 19-item base domain
receipt, persists its exact parity/replay evidence, and applies the three base
source-to-journal links through the PostgreSQL accounting adapter. With all
reviewed options, the fresh target rehearsal reaches 113 aggregate projections,
7 accounting links, and 22 migration receipts; replay remains idempotent.
The twenty-first argument supplies the reviewed notification plan. It adds one
source-bound `notification_outbox` projection and receipt, so the complete
rehearsal reaches 114 projections, 7 accounting links, and 23 receipts. The
notification boundary records queue intent only; provider delivery,
workflow mutation, cash release, and accounting posting remain separate gates.
The twenty-second argument supplies the reviewed access plan. It adds one
native `access_directory` projection and receipt, so the complete rehearsal
reaches 115 projections, 7 accounting links, and 24 receipts. Role migration
is authority-reviewed and exact-scope; passwords, super-user privilege, and
workflow/cash/accounting effects remain excluded.
The twenty-third argument supplies the reviewed accounting-posting map. It
selects already-linked commitment events, validates the explicit chart and
period through the native accounting book, and adds two `accounting_posting`
projections with exact parity and idempotent replay. The resulting rehearsal
reaches 117 projections; opening balances, tax, cash, period close, and
production ownership remain open gates.
The twenty-fourth argument supplies the reviewed opening-control map. It runs
the native `migration/control` shadow compilation and persists five exact
control candidates with value/tolerance/unit/dimension parity. The resulting
rehearsal adds five aggregate projections and one receipt (122 projections in
the demonstrated posting-plus-opening run); identical replay remains
idempotent. These are reconciliation controls only and do not post accounting,
release cash, file tax, or close a period.
The twenty-fifth argument supplies the reviewed tax-filing map. It runs native
tax calculation/review/submission and persists two exact `tax_filing`
projections, including one accepted and one rejected filing, with candidate
parity and idempotent replay. The demonstrated posting-plus-opening-plus-tax
run reaches 124 aggregate projections. Tax payment, tax-authority calls,
accounting posting, cash release, and period close remain separate gates.
The twenty-sixth argument supplies the reviewed bank-statement map. It runs
native balance validation and persists one exact two-line `bank_statement`
projection with candidate parity and idempotent replay. The demonstrated
posting-plus-opening-plus-tax-plus-bank run reaches 125 aggregate projections.
Movement matching, ledger reconciliation, bank-provider calls, cash release,
accounting posting, and period close remain separate gates.
The twenty-seventh argument supplies the reviewed financing-facility map. It
runs native facility lifecycle and interest validation and persists one exact
`financing_facility` projection with candidate parity and idempotent replay.
The demonstrated full run reaches 126 aggregate projections. Lender calls,
cash disbursement/settlement, accounting posting, tax treatment, and period
close remain separate gates.
The twenty-eighth argument supplies the reviewed asset-lifecycle map. It runs
native capitalization, depreciation, and disposal validation and persists one
exact `asset` projection with candidate parity and idempotent replay. The
demonstrated full run reaches 127 aggregate projections. Journal posting,
disposal cash settlement, tax treatment, and period close remain separate
gates.
The twenty-ninth argument supplies the reviewed treasury plan/dispatch map. It
runs native cash-plan and inter-project dispatch lifecycle validation and
persists two `cash_plan` plus one `fund_dispatch` projection with candidate
parity and idempotent replay. The demonstrated full run reaches 130 aggregate
projections. Bank movement, cash settlement, accounting/tax treatment, and
period close remain separate gates.
The thirtieth argument supplies the reviewed invoice/subledger map. It runs
native invoice issue/accept, receivable opening/collection, and payable
opening/payment validation and persists two `invoice`, two `receivable`, and
one `payable` projection with exact parity and idempotent replay. The
demonstrated full run reaches 135 aggregate projections. Cash release,
revenue/expense posting, tax settlement, and period close remain separate
gates.
The thirty-first argument supplies the reviewed procurement cohort. It runs
supplier qualification, tender bidding/award, and separate commitment creation
and performance validation and persists two `supplier`, one `tender`, and one
`commitment` projection with exact parity and idempotent replay. The
demonstrated full run reaches 139 aggregate projections. Cash release,
accounting posting, settlement, tax treatment, and period close remain separate
gates.
The thirty-second argument supplies the reviewed investment-performance map. It
builds a bounded portfolio, attributes explicit quotes, and reconciles an
external benchmark observation, persisting one `investment_portfolio`, one
`investment_performance`, and one `investment_benchmark_reconciliation`
projection with exact parity and idempotent replay. The demonstrated full run
reaches 142 aggregate projections. Position mutation, cash release, accounting
posting, and period close remain separate gates.
The separate `scripts/company_investment_valuation_accounting_rehearsal.sh`
reuses the performance portfolio with an explicit valuation and accounting-link
map. It appends one `investment_valuation` source-to-journal link to the target,
reports exact PostgreSQL identity parity, and replays with zero inserts; it is
not part of the aggregate projection count and does not post journals, release
cash, mutate positions, or close a period.
The separate `scripts/company_invoice_procurement_accounting_rehearsal.sh`
adds three invoice/subledger opening links and one performed procurement
commitment link to the same PostgreSQL accounting-link table. Each receipt
reports exact identity parity and zero-insert replay; these links are outside
the aggregate projection count and do not release cash, post journals, settle
tax, or close a period.
The separate `scripts/company_tax_financing_accounting_rehearsal.sh` applies
two tax-recognition links and two financing draw/repayment links to the same
traceability table. Each native receipt reports exact PostgreSQL identity
parity and zero-insert replay; these links do not file/pay tax, call a lender,
release cash, post journals, or close a period. Run it with the four reviewed
source/accounting maps and the normal `PGHOST`, `PGPORT`, `PGUSER`, and
`PGPASSWORD` environment contract.
The separate `scripts/company_sales_cohort_rehearsal.sh` persists seven
reviewed sales/receivables projections (customer, subscription, agreement,
receivable, mortgage, refund, and revenue evidence) with exact PostgreSQL
identity parity and zero-insert replay. Collection, refund cash, revenue
recognition, book posting, and period close remain separate; the source rows
are synthetic because the available ERP snapshot has no accepted sales rows.
The separate `scripts/company_marketing_cohort_rehearsal.sh` persists four
reviewed marketing projections (campaign, placement, channel evidence, and
material evidence) with exact PostgreSQL parity and zero-insert replay. It
does not call a provider, consume a budget ledger, release cash, post
accounting, or close a period; the source rows are synthetic because the
available ERP snapshot has no accepted marketing rows.
The next optional cohort argument and standalone
`scripts/company_contract_milestone_rehearsal.sh` persist one performed
`commitment`, one reached `contract_milestone`, and one milestone-linked
requested `settlement` with exact PostgreSQL parity and zero-insert replay.
Approval, release, cash movement, accounting posting, tax, and period close
remain separate; the reviewed example is synthetic because the source export
is incomplete.
The following optional cohort argument and standalone
`scripts/company_expense_advance_cohort_rehearsal.sh` persist one partially
repaid `employee_advance`, one approved `expense_claim`, and one
`employee_advance_offset` with exact PostgreSQL parity and zero-insert replay.
The offset does not release cash or post accounting; the reviewed expense is
source-shaped because the available snapshot has no accepted expense rows.
The separate `scripts/company_expense_advance_accounting_rehearsal.sh` then
binds the advance issuance and offset identities to two reviewed journals.
It reports exact PostgreSQL identity parity and zero-insert replay through the
accounting-link table, while leaving the accounting book, cash, expense
recognition, and period close untouched.
It also emits `postgres-reconciliation.json`, which checks the durable
PostgreSQL event/source/journal/principal row against the domain candidate and
reviewed journal amount/currency; the report remains `period_posted=false` and
is readiness evidence only.
