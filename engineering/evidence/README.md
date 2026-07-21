# Engineering evidence inbox

MoonProj issues an `audit_id` when an authenticated user starts an audit.
MoonClaw writes exactly one completed JSON envelope to
`inbox/<audit_id>.json`. Partial output must be written under another name and
renamed only after the independent reviewer finishes.

The native gateway reads the file only after MoonClaw reports the task idle.
The PostgreSQL service then validates these five strict contracts:

1. `moonsuite.engineering-audit-envelope.v1`
2. `moonsuite.project-progress-evidence.v1`
3. `moonsuite.project-health-evidence.v1`
4. `moonsuite.production-gate-evidence.v1`
5. `moonsuite.evidence-review.v1`

Unknown fields, missing fields, mismatched project/commit values, malformed
full commit digests, unsupported states, and producer/reviewer identity reuse
are rejected. A rejected envelope never updates the project projection.

Files in this directory are transport artifacts, not the system of record.
Accepted evidence, review receipts, candidate digests, immutable projection
revisions, and supersession links live in PostgreSQL.
