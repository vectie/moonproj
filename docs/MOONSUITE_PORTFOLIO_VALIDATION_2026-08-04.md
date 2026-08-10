# Moon Suite portfolio validation — 2026-08-04

- Status: diagnostic validation, not trusted release evidence
- Scope: the nine services registered by `config/moonsuite-engineering.json`
- Toolchain: `moon 0.1.20260803`, `moonc v0.10.6+62c2592d1`, native target
- Host: local macOS workspace, temporary PostgreSQL 18 database, local MoonProj
  company service and authenticated gateway

## Executive result

MoonProj can load and display all nine services in its current engineering
portfolio. The authenticated browser, gateway, PostgreSQL service, missing
projection contract, product selection, candidate form, and G1-G9 fail-closed
release UI all worked. None of the nine services has a current independently
reviewed engineering ledger, so MoonProj correctly displays all three product
questions as `unknown` and keeps release authorization locked.

The complete operational use case does not pass. The MoonClaw daemon expected
at port 18123 was unavailable, so the UI could not start the producer/reviewer
audit pair. The failure was presented as a connection failure and did not
create a score or release claim. Repository diagnostics also found three
native-test blockers, one MoonBook assertion failure, warning-clean failures in
all nine repositories, material dirty worktrees in MoonClaw and MoonTown, and
repository-identity gaps.

This report must not be ingested as `moonsuite.engineering-evidence.v2`.
Commands were run directly for diagnosis and were not independently reviewed,
candidate-digest bound, or accepted by the MoonProj evidence service.

## What “all Moon Suite projects” means today

MoonProj currently defines “all” as its first portfolio of nine services:
MoonProj, MoonClaw, MoonBook, MoonTown, MoonDesk, MoonGate, MoonRobo, MoonMoon,
and MoonFish. The same nine identifiers are separately hard-coded in the JSON
portfolio, gateway allowlist, Moon Suite UI, and Quality UI.

That is not the same boundary as MoonLib's default product-home registry. The
MoonLib registry currently contains 17 identifiers and additionally includes
MoonWiki, MoonCode, MoonFlow, MoonChat, MoonVis, MoonMold, Bookkeeper, Lepusa,
and Rabbita, while it does not include MoonProj. The workspace also contains
other Moon-named repositories, including MoonCast, MoonFind, MoonEdit, MoonLeaf,
and MoonStat, which are not in either MoonProj's engineering portfolio or the
MoonLib default registry.

Therefore this validation proves all **registered MoonProj engineering
services**, not every MoonSuite product home, embedded product, support tool,
or Moon-named repository. A single authoritative classification and discovery
contract is required before MoonProj can truthfully offer a complete dynamic
suite view.

## Portfolio analysis matrix

`Check` is `moon check --target native`. `Test` is
`moon test --target native`. `Strict` is
`moon check --target native --deny-warn`. Dirty counts are the baseline at the
start of this validation and include pre-existing local work.

