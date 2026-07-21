# Moon Suite engineering control plane

## Product decision

MoonProj is the engineering control plane for Moon Suite. It answers three
separate questions for each registered project:

1. **How far has it gone?** Lifecycle stage, completed milestones, current
   Gate, blockers, and next required evidence.
2. **How well is it going?** Reproducible build, test, format, static-analysis,
   security, and operational checks at an exact commit.
3. **Does it meet production quality?** Three release redlines followed by
   G1-G7 criterion evidence for a precise release candidate or artifact digest.

MoonProj owns the registry, policy, presentation, and human decisions. MoonClaw
owns agent execution and receipts. Audit skills own the evaluation method. A
different reviewer Agent verifies producer evidence. No layer may silently turn
missing evidence into a pass.

## First portfolio

`config/moonsuite-engineering.json` registers the first nine services:
MoonProj, MoonClaw, MoonBook, MoonTown, MoonDesk, MoonGate, MoonRobo, MoonMoon,
and MoonFish. MoonFish remains an investment-analysis extension; its presence
does not couple the basic engineering product to the broader OPC domains.

## UI workflow

The Moon Suite page is the entry point:

1. Select a registered project.
2. Observe all three dimensions as **unknown** before evidence exists.
3. Choose **Let MoonClaw start audit**.
4. The authenticated MoonProj gateway validates the project identifier against
   its allowlist, resolves its repository below `MOONSUITE_WORKSPACE_ROOT`, and
   submits a task to `MOONCLAW_DAEMON_URI`. The task runs in MoonProj so its
   controller and skills are discoverable; the selected sibling is passed as a
   separate read-only audit target.
5. The task prompt requires the progress, health, production-Gate, and
   independent-review skills and points to the controller contract in
   `moonclaw.jobs.json`. If the runtime cannot establish a different reviewer
   identity, the review remains pending rather than being treated as accepted.
6. The task identifier is displayed. A production conclusion remains unknown
   until independent review accepts its supporting evidence.

This first slice submits and identifies the audit task. Persisted task-status
and evidence ingestion are the next slice; the UI deliberately does not
fabricate a result while those connectors are absent.

## Agent skills

- `skills/moonsuite-progress-audit`: evidence-backed lifecycle progress.
- `skills/moonsuite-health-audit`: repository-declared engineering checks.
- `skills/moonsuite-production-gate`: redlines and G1-G7 criteria.
- `skills/moonsuite-evidence-review`: independent reproduction and verdict.

The producer contracts are read-only. They record exact commit, observation
time, command, exit status, and evidence reference. The reviewer rejects stale,
unreproducible, self-reviewed, or unsupported claims.

## Problems found and fixes

| Problem encountered | Why it was harmful | Fix in this slice |
| --- | --- | --- |
| The UI showed invented versions, CI results, coverage, grades, and Gate scores. | Demo values looked like company facts and could drive unsafe release decisions. | Removed the values from Moon Suite and production-quality views; unobserved state is now `unknown`. |
| Progress, health, and production readiness were conflated. | A project can be advanced but unhealthy, or healthy but not production-ready. | Defined three independent schemas, skills, and UI cards. |
| An Agent could produce and approve the same claim. | Self-review makes model confidence look like verification. | Added an independent-review skill and a different-identity requirement. |
| Progress percentages had no declared denominator. | Commit/file counts are not project completion. | Percentages are forbidden unless milestones and their denominator are declared. |
| Passing a build could be interpreted as production readiness. | Production also requires product, security, compliance, deploy, rollback, and operations evidence. | Added R1-R3 redlines and G1-G7 criterion states at an exact candidate digest. |
| Missing and skipped checks could look successful. | Absence of failure is not evidence of success. | Contracts distinguish `pass`, `fail`, `unknown`, and `not_applicable`. |
| Evidence was not tied to a revision or time. | Results become stale or cannot be reproduced. | Every producer records full commit SHA, observation time, commands, exit status, and receipts. |
| The browser would need an unsafe arbitrary `cwd` to call MoonClaw directly. | It creates path-injection and CORS/security problems. | Added an authenticated same-origin endpoint with a fixed project allowlist and server-side path resolution. |
| Launching MoonClaw inside a sibling repository hid MoonProj's local jobs and skills. | The controller would silently be unavailable for every project except MoonProj. | Tasks now run in the MoonProj control workspace and receive the registered sibling path as their audit target. |
| The daemon task endpoint is an Agent conversation, not the channel job-command parser. | Sending `/plan-job` there would look orchestrated in the UI without necessarily entering MoonClaw's proposal runtime. | The UI submits an explicit audit task that names all four skills and the controller contract; it does not claim proposal confirmation occurred. |
| MoonClaw unavailability could tempt the UI to use fixture results. | A connectivity failure would become a false quality claim. | Fail closed: show connection failure and create no score. |
| Rabbita exposes non-2xx response bodies through the text callback. | The first browser test interpreted a 401 JSON body as an accepted audit. | Submission now requires a non-empty `task_id`; every other body enters the explicit failure state. |
| The repositories have different lifecycles. | A hardware project cannot use the same progress stages as a web service. | Registry and skill distinguish software from hardware/software stages. |
| Trend claims lacked a persisted baseline. | A single observation cannot establish improvement or decline. | No trend is shown in this slice; evidence persistence is explicitly required first. |
| The skill scaffolder was not executable directly. | Initial skill creation stopped before any product code changed. | Invoked the official scaffold tool through its interpreter; this is development tooling only and adds no Python runtime to MoonProj. |

## Remaining connector work

The truthful boundary is intentional: task submission works through the UI, but
MoonProj does not yet poll MoonClaw events or persist normalized audit artifacts
to PostgreSQL. Until that is implemented, the UI displays the MoonClaw task id
and keeps the three conclusions unknown. The next migration slice should add:

1. authenticated task-status polling;
2. strict JSON-schema validation for all five contracts;
3. PostgreSQL tables for observations, evidence receipts, reviewer verdicts,
   candidate digests, and supersession;
4. an accepted-evidence projection endpoint for the three UI dimensions;
5. freshness policy and scheduled re-audit through MoonTown;
6. controlled remediation-task creation only from accepted findings.

## Runtime configuration

The gateway defaults to MoonClaw at `http://127.0.0.1:18123`. Override with
`MOONCLAW_DAEMON_URI`. It resolves repositories relative to the parent of the
gateway working directory; override with an absolute `MOONSUITE_WORKSPACE_ROOT`.
The existing PostgreSQL company service remains the business system of record.
No MySQL or Python runtime has been added.
