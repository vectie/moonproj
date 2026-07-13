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
| Dictionary options | `/api/company/admin/dict/options` | source-compatible read |
| Quality overview | `/api/company/admin/quality/overview` | bounded source read |
| User roster | `/api/company/rbac/users` | source-backed read; role data gated |
| Audit logs | `/api/company/admin/audit/logs` | source-compatible read |
| Audit actions | `/api/company/admin/audit/actions` | source-compatible read |
| Health table coverage | `/api/company/admin/health/tables` | source-coverage read |
| BPM pool snapshot | `/api/company/admin/health/bpm-pool` | source-coverage read |

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
dictionary fixture remains an offline fallback, and no dictionary write is
enabled.

Rows preserve source field names and are marked `sourceKind=imported`. The
quality response marks unavailable rules as `NO_SOURCE_ROWS` and includes
per-table coverage; it does not turn missing source data into passing checks.
The user roster preserves five imported identities and organization labels;
`sys_role`/`sys_user_role` coverage is returned as `NO_SOURCE_ROWS`, so no role
is inferred from the super-user flag.
The Rabbita `/users` screen consumes that roster read and keeps its role and
permission panels as an explicitly offline design snapshot; it does not treat
the imported super-user flag as target authority.
The target does not expose dictionary writes, audit deletion, role changes, or
super-user elevation.

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
- The parity matrix marks the seven connected source admin GET handlers as
  `connected_admin_read`.
- The parity matrix marks the source `GET /rbac/users` roster as
  `connected_rbac_user_read`; role and permission endpoints remain gated.
- The parity matrix marks `/users` as `connected_rbac_user_read`; the
  production identity and super-user owner scenario remain required.
- The parity matrix marks `/system-health` as
  `connected_admin_health_read`; the production identity and super-user owner
  scenario remain required before treating the screen as an accepted admin
  control surface.
- The parity matrix marks `/admin` as `connected_admin_read`; source
  super-user scope and owner acceptance remain required.

## Remaining gate

1. Bind admin screens to production identity and enforce the source super-user
   role and organization scope.
2. Reconcile the full audit/dictionary export, retention policy, and security
   owner acceptance before treating these rows as complete governance history.
3. Keep dictionary writes, audit retention/deletion, role administration, and
   system-health actions separately authorized.
