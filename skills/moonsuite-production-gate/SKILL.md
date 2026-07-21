---
name: moonsuite-production-gate
description: Evaluate whether a Moon Suite project meets production quality by mapping independent evidence to seven exit Gates and three veto redlines. Use when MoonClaw must produce a production-readiness matrix, identify missing evidence, or recommend freeze, internal, gray, or full-release eligibility without inventing scores.
---

# MoonSuite Production Gate

Evaluate evidence against policy. Do not decide release authority.

## Redlines

Evaluate first:

- `R1`: data leakage or credential exposure risk
- `R2`: required compliance, license, or qualification evidence missing
- `R3`: core user or recovery path blocked

Any `fail` freezes release. Any `unknown` prevents a positive production verdict.

## Gates

Evaluate every criterion as `pass`, `fail`, `unknown`, or `not_applicable`:

1. requirement and value validation
2. functional completeness
3. user experience and interaction feedback
4. engineering quality, configuration, tests, and coverage
5. product telemetry and operational measurement
6. security and compliance
7. release, rollback, on-call, and recovery

Use only evidence tied to the exact commit or release candidate. A later source tree does not validate an earlier binary, and a successful build does not prove deployment or rollback.

Do not invent numeric scores. If policy provides deterministic weights, emit criterion results and inputs; MoonProj calculates the score. Otherwise set `computed_grade` to `unknown`.

## Output

Return JSON only with schema `moonsuite.production-gate-evidence.v1`:

```json
{
  "project": "moonclaw",
  "commit": "full-sha",
  "candidate": "tag, digest, or null",
  "observed_at": "ISO-8601",
  "redlines": [{"id": "R1", "status": "pass", "evidence": ["receipt"]}],
  "gates": [{"id": "G1", "status": "unknown", "criteria": [{"id": "G1.1", "status": "unknown", "evidence": [], "missing": ["approved value statement"]}]}],
  "computed_grade": "unknown",
  "release_eligibility": "frozen",
  "missing_evidence": ["string"],
  "owner_decisions": ["string"]
}
```

Allowed eligibility values are `frozen`, `internal_only`, `gray_candidate`, `full_candidate`, and `unknown`. Only the Owner or an explicitly authorized release system may approve release.
