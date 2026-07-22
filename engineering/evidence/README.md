# Engineering evidence inbox

MoonProj issues an `audit_id` when an authenticated user starts an audit.
MoonProj launches two MoonClaw tasks. The producer writes
`inbox/<audit_id>.producer.json` using
`moonsuite.engineering-evidence-draft.v1`. The separate reviewer cites the
producer task id, reruns a bounded sample, and writes exactly one completed
`moonsuite.engineering-evidence.v2` envelope to `inbox/<audit_id>.json`.
Temporary output must stay under a same-directory temporary name and is renamed
only after validation.

The native gateway reads the file only after MoonClaw reports the task idle.
The PostgreSQL service validates the strict v2 ledger as the active contract:

1. `moonsuite.engineering-evidence.v2`

It can still decode these frozen v1 contracts for migration reads only:

1. `moonsuite.engineering-audit-envelope.v1`
2. `moonsuite.project-progress-evidence.v1`
3. `moonsuite.project-health-evidence.v1`
4. `moonsuite.production-gate-evidence.v1`
5. `moonsuite.evidence-review.v1`

Unknown fields, missing fields, mismatched project/commit values, malformed
full commit digests, unsupported states, and producer/reviewer identity reuse
are rejected. A rejected envelope never updates the project projection. The
active skills use MoonBit plus shell/`jq` only, prohibit unbounded search, and
cap individual command outputs and receipts at 64 KiB.

Files in this directory are transport artifacts, not the system of record.
Accepted evidence, review receipts, candidate digests, immutable projection
revisions, and supersession links live in PostgreSQL.
