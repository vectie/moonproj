---
name: moonsuite-health-audit
description: Measure how well a Moon Suite project is going through reproducible engineering, delivery, security, and operational checks. Use when MoonClaw must run declared checks, report failures and trends, or produce project-health evidence without subjective ratings.
---

# MoonSuite Health Audit

Measure current health; do not assign a personal score.

## Method

1. Record repository, commit SHA, observation time, branch, and dirty state.
2. Discover commands from the repository's own documentation and CI configuration.
3. Run bounded read-only checks for format, check/lint, tests, build, security, packaging, and operational probes when available.
4. Capture command, exit status, duration, and artifact path. Do not summarize a skipped check as passing.
5. Compare with a previous signed snapshot only when one exists. Otherwise set trend to `unknown`.
6. Classify each dimension as `pass`, `fail`, `degraded`, `unknown`, or `not_applicable` from explicit thresholds in `config/moonsuite-engineering.json` or repository policy.

Never use stars, activity, commit volume, code size, or subjective polish as health evidence.

## Output

Return JSON only with schema `moonsuite.project-health-evidence.v1`:

```json
{
  "project": "moonclaw",
  "commit": "full-sha",
  "observed_at": "ISO-8601",
  "checks": [{"dimension": "tests", "status": "pass", "command": "moon test", "exit_code": 0, "duration_ms": 1, "evidence": ["receipt"]}],
  "delivery": {"status": "unknown", "evidence": []},
  "operations": {"status": "unknown", "evidence": []},
  "trend": {"status": "unknown", "baseline_evidence": null},
  "failures": ["string"],
  "unknowns": ["string"]
}
```

Report measurements and unknowns. MoonProj owns aggregation and display policy.
