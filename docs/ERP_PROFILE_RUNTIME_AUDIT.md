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
- The response intentionally excludes password hashes, login-failure fields,
  network data, and other authentication secrets.
- Rabbita `/profile` loads the read model for the active user code while
  preserving the designer tabs, form layout, subscriptions table, and
  initiated-document table. A source/provenance note makes the read-only
  boundary visible, and imported rows replace the sample documents when they
  exist.
- The service smoke covers the imported `admin` record, organization joins,
  super-user flag, coverage counts, a missing-user 404 path, and the
  `limingjin` initiated-document counts and identities.

## Remaining gates

Profile updates, password changes, preferences, production
identity/token binding, browser acceptance, and security-owner approval remain
separate gates. The local adapter is evidence of source translation, not
authorization to mutate identity data.
