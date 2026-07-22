---
name: moonsuite-production-gate
description: Produce one candidate-bound Moon Suite engineering evidence draft covering progress, health, production quality, and release rehearsal through nine Gates and three veto redlines. Use when a MoonClaw producer task must inspect a repository and give a separate reviewer task bounded evidence for MoonProj's single engineering system.
---

# MoonSuite Engineering Evidence

Inspect one exact repository revision and produce facts, not ratings, review, or release authority.

## Workflow

1. Resolve the repository remote, branch, full commit, version, and proposed tag.
2. Read repository policy and the product-specific release handover when one exists.
3. Run bounded checks and preserve commands, selected outputs, paths, digests, screenshots, and timestamps as receipts.
4. Evaluate all three redlines and all nine Gates from those same receipts.
5. Keep missing evidence `unknown`; never convert absence of failure into `pass`.
6. Write a producer draft for a separate MoonClaw task to review. Never claim or simulate independent review inside the producer task.
7. Do not tag, push, publish, sign, notarize, or modify the audited repository.

## Execution limits

- Use MoonBit and shell tooling only. Never invoke `python`, `python3`, a Python module, or a Python script.
- Never call an unbounded repository-search tool. Prefer `rg --files`, bounded `rg`, `sed`, `head`, counts, and digests.
- Limit each command output and each receipt to 64 KiB. Summarize larger results with a count, selected paths, exit code, and digest.
- Run mutation-capable build, format, interface, and test commands only in an ephemeral archive of the exact commit.
- Build JSON with `jq`, validate it with `jq`, and publish it with a same-directory atomic `mv`.

For Lepusa/Rabbita macOS apps, treat `docs/LEPUSA_APP_RELEASE_HANDOVER.md` in the audited repository as the release procedure when present. A successful build alone does not satisfy packaging, copied-app smoke, signature, secret, remote, tag, checksum, or release checks.

## Redlines

- `R1`: data, credential, or secret exposure
- `R2`: required compliance, license, qualification, or signing evidence missing
- `R3`: core user, installation, recovery, or rollback path blocked

Any `fail` or `blocked` freezes the candidate. Any `unknown` prevents owner authorization.

## Nine Gates

- `G1` intent, requirements, value, scope, and candidate identity
- `G2` functional completeness and acceptance paths
- `G3` user interface, accessibility, responsive behavior, and user guidance
- `G4` engineering quality, configuration, build, tests, format, static analysis, and coverage policy
- `G5` integration, persistence, refetch/restart consistency, and external-data behavior
- `G6` security, privacy, compliance, licenses, capabilities, and secret scanning
- `G7` artifact reproducibility, resources, compatibility, architecture, and packaging
- `G8` installation smoke, signatures, runtime readiness, telemetry, rollback, recovery, and cleanup
- `G9` repository/branch/commit/tag/checksum/release consistency and owner-controlled publication readiness

The Gates are the lifecycle. Their meanings and order are fixed; do not remap a Gate to a different criterion. MoonProj derives “how far,” “how well,” and “production quality” from the reviewed ledger. Do not return three independent audit artifacts.

## Output

Write JSON with schema `moonsuite.engineering-evidence-draft.v1` and exactly these top-level fields:

```json
{
  "schema": "moonsuite.engineering-evidence-draft.v1",
  "project": "moonproj",
  "repository": "git@github.com:vectie/moonproj",
  "branch": "main",
  "commit": "full-sha",
  "version": "0.1.0",
  "tag": "v0.1.0",
  "observed_at": "ISO-8601",
  "producer_agent": "audit-id:producer",
  "redlines": [
    {"id":"R1","status":"pass","summary":"string","receipts":["string"],"missing":[]}
  ],
  "gates": [
    {"id":"G1","status":"pass","summary":"string","receipts":["string"],"missing":[]}
  ],
  "findings": []
}
```

Return exactly R1–R3 and G1–G9 once each. Allowed status values are `pass`, `fail`, `blocked`, `unknown`, and `not_applicable`. `not_applicable` requires a receipt identifying the governing policy. The producer draft has no `review` field.

Only MoonProj computes projections and determines `ready_for_owner_authorization`. Only the Owner or an explicitly authorized release system may approve or execute publication.
