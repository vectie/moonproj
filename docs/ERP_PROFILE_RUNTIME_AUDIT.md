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
- `GET /api/company/auth/prefs?userCode=...` now exposes the source preference
  shape as a read-only observation. The current export has no
  `sys_user_pref` rows, so `admin` receives `{}` with explicit zero coverage;
  the endpoint never persists or authorizes a preference change.
- `GET /api/company/rbac/me?userCode=...` now exposes the source current-user
  RBAC shape while keeping authority separate. It returns the imported
  identity, empty roles/permissions, `dataScope=self`, and `NO_SOURCE_ROWS`
  for the absent `sys_role`/`sys_user_role` tables. The response is marked
  `authorizing=false` and cannot be used as a production grant.
- The response intentionally excludes password hashes, login-failure fields,
  network data, and other authentication secrets.
- Rabbita `/profile` loads the read model for the active user code while
  preserving the designer tabs, form layout, subscriptions table, and
  initiated-document table. A source/provenance note makes the read-only
  boundary visible, and imported rows replace the sample documents when they
  exist.
- The service smoke covers the imported `admin` record, organization joins,
  super-user flag, coverage counts, the empty preference observation, the
  non-authorizing RBAC observation, a missing-user 404 path, and the
  `limingjin` initiated-document counts and identities.

## Remaining gates

Profile updates, password changes, preference writes, role administration,
production identity/token binding, browser acceptance, and security-owner
approval remain separate gates. The local adapter is evidence of source
translation, not authorization to mutate identity data or approve workflows.