| Product | Declared maturity | Load/UI | Repository baseline | Check | Test | Strict | Failing now | Recommended next move |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MoonProj | Preview/alpha control plane; Product In-Gate `experiment` | Pass; authenticated projection is `unknown`, release locked | `main` at `7c22db669308`; 8 local changes; GitHub origin and module identity agree | Pass | **Blocked before full suite**: multiple native blackbox commands fail to link `_moonbit_get_cli_args` on arm64 | **Fail: 21** warning-as-error diagnostics | Native release tests cannot complete; no trusted ledger; MoonClaw offline; portfolio duplicated in four places; project-plan artifact is not reviewable in the UI | Reproduce the linker failure with a minimal CLI blackbox package and pin or fix the toolchain/runtime; restore MoonClaw; make one registry feed gateway and both UIs; add the missing plan-artifact review loop before claiming end-to-end governance |
| MoonBook | Local alpha, L2 usable locally | Pass; projection `unknown` | `main` at `61efe76052af`; clean; GitHub origin; module repository is empty | Pass | **360/361 pass**; `wiki/ui_reader_content_wbtest.mbt:68` has a leading-space mismatch | **Fail: 17** | One deterministic reader-summary regression; no trusted ledger; warning debt; release identity incomplete in `moon.mod` | Fix or deliberately normalize leading whitespace and retain the regression test; fill canonical repository metadata; clear strict diagnostics; then run backup/recovery and acceptance paths under an independent audit |
| MoonClaw | Advanced local alpha, L2 | Pass; projection `unknown` | `main` at `5fdc845f2a92`; **154 local changes**; origin is Gitee `vectie/mcl` while module metadata names GitHub `vectie/moonclaw` | Pass | **Blocked before full suite** by a compiler internal error while linking `internal/uuid` (`Uuid7variant`, scalar destination type mismatch) | **Fail: 26**, plus target-declaration warnings | Audit daemon is not listening; compiler ICE prevents a clean suite result; large dirty worktree and repository identity mismatch make candidate binding unsafe | Preserve and split the dirty work by intent; reduce the UUID ICE to a minimal reproducer and test a known-good compiler; reconcile canonical origin; start and health-check the daemon only from a clean, identified candidate; then rerun producer/reviewer isolation tests |
| MoonTown | Experimental local alpha | Pass; projection `unknown` | `main` at `b582c013763d`; **9 local changes**, including UI/evidence artifacts; no Git origin; module metadata names GitHub | Pass | **1082/1082 pass** | **Fail: 6** | Test suite passes, but release identity is not fetchable and the worktree is not candidate-clean; no trusted ledger | Preserve the current UI work, move generated evidence out of release source, establish a canonical origin, clear strict diagnostics, then run restart/standing-goal continuity under MoonClaw review |
| MoonDesk | Local single-user alpha; signed/notarized release not ready | Pass; projection `unknown` | `main` at `27b846bb1701`; clean; no Git origin and empty module repository | Pass | **368/368 pass** | **Fail: 150** | Largest warning-clean gap in the portfolio; missing canonical repository identity; clean-machine packaging/signing evidence absent | Make warning cleanup a dedicated migration, establish repository identity, then validate live graph handoff, restart recovery, clean-machine bundle, signing, notarization, install, and rollback |
| MoonGate | Feature-testing alpha | Pass; projection `unknown` | `main` at `a0da72dcc0cb`; clean; origin is Gitee `vectie/hij` while module metadata names GitHub `vectie/moongate` | Pass | **868/868 pass** | **Fail: 13**, plus 12 target-declaration warnings | Its own release policy requires warning-clean checking, so the current candidate is not releasable; repository identity differs; its health endpoint correctly requires authentication | Treat `--deny-warn` as a blocking gate, add explicit supported targets, reconcile origin/module identity, and run authenticated provider, credential-storage, metrics, restart, and rollback tests without exposing credentials |
| MoonRobo | Experimental bounded hardware/software | Pass; projection `unknown` | `main` at `22a112a08b04`; clean; GitHub origin and module identity agree | Pass | **Blocked before full suite**: native blackbox packages fail to link `_moonbit_get_cli_args` | **Fail: 6** | Native qualification cannot complete; no hardware evidence ledger; software-only checks cannot authorize physical execution | Share the MoonProj linker reproducer/toolchain fix; keep physical actions disabled; after software recovery, bind hardware revision, safety envelope, adapter receipts, dry runs, abort/recovery, and operator authorization to one candidate |
| MoonMoon | Digital simulation alpha | Pass; projection `unknown` | `main` at `7ac7e6d93dd9`; clean; no Git origin; module metadata names GitHub | Pass | **208/208 pass** | **Fail: 3** | Tests are green, but no fetchable origin, warning-clean result, provenance ledger, or independently reviewed simulation candidate exists | Add the canonical origin, clear the three strict diagnostics, then replay a signed data/provenance snapshot and verify deterministic mission results through an independent reviewer |
| MoonFish | Shadow-only alpha; required shadow cohort not accrued | Pass; projection `unknown` | `main` at `275c38db0cb9`; clean; GitHub origin; module repository is empty | Pass | **387/387 pass** | **Fail: 13** | Code tests pass, but data licensing/provenance, warning-clean release, 120-session shadow evidence, and trusted engineering ledger are missing | Fill repository metadata, clear strict diagnostics, bind licensed source snapshots and model versions, complete the declared 120 shadow sessions, and review accuracy/risk results before any decision authority is enabled |

