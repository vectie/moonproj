# ERP frontend clone (Rabbita)

This browser surface is a Rabbita port of the designer-built ERP in
`../erp/erp_new/web`: the login page, dark navigation hierarchy, header, and
dashboard are copied from the source UI language and labels. The major ERP
route families now have their own screen compositions—projects, plans,
workflow, AI, sales, cost/procurement, finance, analysis, and system
administration—with the source tables, tabs, KPI cards, forms, and action
boundaries represented as read-only fixtures. Inbox, attachments, health,
users/roles, profile, notifications, OCR, and webhook routes now retain their
distinct source layouts instead of sharing a generic administrative table.
The report center also opens a read-only `/share/:token`-shaped cost report
preview with the source metadata bar, dense summary table, expiry label, and
public-link boundary.
Detail routes accept arbitrary source identifiers (`/projects/:id`,
`/contracts/:id`, `/expenses/:id`, `/loans/:id`, and
`/srm/providers/:id`) instead of being limited to the reviewed fixture IDs;
the source dashboard redirect aliases are retained as well.

The UI is deliberately fixture-backed while the HTTP/API boundary is being
connected. It is a visual and interaction migration, not a claim that a button
already mutates company data. Representative project, contract, expense,
loan, and supplier detail/new flows now open as source-shaped forms with
explicit return/save/submit boundaries. The dashboard now reads the
PostgreSQL projection summary through the fixed read-only native MoonBit
adapter `scripts/company_postgres_read_model_server.sh`. The authenticated
bounded runtime is available separately as `scripts/company_postgres_service.sh`
plus the native gateway wrapper. The
dashboard group overview, stage funnel, and top-anomaly panels now load the
bounded source-backed cockpit reads in sequence, followed by a separate
read-only v2 KPI/payment-trend/stage/warning panel; `/dashboard-v3` also
mounts the source-shaped v3 health/KPI/expense/city/funnel/contract/gap
observations. Project KPI/anomaly deep-link reads are available through the
same service. Missing source tables remain visible, and the v3 panel is
explicitly an observation surface rather than management truth. Its
local command verticals include the expense lifecycle documented in
`docs/ERP_EXPENSE_RUNTIME_VERTICAL.md`, the contract lifecycle documented in
`docs/ERP_CONTRACT_RUNTIME_VERTICAL.md`, and the payment-application lifecycle
documented in `docs/ERP_PAYMENT_APPLICATION_RUNTIME_VERTICAL.md`, and the
procurement/tender lifecycle documented in
`docs/ERP_PROCUREMENT_RUNTIME_VERTICAL.md`. The
new-expense and contract routes are wired to the native local
create/submit/reject/resubmit/approve loops, while `/payment-applies` also
loads real application rows and exposes edit/void plus milestone eligibility
controls through the native local gateway below; `/tender` now loads
tender projections and exposes local planning/publish/bidding/cancellation
controls, including award/complete validation against a qualified supplier.
Imported tender rows remain read-only. `/srm/providers` now loads the separate
source-compatible ERP provider list when imported rows exist, preserves an
explicit empty/missing-source state, and keeps supplier qualification/scope
projections separate for local create/update/review, blacklist, and void
command states. Provider detail now reads the source provider, linked business
units, and historical contracts when available, while transport failure keeps
the designer detail form; the provider page also shows source-backed aggregate
stats with truthful zero counts and a per-provider source risk detail (score,
rating, tags, contract count, and overdue milestones). Risk-board reads and
contract-split reads/creates are available through the same boundary. The five
sales pages now load
PostgreSQL customer, reservation, agreement, mortgage, refund, revenue, and
receivable projections through the gateway and show their source/state/amount
metadata while preserving the source-shaped tables as an offline fallback. The
invoice page also reads reviewed invoice projections when an invoice cohort is
present. `/project/progress` and `/project-plan` now load the PostgreSQL
delivery overview and expose evidence-gated progress, output, and task-report
commands; imported task/progress/output rows remain read-only, while local
command projections are marked separately. Browser production-identity
acceptance is still pending. `/reports` now loads the five core report reads
through `/api/company/reports/overview` and shows source coverage; report
templates and sharing remain separate gates. `/loans` now loads
source-preserving employee-loan/offset reads; imported balances remain
read-only. `/cashflow` now loads `/api/company/cashflow/forecast` and the source
`/api/company/cashflow/inflow` read for a six-month project-scoped forecast, showing
payment-plan, application, expense, loan, and revenue evidence with explicit
missing-table coverage. The authenticated service/read-model adapter also
exposes `/forecast-v3`, `/forecast/detail`, `/inflow`, `/net`, and `/gap-alert`
for source-compatible drill-downs. Cash release, accounting, tax, bank
settlement, and production identity remain separate gates. The `/cbs/*`
screens now load the source-compatible PostgreSQL CBS dictionary and R0 queue
reads, including explicit empty/covered source states when the export has no
CBS dictionary/version rows; CBS mutations and budget ownership remain
separate gates. The `/fund/plan` screen now loads source-compatible PostgreSQL
fund plans, gap analysis, and dispatch reads with explicit empty-source
provenance; fund-plan and dispatch mutations remain gated.
The `/warning` and `/warning-rules` screens now load observed source warning
badge/list/rule reads. Imported project/cost evidence yields one W005 finding;
the adapter marks observations non-authorizing and keeps imported findings
read-only. Resolve/ignore actions write only a local `warning_state` overlay
with replay/audit evidence; scans, rule writes, tickets, and notifications
remain gated. The authenticated
`/attachments` screen now reads source attachment metadata and statistics from
PostgreSQL; the export has no attachment rows or binary storage, so the empty
state is explicit and upload/download/OCR remain gated.
The `/marketing` screen now reads campaign, placement, channel, and material
metadata from PostgreSQL; the export has no marketing rows, so successful reads
show an explicit empty source state and keep the reviewed cohort/designer rows
only as transport fallback. Marketing mutations, spend/CBS consumption, and
attribution remain gated.
The authenticated `/inbox` screen now reads user-scoped notification messages
and unread counts through the PostgreSQL service. `/notify-config` chains
source subscriptions, redacted configuration-key status, email-outbox
metadata, digest preview/log evidence, and provider discovery. The export has
no notification source rows, so successful reads show explicit empty-source
states; message acknowledgement, subscription/configuration writes, digest
dispatch, provider calls, consent/retry policy, and delivery remain gated.
The authenticated `/ocr-config` screen now reads provider definitions,
current scene, and redacted configuration-key status without invoking OCR.
`/error-log` reads bounded source error metadata while redacting IP addresses
and stack traces. The export has no `/sys_param` or `/sys_error_log` rows,
so successful reads show explicit definition/empty-source states; provider
execution, configuration writes, retention, production identity, and
super-user ownership remain gated.
The authenticated `/ai-stats` screen now reads source-compatible AI
overview, activity, and badge evidence from PostgreSQL. The export has no
`ai_draft`, `ai_query_log`, correction, or workflow auto-skip rows, so
successful reads show explicit empty-source analytics; LLM/OCR execution,
draft confirmation, workflow authority, prompt retention, and AI-owner
acceptance remain gated.
The authenticated `/ai-hub` screen now reads source-compatible usage stats,
draft history, query history, correction rows, and correction statistics from
PostgreSQL before rendering the existing designer workbench. The current
export has no `ai_draft`, `ai_query_log`, `ai_correction_log`,
`ai_query_session`, or `ai_query_turn` rows, so successful reads show explicit
empty-source metrics/history; draft field values, SQL, and OCR text remain
redacted. Intake/confirm/discard/query/explain/rule/approval/global-ask/
session/command routes and provider/LLM/OCR execution remain gated.
The authenticated `/webhook-config` screen now reads the three-platform
source-compatible webhook configuration through `/api/company/webhook/config`.
URL and secret values are redacted, and the current export has no `sys_param`
rows, so successful reads show explicit empty-source metadata. Configuration
writes, test delivery, overdue scans, provider credentials, and
notification-owner acceptance remain gated.
The authenticated `/report-builder` screen now reads the ERP table/column
whitelist and saved-template metadata through
`/api/company/reports/templates/meta` and `/api/company/reports/templates`.
The export contains no `sys_report_template` rows, so successful reads show an
explicit empty-template state while retaining the designer builder layout.
The PostgreSQL service/gateway now also exposes source-safe template create,
run, and delete commands; command-owned templates are shown with
`sourceKind=command`, while imported templates stay read-only. Run evaluates
only the allow-listed imported envelope fields and reports `sql_executed=false`.
CSV/PDF exports, production identity, and report-owner acceptance remain
gated.
The company service/gateway also exposes local
employee-loan create, applicant submit, bounded offset, draft update, and
draft/rejected void commands with explicit authority evidence and idempotency;
workflow synchronization stays gated until source workflow rows are available.
The Rabbita loan editor now emits the local create/submit/update/void commands
and keeps imported detail routes read-only; the offset action remains available
only after an approved workflow state is supplied. The other route families
remain fixture-backed. `/tasks` now reads the source workflow definitions and
previews (two processes, twelve steps, six assignee mappings with imported user
labels) through the authenticated service; source instances/actions are empty, so the task cards
remain a clearly labelled design snapshot and no approval mutation is exposed.
`/projects` and `/projects/:guid` now read the source project master and
lifecycle/task evidence (two projects, fourteen lifecycle rows, nine tasks),
while the designer project tables/forms remain an explicitly labelled fallback;
native local project-plan task mutations are available as a separate
authority-bound boundary and do not mutate imported rows.
Source-compatible plan reads are also available at
`/api/company/projects/:id/tasks`, `/api/company/tasks/:id`, and
`/api/company/projects/:id/plan-summary`, plus lifecycle and delay-impact
reads. `POST`/`PUT`/`DELETE /api/company/plan/tasks[/:id]` and the evidence-gated
`/report` alias persist local projections through the compiled MoonBit service;
workflow, cash, accounting, and tax effects remain explicitly false.
The source MDM business-unit tree is available to company-scoped screens at
`/api/company/business-units/tree`; imported organization rows remain read-only
until legal-principal and role ownership are accepted.
Expense-form dictionary reads are available at
`/api/company/budget/dict/cost-subjects` and `/api/company/budget/proceedings`;
dictionary and expense writes remain finance-owner gated.
The imported expense list and detail screens now use
`/api/company/budget/expenses` and `/api/company/budget/expenses/:guid`.
Detail responses preserve the source `vcb_expense`, `cb_expense_detail`, and
`cb_expense_split` envelope, render empty source tables explicitly, and keep
the designer form as a transport-failure fallback; imported detail remains
read-only.
Investment read evidence is available at
`/api/company/investment/projects/:id/versions`,
`/api/company/investment/versions/:id/indices`,
`/api/company/investment/projects/:id/profit-summary`, and
`/api/company/investment/meta/dimensions`; import and valuation mutations remain
separately gated.
The `/investment` screen loads the imported current version, 26 grouped
indices, profit summary, sensitivity scenarios, and the source-compatible
`profit-actual` missing-plan/approval boundary through the read-only adapter;
its designer comparison table remains an offline fallback.
The `/dynamic-cost` screen loads the seven imported `cb_cost` rows and source
A/B/C/D/E/F/G/H calculation for `proj-0001`; cost writes and downstream
accounting/cash effects remain gated.
The `/cost-dashboard-v3` screen now reads the source
`/api/company/investment/projects/:id/profit-actual-v2` hierarchy. It renders
R/l2/l3 CBS rows and the B/D/E/F/G/H summary when available, shows explicit
empty CBS/version state for the current export, and retains the designer
dashboard only as transport fallback; budget, accounting, cash, and tax writes
remain gated.
Admin governance reads are available at
`/api/company/admin/dict/groups`, `/api/company/admin/dict/options`,
`/api/company/admin/quality/overview`,
`/api/company/admin/audit/logs`, `/api/company/admin/audit/actions`,
`/api/company/admin/health/tables`, and `/api/company/admin/health/bpm-pool`;
the quality response keeps four unavailable source dependencies explicit, and
the source super-user boundary and all admin writes remain gated.
The `/system-health` screen consumes both health reads through the read-only
adapter and keeps its original uptime, memory, storage, and queue cards as
offline design fallback only.
The `/admin` screen consumes dictionary group/options after the quality read;
the five imported options and twelve quality rules remain read-only evidence,
with the designer dictionary table retained as offline fallback.
`/api/company/rbac/users` also loads the five imported user identities and
organization labels on `/users`; role and permission tables remain explicit
source gaps, and no role is inferred from `isSuperUser`.
Command-gateway
production deployment, identity/token integration, and managed rollback remain
separate gates.
Build and preview it with Warren:

