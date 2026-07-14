# ERP Access and Role Boundary

Recorded: 2026-07-13
Owner: `foundation/access` and `cmd/access_import`

The company product owns bounded local authority, not legacy authentication
secrets. A reviewed access plan translates source `sys_role` and
`sys_user_role` intent into local roles, exact-scope permissions, principal and
actor assignments, and segregation-of-duties rules. Password history, network
fields, and source super-user bits are never imported.

## Native validation

`scripts/erp_access_plan.py` compiles a complete source export and explicit
permission/identity/scope map into `moonproj.company.access-plan.v1`.
`cmd/access_import` requires that plan with
`reviewed=true`. It builds the local `AccessDirectory` through the normal
authority-bearing APIs:

- every permission has an explicit capability, exact scope, and amount ceiling;
- roles are created and edited under `rbac:role:*` grants;
- separation rules are installed before assignments;
- assignments bind a principal, actor, role, scope, and cap; and
- incompatible assignments fail with `SegregationViolation` rather than being
  silently repaired.

The importer emits the normal domain-promotion receipt with one
`access_directory` candidate. The projection records `authority_migrated=true`
separately from workflow, cash, and accounting effects, all of which remain
false. Durable SQLite and PostgreSQL projection adapters provide exact parity
and zero-insert replay.

## Migration contract and open gates

The optional twenty-fourth SQLite rehearsal argument and twenty-second
PostgreSQL cohort-runner argument accept the reviewed plan. The checked-in
fixture is synthetic because the available ERP snapshot contains no
`sys_role` or `sys_user_role` rows. A complete source export must provide
explicit role/permission mappings, user-to-principal identity, scope mapping,
system-role review, and owner approval before real authority is transferred.
Authentication remains provider-owned and role migration does not grant
workflow approval, cash movement, or accounting posting by itself.

The PostgreSQL adapter's `/api/company/rbac/me` is an observation endpoint for
source identity/role coverage only. It returns `authorizing=false` and treats
missing `sys_role`/`sys_user_role` rows as `NO_SOURCE_ROWS`; it never derives
permissions from the imported `is_super_user` flag. `/api/company/auth/prefs`
similarly reports imported preference values when available and an explicit
empty source state otherwise. Neither endpoint replaces the production token,
role directory, or reviewed access-plan import.
