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
- The response intentionally excludes password hashes, login-failure fields,
  network data, and other authentication secrets.
- Rabbita `/profile` loads the read model for the active user code while
  preserving the designer tabs, form layout, subscriptions table, and
  initiated-document table. A source/provenance note makes the read-only
  boundary visible.
- The service smoke covers the imported `admin` record, organization joins,
  super-user flag, coverage counts, and a missing-user 404 path.

## Remaining gates

Profile updates, password changes, preferences, initiated-document reads,
production identity/token binding, browser acceptance, and security-owner
approval remain separate gates. The local adapter is evidence of source
translation, not authorization to mutate identity data.
