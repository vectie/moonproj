# ERP Profile Runtime Audit

Recorded: 2026-07-14  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source profile read is `GET /api/v1/auth/me`. The available export has
five `sys_user` rows and seven `mu_business_unit` rows, so the target can
reproduce the non-secret identity/profile read without inventing a user or
organization.

## Target evidence

- `GET /api/company/auth/me?userCode=...` selects an imported `sys_user` by
  `user_code`, joins business-unit and department names, and returns source
  coverage for both tables.
- `GET /api/company/auth/my-initiated?userCode=...` filters the source
  `vcb_expense`, `vcb_loan_simple`, and `cb_htfk_apply` rows by the selected
  user's ID. The current export yields zero expenses, one loan, and three
  payment applications for `limingjin`; the empty expense table is reported
  as source coverage rather than replaced with a fixture.
- `GET /api/company/auth/prefs?userCode=...` exposes the source preference
  shape and merges any active local command projection. The current export has
  no `sys_user_pref` rows, so `admin` receives `{}` with explicit zero source
  coverage until a signed local command is issued. `PUT`/`DELETE`
  `/api/company/source/auth/prefs/:key` translate the source self-scoped
  preference mutations into durable, idempotent `user_preference` projections
  and audit receipts. They are command provenance only: they do not grant
  authority or trigger provider, accounting, cash, or tax effects; imported
  `sys_user_pref` rows remain read-only.
- `GET /api/company/rbac/me?userCode=...` now exposes the source current-user
  RBAC shape while keeping authority separate. It returns the imported
  identity, empty roles/permissions, `dataScope=self`, and `NO_SOURCE_ROWS`
  for the absent `sys_role`/`sys_user_role` tables. The response is marked
  `authorizing=false` and cannot be used as a production grant.
- `GET /api/company/rbac/roles`, `GET /api/company/rbac/roles/:code`, and
  `GET /api/company/rbac/permission-catalog` now expose role/detail/catalog
  observations. The current export returns zero role rows with explicit
  `NO_SOURCE_ROWS`, preserves the source-defined 11-module catalog, and marks
  every response non-authorizing; an unknown role detail returns 404.
- The response intentionally excludes password hashes, login-failure fields,
  network data, and other authentication secrets.
- Rabbita `/profile` loads the read model for the active user code while
  preserving the designer tabs, form layout, subscriptions table, and
  initiated-document table. The name field is editable and sends the source
  `empName`/`userName` profile command; the password card sends the source
  `{oldPassword,newPassword}` shape, validates confirmation and minimum
  length locally, and clears password inputs after a successful credential
  projection before logging the session out to the login screen. A
  source/provenance note makes the PostgreSQL command boundary visible, and
  imported rows replace the sample documents when they exist.
- The service and trusted-gateway smokes cover the imported `admin` record,
  super-user flag, coverage counts, the empty preference observation, the
  preference set/replay/read/delete command path,
  non-authorizing RBAC current-user/role/catalog observations, the missing-user
  and missing-role 404 paths, and the `limingjin` initiated-document counts and
  identities.
- `scripts/company_postgres_dev_gateway.py` now has an opt-in trusted-upstream
  identity mode. It verifies a short-lived HMAC assertion, confirms the
  asserted user exists and is enabled through `/api/company/auth/me`, then
  binds the HttpOnly session actor to that source `user_code`. The dedicated
  gateway smoke covers valid login, PostgreSQL forwarding, stale-assertion
  rejection, and missing-session rejection without printing credential values.

## Remaining gates

Role administration, managed issuer/audience validation, session-store
durability, token rotation, browser production-identity acceptance, and
security-owner approval remain separate gates. Profile/password commands are
still signed local projections: they do not import legacy credentials or
authorize downstream work. Preference commands are limited to the signed
user's local projection and are not an authorization mutation. The
trusted-upstream mode is an identity-bound rehearsal seam; it is evidence of
source translation and gateway binding, not authorization to mutate identity
data or approve workflows.