## Cross-product test findings

### P0 — blocks the real MoonProj use case

1. **MoonClaw audit execution is unavailable.** A live browser candidate
   submission reached the authenticated MoonProj boundary but the local daemon
   at port 18123 was not listening. MoonProj correctly failed closed, but no
   product can obtain a new trusted projection until producer and reviewer
   tasks can run and return an accepted ledger.
2. **Native test execution is broken in three repositories.** MoonProj and
   MoonRobo share the missing `_moonbit_get_cli_args` linker symbol. MoonClaw
   triggers a MoonBit compiler internal error. Because normal type checking
   passes, these look like native test/toolchain or generated-linkage problems,
   but that is a hypothesis until reduced reproducers confirm it.
3. **The full suite boundary is not authoritative.** MoonProj's nine-service
   portfolio, MoonLib's 17 product homes, and extra workspace repositories are
   different sets. The hard-coded UI and allowlist cannot discover additions
   and can silently drift apart.

### P1 — blocks candidate quality

1. **Every registered repository fails `--deny-warn`.** The current counts are
   MoonProj 21, MoonBook 17, MoonClaw 26, MoonTown 6, MoonDesk 150, MoonGate 13,
   MoonRobo 6, MoonMoon 3, and MoonFish 13. Common causes are ambiguous `{}` map
   literals, deprecated JSON/HTTP/file APIs, and missing supported-target
   declarations.
2. **MoonBook has one functional regression.** Its reader summary preserves an
   unexpected leading space when an explicit main message is selected.
3. **Candidate identity is weak in six repositories.** MoonClaw and MoonGate
   disagree between Git origin and module metadata; MoonTown, MoonDesk, and
   MoonMoon have no origin; MoonBook, MoonDesk, and MoonFish have empty module
   repository metadata. Exact repository identity is required by G9.
4. **Dirty candidates are material.** MoonClaw has 154 changes and MoonTown has
   9. MoonProj also began with 8 intentional local documentation changes. No
   release evidence should be bound to these worktrees until their exact scope
   is reviewed and committed or deliberately excluded.

### P2 — product and UX completeness

1. **The Projects page is still fixture-driven.** In Moon Suite mode it renders
   four seeded rows (`OPC Core v0.9`, `Agent Evidence Bus`, `Edge Node MkII`,
   and `Company Control Pack`) with percentages and health labels. They are not
   the nine registered engineering projections and can be mistaken for current
   company facts.
2. **The governed project-plan adapter is not a UI-to-UI workflow.** MoonProj
   can create and validate a plan pack through its adapter, but the current UI
   does not render the artifact, let an operator review it, or show its exact
   MoonFlow handoff and recovery receipts.
3. **Demand evidence remains separate and incomplete.** Engineering checks do
   not upgrade the Product In-Gate. MoonProj remains in `experiment`; each
   product needs its own commitment-backed adoption evidence before broad
   expansion is justified.

## UI-to-UI validation matrix

