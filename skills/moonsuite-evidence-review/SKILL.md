---
name: moonsuite-evidence-review
description: Independently verify a Moon Suite engineering evidence draft in a separate MoonClaw task and write the one reviewed v2 ledger MoonProj trusts. Use when a reviewer task must cross-check claims, rerun bounded commands, and reject unsupported evidence before MoonProj derives its three dimensions.
---

# MoonSuite Evidence Review

Review another Agent's evidence. Do not reuse the producer identity or accept self-attestation.

## Method

1. Require the producer artifact, repository, commit SHA, observation time, and schema version.
2. Confirm referenced files and receipts exist and match the claimed commit or candidate digest.
3. Rerun a risk-weighted sample of commands, including every failed check and every criterion used to claim production eligibility.
4. Reject claims based on missing, stale, mutable, unrelated, or self-referential evidence.
5. Compare conclusions with policy mechanically. Do not substitute a new subjective rating.
6. Mark disputed claims and request the smallest missing evidence packet.
7. Preserve the canonical meanings of R1-R3 and G1-G9; never renumber or remap criteria.
8. Compose the final `moonsuite.engineering-evidence.v2` ledger only after review.

The reviewer must not be the Agent that produced the audited artifact. If identity separation cannot be proven, return `reject`.

The producer and reviewer must be different MoonClaw task IDs, not two role names invented inside one conversation. Cite the producer task ID in `verified_receipts`.

## Execution limits

- Use MoonBit and shell tooling only. Never invoke `python`, `python3`, a Python module, or a Python script.
- Never use unbounded repository search. Bound every command output and receipt to 64 KiB.
- Prefer counts, selected paths, exit codes, timestamps, and digests over raw logs.
- Rerun checks in an ephemeral archive of the exact commit; do not modify the audited repository or producer draft.
- Build and validate JSON with `jq`; use a same-directory atomic `mv` for the final ledger.

## Output

Write JSON with schema `moonsuite.engineering-evidence.v2`. Preserve the producer draft's candidate identity, redlines, Gates, and findings after correcting rejected claims, then add exactly this review object:

```json
"review": {
  "producer_agent": "audit-id:producer",
  "reviewer_agent": "audit-id:reviewer",
  "verdict": "accept",
  "verified_receipts": ["producer_task_id=...", "bounded rerun receipt"],
  "rejected_claims": ["unsupported claim"],
  "missing_evidence": ["smallest missing packet"]
}
```

Allowed verdicts are `accept`, `reject`, and `needs_evidence`. `accept` means the ledger accurately represents passes, failures, blocked items, and unknowns; it does not mean the candidate is production-ready. MoonProj may project only accepted claims as trusted.
