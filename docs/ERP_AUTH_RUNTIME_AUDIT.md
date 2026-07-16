# ERP Auth Runtime Audit

The source auth routes cover login, logout, password change, and profile
mutation. Native PostgreSQL now recognizes the same `/api/company/auth/*`
boundaries. Login is reachable without a bearer token (subject to forwarded TLS)
so the missing behavior is explicit rather than an authentication 401.

Logout, profile, and password change now use signed local commands with
idempotent PostgreSQL receipts, immutable `auth_session`/`auth_profile`/
`auth_credential` revisions, and audit events. Profile overlays continue to
read back through `/auth/me`; password transitions persist only SHA-256 digest
evidence and redacted history markers (`credentialVerified=false`) because the
imported password store is not available. They remain non-authorizing and do
not issue bearer tokens. Login now verifies the latest PostgreSQL credential
projection and returns a redacted authenticated envelope; the trusted gateway
turns that proof into an HttpOnly session. Users without a command-owned
credential still receive the explicit `auth_lifecycle_candidate` 409, while
the development fixture remains a compatibility fallback. Production identity,
imported credential migration, managed session storage, and security-owner
acceptance remain unported. The trusted gateway and Rabbita profile actions
cover the persisted profile/password command boundary. Read-only preferences
and initiated-document observations remain separate native surfaces.
