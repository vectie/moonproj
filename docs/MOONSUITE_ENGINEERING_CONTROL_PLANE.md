# Moon Suite engineering control plane

## Product decision

MoonProj is the engineering control plane for Moon Suite. It answers three
questions from one candidate-bound evidence ledger for each registered project:

1. **How far has it gone?** Lifecycle stage, completed milestones, current
   Gate, blockers, and next required evidence.
2. **How well is it going?** Reproducible build, test, format, static-analysis,
   security, and operational checks at an exact commit.
3. **Does it meet production quality?** Three release redlines followed by
   G1-G9 criterion evidence for a precise release candidate or artifact digest.

These are projections, not three audit systems. The nine Gates are the shared
lifecycle and release control structure. A single receipt may support more than
one projection, but it is stored once and remains tied to one repository,
branch, full commit, version, and proposed tag.

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
5. The task prompt requires one `moonsuite.engineering-evidence.v2` ledger with
   R1-R3 and G1-G9, followed by independent review. If the runtime cannot
   establish a different reviewer identity, the review remains pending rather
   than being treated as accepted.
6. The gateway issues an audit identifier before submission. MoonClaw writes
   the final independently reviewed envelope to the corresponding controlled
   inbox path and changes no audited repository files.
7. Rabbita polls the authenticated gateway. While MoonClaw is generating, or
   while an idle task has not produced its envelope, all conclusions remain
   unknown.
8. The native PostgreSQL service rejects schema drift, mismatched projects or
   commits, missing or duplicate Gate ids, non-full commit digests, unsupported states, and self-review. It
   stores accepted observations, review receipts, candidate digests, and an
   immutable superseding projection revision.
9. Rabbita loads only the service projection. Evidence older than seven days
   is marked stale and is not presented as a current trusted conclusion.
10. A remediation command appears only when a fresh accepted review contains
    findings. The service repeats that guard, so UI bypass cannot manufacture
    remediation work.

## One Gate system

- G1 target, requirements, value, scope, and candidate identity.
- G2 functional completeness and acceptance paths.
- G3 UI, accessibility, responsive behavior, and guidance.
- G4 build, test, configuration, static analysis, and engineering quality.
- G5 integration, persistence, refetch/restart consistency, and external data.
- G6 security, privacy, compliance, licenses, capabilities, and secrets.
- G7 artifact reproducibility, resources, compatibility, and packaging.
- G8 installation, runtime readiness, operations, rollback, recovery, and cleanup.
- G9 repository, branch, commit, tag, checksum, release consistency, and publication control.

`skills/moonsuite-production-gate` now produces the unified ledger. The older
progress and health skills remain migration references for legacy v1 evidence;
new runs must not emit three independent artifacts.

The producer contract is read-only. It records exact candidate identity,
observation time, Gate states, and receipts. The reviewer rejects stale,
unreproducible, self-reviewed, or unsupported claims. MoonProj derives all three
dimensions and the `ready_for_owner_authorization` state; the Agent cannot award
itself release authority.

## Release rehearsal

The Quality page is the release dashboard for the same system. An operator
chooses a registered project and declares branch, version, and proposed tag.
MoonClaw tests that exact candidate against G1-G9, applying the Lepusa app
handover where relevant. The rehearsal never tags, pushes, publishes, signs, or
notarizes. Even when every Gate passes, the result is only
`ready_for_owner_authorization`; publication remains a separate Owner action.

## Problems found and fixes