```sh
moon install moonbit-community/warren
warren dev frontend/main --public-dir frontend/public
```

To exercise the native MoonBit PostgreSQL read model directly:

```sh
PGHOST=/tmp PGPORT=5432 PGUSER=moonproj PGDATABASE=moonproj \
  scripts/company_postgres_read_model_server.sh --host 127.0.0.1 --port 4173
```

The native authenticated service and session gateway can be run together for
a one-origin Rabbita rehearsal:

```sh
export MOONPROJ_SERVICE_TOKEN=choose-a-local-token
export MOONPROJ_ACTOR_SIGNING_SECRET=choose-a-local-signing-secret
export MOONPROJ_SESSION_SECRET=choose-a-local-session-secret
export MOONPROJ_DEV_USER=choose-a-local-user
export MOONPROJ_DEV_PASSWORD=choose-a-local-password
export PGPASSWORD=your-local-password
scripts/company_postgres_service.sh --port 4174 --require-forwarded-tls &
scripts/company_postgres_gateway.sh \
  --public-dir /path/to/warren/dist --port 4173 --service-port 4174
```

The native gateway keeps the bearer token server-side, establishes an
HttpOnly session, signs the actor assertion, forwards only allow-listed
company paths, and serves the Warren bundle with SPA fallback. The Python
service and gateway commands that used to appear here are frozen comparison
artifacts and are not supported build, test, or deployment dependencies.

Identity-bound browser rehearsal uses the native gateway's optional
`--trusted-identity-secret-env` mode. It verifies the short-lived
`X-Moonproj-Identity`, timestamp, and HMAC signature against the native
PostgreSQL profile before creating a secure session cookie. Managed persistent
session storage, issuer/audience validation, rotation, production deployment,
and owner approval remain open; no Python gateway fallback is authorized.

This is an integration seam for the managed identity gateway, not a claim
that the local in-memory session store, issuer/audience validation, rotation,
or production owner approval is complete.

The UI intentionally stays within the source product’s Element Plus visual
language: system Chinese fonts, `#1e293b` navigation, `#f1f5f9` work canvas,
compact KPI cards, dense data tables, and the source login gradient.
