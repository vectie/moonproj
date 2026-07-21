---
name: moonsuite-evidence-review
description: Independently verify Moon Suite progress, health, and production-gate evidence produced by other Agents. Use when MoonClaw must cross-check claims, rerun sampled commands, reject unsupported ratings, or issue an acceptance receipt before MoonProj displays an audit as trusted.
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

The reviewer must not be the Agent that produced the audited artifact. If identity separation cannot be proven, return `reject`.

## Output

Return JSON only with schema `moonsuite.evidence-review.v1`:

```json
{
  "project": "moonclaw",
  "producer_artifact": "path",
  "producer_agent": "agent-id",
  "reviewer_agent": "different-agent-id",
  "commit": "full-sha",
  "observed_at": "ISO-8601",
  "verdict": "accept",
  "verified_claims": [{"claim": "string", "evidence": ["receipt"]}],
  "rejected_claims": [{"claim": "string", "reason": "string"}],
  "rerun_receipts": ["path"],
  "missing_evidence": ["string"]
}
```

Allowed verdicts are `accept`, `reject`, and `needs_evidence`. MoonProj may project only accepted claims as trusted.