| Problem encountered | Why it was harmful | Fix in this slice |
| --- | --- | --- |
| Progress, health, production, and release rehearsal were modeled as separate producer systems. | The same command could be copied into contradictory artifacts, and the UI could imply four independent truths. | Replaced new-run ingress with one strict `moonsuite.engineering-evidence.v2` ledger; MoonProj derives all three dimensions and release state from it. |
| The production policy stopped at G7 while the Lepusa handover separately checked integration, packaging, installation, Git, checksum, and release consistency. | A broad “release” Gate hid materially different failure modes and made a passing build look closer to publication than it was. | Expanded the shared lifecycle to G1-G9, with explicit integration, artifact, installation/operation, and release-control boundaries. |
| An audit request named only a project, not a branch, version, and proposed tag. | Results could not prove which release candidate the operator meant to test. | The dashboard now requires candidate labels and the v2 envelope records repository, branch, full commit, version, and tag. |
| A release checklist could be mistaken for release execution. | Tagging, pushing, signing, notarizing, and publishing are owner-impacting mutations. | The MoonClaw rehearsal is read-only and can only reach `ready_for_owner_authorization`; publication remains outside the rehearsal action. |
| The first rendered release dashboard showed `moontown` while its request model still targeted `moonproj`. | Quality had retained a second product selector, so the visible candidate and submitted candidate could diverge. | Removed the separate Quality selection state; both pages now use the single engineering-project identity. |
| Loading a missing PostgreSQL projection replaced the operator's requested `main` branch with `unknown`. | Starting a first rehearsal would fail candidate validation even though the form had a valid default. | Missing historical metadata no longer overwrites the candidate form; only observed branch identity replaces operator input. |
| Navigation still advertised the retired seven-Gate policy after the dashboard moved to nine Gates. | Operators could not tell which policy governed the run. | Updated navigation, dashboard copy, controller prompts, and skill metadata to the same G1-G9 vocabulary. |
| An unauthenticated browser run reported only a generic daemon/gateway failure. | The fail-closed behavior was correct, but the operator could not distinguish missing session identity from unavailable infrastructure. | The dashboard failure copy now names authentication and infrastructure without claiming which one failed. |
| MoonClaw listened on IPv6 `localhost`, while MoonProj defaulted to IPv4 `127.0.0.1`. | The authenticated self-release request reached MoonProj but could not connect to the running Agent daemon. | Changed the default daemon URI to `http://localhost:18123`, matching MoonClaw's advertised endpoint while retaining environment override support. |
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
| MoonClaw exposes finite task status but no finite final-answer endpoint. | Reading its event stream with a normal HTTP body reader would block indefinitely, while treating `idle` as success could lose the result. | Added a server-issued audit id and controlled, size-bounded evidence inbox; `idle` without a file is explicitly `awaiting_artifact`. |
| MoonClaw names its active task state `generating`, while the UI model used `running`. | Polling would stop after the first successful status response and incorrectly show failure. | The gateway normalizes `generating` to the UI's `running` state and tests the task-status decoder. |
| Agent JSON could add plausible-looking fields or mix commits across artifacts. | Lenient decoding turns contract drift or unrelated evidence into trusted facts. | Added exact-key validators for the envelope and four evidence contracts, full commit validation, cross-artifact identity checks, and independent-review enforcement. |
| A successful Agent run was not durable engineering state. | Results could disappear and had no replay, digest, or supersession trail. | PostgreSQL now stores raw evidence, review receipts, candidate-digest receipts, and immutable `engineering_project` projection revisions using idempotent source ids. |
| Old accepted evidence could remain visually authoritative. | A once-passing build does not prove the current repository is healthy or releasable. | The service applies a seven-day freshness boundary, downgrades stale trust, and ships an installable MoonTown standing goal for recurring stale-evidence review. |
| A generic action button could create work from unreviewed model suggestions. | Agent speculation could enter the operational backlog. | Remediation is allowed only from fresh, accepted, persisted findings and remains idempotent. |
| A delayed poll or projection response could arrive after the operator selected another project. | Evidence from one repository could appear under another repository's name. | Every asynchronous Rabbita result now carries its project identity; the reducer discards responses that no longer match the selected project. |

## Connector status

The connector slice is implemented:

- authenticated MoonClaw task polling and explicit `awaiting_artifact` state;
- strict native MoonBit validation for the five ingress contracts;
- PostgreSQL persistence using typed `company_record` records and immutable
  `company_aggregate_projection` revisions;
- an accepted-evidence read projection for progress, health, and production;
- seven-day freshness enforcement and a MoonTown standing-goal definition;
- controlled, idempotent remediation creation from accepted findings only.

The MoonTown definition is deliberately delivered as product configuration,
not silently written into another product's home. Install or update it with
`scripts/install_moontown_engineering_goals.sh`; the script merges by goal id.
The scheduled watcher raises a `needs-review` decision for stale or missing
projects. An authenticated operator launches the audit in MoonProj, preserving
the UI authorization and independent-review boundary.

No repository currently has a trusted score merely because these connectors
exist. Each project remains missing/unknown until a real MoonClaw run produces
an envelope that the independent reviewer and PostgreSQL service accept.

## Runtime configuration

The gateway defaults to MoonClaw at `http://localhost:18123`. Override with
`MOONCLAW_DAEMON_URI`. It resolves repositories relative to the parent of the
gateway working directory; override with an absolute `MOONSUITE_WORKSPACE_ROOT`.
The existing PostgreSQL company service remains the business system of record.
No MySQL or Python runtime has been added.
