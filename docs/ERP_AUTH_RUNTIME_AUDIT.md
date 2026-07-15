# ERP Auth Runtime Audit

The source auth routes cover login, logout, password change, and profile
mutation. Native PostgreSQL now recognizes the same `/api/company/auth/*`
boundaries. Login is reachable without a bearer token (subject to forwarded TLS)
so the missing behavior is explicit rather than an authentication 401.

Logout and profile now use signed local commands with idempotent PostgreSQL
receipts, immutable `auth_session`/`auth_profile` revisions, audit events, and
`/auth/me` profile overlay readback. They remain non-authorizing and do not
issue bearer tokens. Login and password change return an explicit
`auth_lifecycle_candidate` 409 with `sessionIssued=false` and `persisted=false`;
password hashing/history, session/token issuance, production identity, and
security-owner acceptance remain unported. Read-only preferences and
initiated-document observations remain separate native surfaces.
