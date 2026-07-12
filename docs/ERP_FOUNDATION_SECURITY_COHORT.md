# ERP Foundation-Security Schema Cohort

Recorded: 2026-07-13  
Source wave: `foundation-security` from `../erp/erp_new/server/src/db/index.js`

The current snapshot contains no rows for this wave. The migration therefore
records an explicit semantic and security mapping without fabricating source
records or granting authority from legacy configuration.

| Source table | Target boundary | Disposition | Required control |
|---|---|---|---|
| `attachment` | `foundation/evidence.Evidence` | typed import | content hash, retention, and access review; file paths are not authoritative |
| `sys_param` | opaque foundation parameter evidence | evidence only | principal/scope mapping and no policy inference |
| `sys_password_history` | identity security boundary | exclude sensitive | password hashes never migrate; authentication remains provider-owned |
| `sys_role` | `foundation/access.Role` | typed import | permissions require review and do not assign authority implicitly |
| `sys_user_pref` | user-preference boundary | evidence only | user scope and sensitive-value review; no authority effect |
| `sys_user_role` | `foundation/access.RoleAssignment` | typed import | user/role identity map, principal/scope, and segregation-of-duties checks |

The machine-readable mapping is
`scripts/fixtures/schema_foundation_security_mapping.json`. Each rehearsal
emits `schema-foundation-security.json` with state `mapped_scope_only`, six
mapped tables, zero available source rows, and `promotion_authorized=false`.
This is readiness evidence, not a migration receipt or cutover authorization.

When a complete source export becomes available, the wave can proceed only if
each row passes the target domain importer, exact parity/replay checks, and
named security/business acceptance. Password history remains excluded even in
that later export.