| Use case | Result | Observed behavior |
| --- | --- | --- |
| Start a clean local MoonProj stack | Pass | Frontend built; PostgreSQL schema initialized; company service and gateway listened on temporary local ports |
| Establish a browser session | Pass | Visiting `/` created the desktop actor session; `/api/session` returned the authenticated validation actor |
| Enter Moon Suite mode and open Moon projects | Pass | The banner and navigation changed to Moon Suite, then `/moon` rendered the engineering control plane |
| Persist a Product In-Gate experiment | Pass | The Moon Suite form recorded the solution hypothesis, demand context, receipt references, outcome/adoption packet, signed owner, and `exit_gate_effect=false` through the authenticated gateway |
| Restart and reload Product In-Gate | Pass | After restarting the native company service and reopening Moon Suite, PostgreSQL returned the same persisted `experiment` decision and owner; the isolated v2 smoke also proved idempotent replay and pass-evidence rejection |
| Keep Product In-Gate out of Quality | Pass | The Moon Suite page rendered one In-Gate panel; the Quality page rendered zero In-Gate panels and one unified G1-G9 evidence ledger |
| Load every registered product | Pass, 9/9 | Each of the nine unique product buttons selected exactly one matching `<product> · 审计编排` view |
| Load product projections | Pass, 9/9 | Every authenticated project endpoint returned HTTP 200 with schema `moonsuite.engineering-projection.v1`, revision 0, `trusted=false`, `freshness=missing`, and `review_verdict=needs_evidence` |
| Keep missing evidence fail-closed | Pass | “How far,” “how well,” and “can it ship” remained `unknown`; no score, grade, or progress percentage was invented |
| Open Quality and switch candidates | Pass, 9/9 | Every selector produced exactly one matching `<product> · 发布候选` heading |
| Declare an exact candidate | Pass | Branch, version, and proposed tag accepted `main`, `0.1.0-preview.3`, and `v0.1.0-preview.3`; repository and commit correctly remained unknown without evidence |
| Inspect the release ledger | Pass | G1-G9 rendered separately, each with no independently reviewed receipt and state `unknown`; Owner authorization remained locked |
| Start the MoonClaw audit | **Operational fail; safety pass** | UI reported connection failure, retained all unknown states, generated no conclusion, and did not expose a release bypass |
| Inspect the generic Projects page in Moon mode | Partial | Page, phase legends, four fixture rows, and the blocked hardware row rendered, but the page is not connected to the nine-service engineering registry |
| Browser console | Pass | No browser `error` or `warn` entries were observed during the tested flow |

## Recommended recovery order

1. Restore and health-check MoonClaw on the configured URI, then run one
   producer/reviewer rehearsal against a clean, low-risk project such as
   MoonMoon. Prove task separation, exact candidate identity, bounded receipts,
   inbox ingestion, and projection refresh before scaling to nine projects.
2. Reduce the two native toolchain failure classes: one minimal CLI blackbox
   reproducer for `_moonbit_get_cli_args`, and one UUID reproducer for the
   MoonClaw compiler ICE. Pin the last known-good MoonBit toolchain if needed;
   do not weaken tests to make the dashboard green.
3. Fix the MoonBook whitespace regression and rerun its full native suite.
4. Burn down warning-as-error failures, starting with MoonGate because its own
   release contract already requires warning-clean validation, then MoonDesk
   because it has 150 diagnostics.
5. Define one portfolio source of truth with explicit classes such as
   `service`, `embedded-product`, `support-runtime`, and `excluded`. Serve that
   registry from the authenticated backend and render both Moon Suite and
   Quality selectors from it. Generate the audit allowlist from the same
   validated data and add a test that rejects registry/UI/gateway drift.
6. Reconcile Git origins and `moon.mod` repository fields, preserve dirty work,
   and bind later audits only to clean full commits and candidate digests.
7. Replace or clearly label fixture values on the Projects page and connect it
   to the accepted engineering projections. Add the missing UI review and
   recovery loop for governed project-plan artifacts.
8. Keep the Product In-Gate separate: run narrow, commitment-backed experiments
   for products without adoption evidence. Passing builds or G1-G9 cannot prove
   that users will repeatedly use the product.

## Evidence boundaries and cleanup

The validation used an isolated temporary database and local service ports. It
did not write engineering evidence into the company store, change any sibling
repository, start a physical action, tag, push, publish, sign, or notarize. The
only durable artifact from this validation is this report and its documentation
index entry.
