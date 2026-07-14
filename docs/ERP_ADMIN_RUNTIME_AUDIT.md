# ERP Admin Governance Runtime Audit

Recorded: 2026-07-14
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source admin route provides dictionary group/options, a twelve-rule quality
overview, and audit-log query reads behind a super-user boundary. The available
credential-safe export contains one dictionary group with five options, two
login audit rows, and enough project/contract/payment/cost/task/loan/user rows
to evaluate eight quality rules. Four rules remain explicitly unavailable
because expense, workflow, or supplier source rows are empty or absent.

The target now exposes source-compatible read boundaries:

| Source surface | Target endpoint | Target state |
|---|---|---|
| Dictionary groups | `/api/company/admin/dict/groups` | source-compatible read |
| Dictionary options | `/api/company/admin/dict/options` | source-compatible read plus bounded local create/update overlay |
| Quality overview | `/api/company/admin/quality/overview` | bounded source read |
| User roster | `/api/company/rbac/users` | source-backed read; role data gated |
| Audit logs | `/api/company/admin/audit/logs` | source-compatible read |
| Audit actions | `/api/company/admin/audit/actions` | source-compatible read |
| Health table coverage | `/api/company/admin/health/tables` | source-coverage read |
| BPM pool snapshot | `/api/company/admin/health/bpm-pool` | source-coverage read |
| OCR provider status | `/api/company/admin/ocr/status` | metadata-only read; provider execution gated |
| Error log metadata | `/api/company/admin/error-log` | bounded read; IP/stack redacted |
| Database backup export | `/api/company/admin/backup/db` | PostgreSQL target-format boundary; export gated |

The Rabbita `/system-health` screen now calls both health endpoints through the
read-only PostgreSQL adapter. When the responses arrive it shows the 29-table
source coverage, empty/missing-table count, BPM instance/action counts, and the
explicit non-authorizing state. Its original uptime, memory, storage, and
queue values remain only as an offline design snapshot; they are not presented
as live evidence.

The Rabbita `/admin` screen now calls the dictionary group/options reads after
the quality overview succeeds. Its data-dictionary table shows the five
imported `cost_subject` options and source provenance; the quality table keeps
the twelve-rule result, including unavailable source dependencies. The
dictionary fixture remains an offline fallback. The PostgreSQL service now
also accepts source-shaped dictionary create/update commands as command-owned
overlays: imported rows are never mutated, an enabled imported source
super-user is required, and the command writes only an immutable projection,
receipt, and audit event with `authorizing=false` and no provider, cash,
accounting, or tax effect. The current Rabbita table remains read-only, so
browser action wiring is still a separate parity gate.

Rows preserve source field names and carry explicit imported, imported-or-
command, or command provenance. The quality response marks unavailable rules as `NO_SOURCE_ROWS` and includes
per-table coverage; it does not turn missing source data into passing checks.
The user roster preserves five imported identities and organization labels;
`sys_role`/`sys_user_role` coverage is returned as `NO_SOURCE_ROWS`, so no role
is inferred from the super-user flag.
The Rabbita `/users` screen consumes that roster read and keeps its role and
permission panels as an explicitly offline design snapshot; it does not treat
the imported super-user flag as target authority.
The Rabbita `/audit-log` screen now consumes the two imported login rows and
the `login × 2` action aggregate through the read-only adapter. It keeps the
source IP redaction and append-only presentation; filtering, retention,
deletion, and export authority remain separate gates.
The target does not expose audit deletion, role changes, or super-user
elevation. Dictionary create/update is available only through the bounded
authenticated service/gateway overlay described above; it does not promote or
rewrite imported rows. OCR status never executes a provider or returns secret
values; error-log reads never return raw IP addresses or stack traces. The
current export has no `sys_param` or `sys_error_log` rows, so both screens
render explicit empty-source/definition states after successful reads.

## Evidence

- PostgreSQL service smoke returns one `cost_subject` group, five options, two
  audit log rows, and one `login` action with count two.
- PostgreSQL service smoke evaluates all twelve quality rules: eight are
  source-backed, one currently fails (`project_without_dynamic_cost`), and
  four are `NO_SOURCE_ROWS` (expense, workflow, and supplier dependencies).
- Action, user, target-type, and pagination filters are applied against the
  bounded imported rows.
- Health tables enumerate 29 source tables and expose imported/empty status;
  the BPM pool explicitly reports zero source instances/actions and
  `authorizing=false`.
- The parity matrix marks the nine connected source admin GET handlers as
  `connected_admin_read` and the source dictionary POST/PATCH handlers as
  `connected_admin_dictionary_command`.
- The parity matrix marks the source `GET /rbac/users` roster as
  `connected_rbac_user_read`; role and permission endpoints remain gated.
- The parity matrix marks `/users` as `connected_rbac_user_read`; the
  production identity and super-user owner scenario remain required.
- The parity matrix marks `/audit-log` as `connected_admin_audit_read`; audit
  retention/export ownership and the production super-user scenario remain
  required.
- The parity matrix marks `/system-health` as
  `connected_admin_health_read`; the production identity and super-user owner
  scenario remain required before treating the screen as an accepted admin
  control surface.
- The parity matrix marks `/admin` as `connected_admin_read`; source
  super-user scope and owner acceptance remain required.
- The trusted gateway smoke exercises dictionary PATCH with the imported
  `admin` super-user, verifies idempotent replay, and confirms the command
  receipt/audit result is non-authorizing with no external effect.
- The parity matrix marks `/ocr-config` and `/error-log` as connected
  metadata reads; provider execution, error-log retention, production identity,
  and super-user owner acceptance remain required.
- The parity matrix marks `GET /backup/db` as a connected PostgreSQL boundary.
  It never invokes the source MySQL `mysqldump`, returns no binary, and keeps
  backup ownership, retention, download authorization, and restore testing as
  managed-operations gates.

**Browser evidence (2026-07-14).** A local PostgreSQL read-model session
opened `/audit-log`, `/error-log`, `/system-health`, `/users`, `/admin`, and
`/ocr-config`, then the Webhook configuration view. All observed reads returned
HTTP 200. The browser showed the two imported audit rows, five imported users,
29-table health coverage, twelve quality rules, five dictionary options, and
redacted OCR/Webhook metadata. It also visibly kept the health metrics and
role/permission panels as offline design snapshots where the source routes or
tables are unavailable. No write, OCR call, or Webhook delivery was attempted.

## Remaining gate

1. Bind admin screens and dictionary actions to production identity and enforce
   the source super-user role and organization scope.
2. Reconcile the full audit/dictionary export, retention policy, and security
   owner acceptance before treating these rows as complete governance history.
3. Keep audit retention/deletion, role administration, and system-health
   actions separately authorized; keep dictionary overlays isolated from source
   promotion and external effects.
