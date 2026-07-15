# ERP Auth Runtime Audit

The source auth routes cover login, logout, password change, and profile
mutation. Native PostgreSQL now recognizes the same `/api/company/auth/*`
boundaries. Login is reachable without a bearer token (subject to forwarded TLS)
so the missing behavior is explicit rather than an authentication 401.

Each route currently returns a signed-request-independent `409`
`auth_lifecycle_candidate` response with `sessionIssued=false` and
`persisted=false`. Password hashing/history, session/token issuance, user
profile persistence, production identity, and security-owner acceptance remain
unported. Read-only `/me`, preferences, and initiated-document observations
remain separate native surfaces.
