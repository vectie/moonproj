---
name: moonsuite-progress-audit
description: Determine how far a Moon Suite software or hardware project has progressed using repository, artifact, release, and Gate evidence. Use when MoonClaw must report lifecycle stage, completed milestones, current Gate, blockers, or next evidence without estimating progress from intuition.
---

# MoonSuite Progress Audit

Inspect; do not manage or edit the project.

## Method

1. Resolve the repository from `config/moonsuite-engineering.json`.
2. Record the exact commit SHA and observation time.
3. Read declared roadmap, release, CI, test, package, and operational artifacts.
4. Classify software as `discovery`, `specification`, `implementation`, `validation`, `release_candidate`, `production`, or `operated`.
5. Classify hardware as `concept`, `EVT`, `DVT`, `PVT`, `pilot`, `production`, or `operated`.
6. Mark the current Gate `not_started`, `in_progress`, `at_gate`, `passed`, `blocked`, or `unknown`.
7. Cite evidence for every completed milestone. Treat absent evidence as `unknown`, never as pass.

Do not convert commit count, file count, test count, or model confidence into a progress percentage. Emit a percentage only when the project declares a milestone denominator and cite that denominator.

## Output

Return JSON only with schema `moonsuite.project-progress-evidence.v1`:

```json
{
  "project": "moonclaw",
  "commit": "full-sha",
  "observed_at": "ISO-8601",
  "lifecycle": "software",
  "stage": "validation",
  "gate_state": "at_gate",
  "completed_milestones": [{"name": "string", "evidence": ["path or receipt"]}],
  "current_work": [{"name": "string", "evidence": ["path or receipt"]}],
  "blockers": [{"name": "string", "evidence": ["path or receipt"]}],
  "next_gate": {"name": "string", "required_evidence": ["string"]},
  "unknowns": ["string"]
}
```

Separate observed facts from proposed next actions. Never claim shipment, deployment, acceptance, or operation from source code alone.
