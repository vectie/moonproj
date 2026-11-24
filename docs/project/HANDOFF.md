# MoonProj project handoff

## Deliverable clarity and MoonDesk context — 2026-11-24

Coordinated work leads with the promised deliverable, Now / Next / Needs you,
real contribution rows, and the marked integrated draft. Each contribution
opens its substantive saved answer and artifact references. Office uses the
same recorded responsibility and contribution link. Missing legacy information
stays unknown; worker completion never means integration, review or acceptance.
The redundant Dispatch journey/header no longer contradicts stopped work.
Task loading has its own surface rather than flashing unrelated task controls.

New initial and coordinated revision prompts request a per-command
`.moonproj-progress-<command>.json` note in the captured coordinator workspace.
It describes the deliverable, current work, next step, requested owner input,
and each exact worker ID's responsibility/contribution target. The gateway
reads at most 64 KiB through the existing confined file reader, checks task /
command identity and projects only explanatory fields. No second task store,
poller, approval system or completion gate was added. The note is agent-authored
intent, not terminal evidence; its path is excluded from deliverable artifacts.
An integrated draft needs both the note's output path and an attributed artifact
from that exact command. Old notes cannot describe a successor's result.

Worker readback now preserves the native bounded answer, truncation indicator
and child Book root, rather than discarding the actual contribution when saving
status. It cannot reconstruct answers that older stopped records already lost.
The latest coordinated revision's outcome overrides the original command's
outcome in the user-facing status. Human-selected revisions retain their exact
immutable identity; accepted work shows the accepted report rather than calling
mutable workspace bytes the accepted version.

MoonDesk links carry an escaped display-only task title; the canonical task /
run / command / Book checks remain unchanged. Desk displays the title, an editing
purpose, and a direct return to MoonProj. Exiting clears the title hint too.
Editing/returning does not submit, accept, resume or start an agent. The existing
cross-product revision editor supports UTF-8 text up to 256 KiB, not an arbitrary
Office/PDF round trip. Non-text/accepted outputs are labeled Open, not Edit.

Real browser testing found a remaining integration blocker: the smoke task's
generated nested coordinator Book is not in the installed MoonDesk host's active
library. Navigation carries the exact task and returns correctly, but resolution
stops at unknown_workspace. Do not weaken library/Book scope checks or claim an
end-to-end edit/save round trip passed. Workspace ownership/discovery needs a
separate root fix. Both SSH attempts to cluster Mac 192.168.2.195 timed out; the
user's latest Downloads dissertation folder was not opened or modified.

Validation: 571 frontend JS tests, 270 native service/gateway tests and 840
MoonDesk main UI tests pass; locale checks and release builds pass. No public
interface changes. The isolated index snapshot excludes unrelated user work and
passes 570 frontend tests. Browser checks cover the real stopped smoke record, same-task
Desk navigation/return and a clearly labeled illustrative contribution fixture
at 375px without horizontal overflow. No provider run, dissertation review,
packaged-app installation or cluster deployment is qualified. Screenshot:
`/tmp/moonproj-delivery-clarity-verified.jpg`. Unrelated plan/GitHub-import edits
and MoonDesk's pre-existing HANDOFF changes remain excluded.
The temporary test services and disposable database are stopped. MoonDesk's
generated dist changes were restored after archiving the verified build at
`/tmp/moondesk-clarity-dist-verified.tgz`; source-only changes are committed.

## One task per office — 2026-11-24

Office and fleet now show only one selected task's team. A native, labeled 任务
dropdown defaults to the newest created regular task; objectives are not jobs
in this picker. Switching clears member selection/error/pending reads, keeps the
chosen view and does not start work. Task-scoped desk keys prevent an inspector
from following a reused session into a different job. Selection survives a work
refresh while still valid; a missing selection falls back to the newest task.
Reload starts at the newest task. A selected job without execution stays empty,
with a direct 查看任务 action, rather than borrowing another job's agents.

The task-list projection now exposes `createdAt` from the first saved projection
timestamp, computed within the existing SQL read; status updates do not make old
jobs newest. No schema migration, N+1 lookup, polling or execution authority is
added. Tasks without a creation time sort after dated records, with IDs breaking
ties deterministically. The dropdown, floor and inspector use one task filter.

Validation: 563 frontend JS tests pass in the combined tree. The isolated staged
snapshot excludes unrelated user work and passes 562 frontend plus 266 native
tests and its release UI build. Native service release, `moon check`, `moon info`,
scoped formatting and diff checks pass; no generated interface changes. Real
PostgreSQL readback confirms creation times. Browser checks cover newest default
and reload, older/unstarted task selection, cleared inspector, map/list isolation,
keyboard dropdown and 375px layout without horizontal overflow. No agents were
started or resumed. Screenshot: `/tmp/moonproj-office-one-task-verified.jpg`.
No packaged-app update or cluster deployment is included.

## Office clarity pass — 2026-11-24

The office now leads with simple role seats (负责人 / 专员 1, 2), one status
per desk, and one task title per team. These are display labels for the same
real session identities, not new employee records or inferred specialties.
Original worker names, model, IDs, book paths, source and read timestamp remain
available under 详细记录. The main inspector shows work, available results and
one 查看任务 action. Completion explains that a worker's finished part is not
whole-task acceptance; stopped work explains how to continue. Recovery remains
visible on read failure; an empty office links to arranging work in Objectives.
No backend behavior, polling, dependencies or execution authority changed.

Validation: 560 frontend JS tests pass in the combined tree; the isolated
commit-only snapshot excluding user changes passes 559 tests and the release
frontend build. `moon check`, `moon info`, scoped formatting and diff checks pass,
without public-interface changes. Real saved smoke records were checked in the
browser: desk selection, list/map preservation, technical disclosure, task link,
keyboard focus and 375px layout (367px content width). No agents were started or
resumed. Screenshot: `/tmp/moonproj-office-simple-verified.jpg`. No packaged-app
update or cluster deployment is included; unrelated user changes stay excluded.

## Mini office, real run identities — 2026-11-24

More tools → Agent 编队 now switches between 迷你办公室 and a compact fleet
list. Both use the same company task/execution projection and preserve selection.
Click a real coordinator or worker to see its linked tasks, execution stage,
separate business task stage, recorded summary/output references and exact source;
Open task uses the existing task workspace. These are per-run identities, not
invented permanent employees or an online/idle roster. No animation, extra task
store, orchestrator or provider invocation was added. Shared UI tokens, responsive
stacking and keyboard focus/return keep the feature inside the existing UI.

`GET /api/company/tasks/:id/office` reads the authenticated canonical task and,
where available, the existing MoonClaw inspect-only task panel for that captured
session/book. It does not call delivery reconciliation, start/resume a turn,
submit a report or accept work. The projection excludes native personal memory
and arbitrary result fields. Observations are demand-loaded per task; refreshing
the company records invalidates the cache. Superseded actor/scope/read callbacks
cannot replace current selection data; read failures keep saved records visible.
Company-wide scope reuses the existing bounded project reader and explicitly
marks partial results, rather than presenting an incomplete roster as complete.

The local native task panel returns 404 for suspended chats. A confirmed stopped
task therefore shows its saved canonical execution/worker records without trying
to unseal it. Active-session inspect failures remain explicit. Stopped controls
override stale running fields; completed workers do not imply accepted tasks.
A planned child confirmed missing by the suspension receipt has no desk.
The task drill-down headline now also respects stopped/pending control states.
Read timestamps use JSON numbers, matching the frontend timestamp contract.

Validation: 558 frontend JS and 266 native service/gateway tests pass in the
combined tree; the exact staged snapshot excluding unrelated user work passes
557 frontend plus 266 native tests and the release frontend build. Native release,
`moon info`, scoped formatting and diff checks pass; no public-interface changes.
Local browser checks used the two existing real smoke runs: five actual desks,
individual task/stage/output drill-down, map/list selection preservation, correct
task navigation, Enter/close focus and 390px layout. No agents were started or
resumed to populate this view. No cluster deployment or packaged-app installation
is included. User-owned plan/GitHub-import work remains excluded from the commit.

## Coordinated delivery, not another control plane — 2026-11-24

Delegated objective work now explicitly uses coordinated delivery. The founder
sets the brief, criteria and limits; the existing MoonClaw worker tools handle
specialist work and review in isolated sibling books inside the selected root.
Artifacts and the selected result stay in the objective workspace. Reporting
reconciles automatically once the exact native command has a completed result;
owner acceptance remains explicit and captures the report summary/evidence/source.
Feedback continues the same task through the existing continuation protocol,
not another task store or a new approval/policy engine. Sample delivery,
governance and monitoring surfaces remain available under development navigation.

Stop uses MoonClaw's real session-tree suspension. An acknowledged request is
not sufficient: the root must be suspended and every returned child must be
suspended, archived, deleted or confirmed missing. A planned child that never
became a session has nothing running. Unknown outcomes remain recoverable.
Only explicit Continue/Revise may resume the root; background reconciliation
must not unseal it. Suspension does not settle a paused native command. A
successor for unfinished stopped work first settles it with one stable native
cancel control, preserving retained files and the original outcome history.
Retries reuse that control and successor identity. Completed work is not rerun.

Live testing found that `SELECT revision::text ... ORDER BY revision` sorts by
the textual output alias, returning revision 9 ahead of 10/11. The exact task
lookup now qualifies the numeric table column. Control-only writes merge under
the existing projection lock instead of replacing a concurrently updated result;
their source-event suffix uses the revision actually inserted under that lock.
Keep these properties when changing task persistence.

Public task execution intentionally omits private command bytes. Revision
capture reads C0 from the exact authenticated native claim instead.
The native planner treats `context_path` as a reference, not automatic file
contents. A coordinated successor therefore captures its complete composed
brief as the wire instruction as well as its immutable input file; supplying
only "continue" loses the acceptance/tool guidance even though the file exists.
Worker inspection is ancillary: its failure is visible but cannot erase an otherwise
valid execution readback. Background reads do not monopolize delivery controls.
Stopped work does not poll; coordinated reconciliation avoids redundant native
continuation reads while control is pending and uses a five-second interval.

The old blanket 2 MB response rejection ran after allocation and rejected real
journals; it is removed. Instance/status/credential checks, signed authority,
exact task/command attribution and unknown-outcome handling remain. Native
journal APIs still return full history, so long-running histories have a real
read/parse cost; incremental native readback is a future performance task, not
a reason to invent a second event store here. Brief limits are instructions,
not an enforced provider-spend cap. Cost remains unknown without actual usage.

Worker model selection must omit the optional field to inherit the actual
selected model: the literal `default` is not a provider selector. Failed spawn
IDs remain historical and require fresh IDs on recovery. For Markdown products,
use native file tools rather than requiring shell; the live shell route has no
configured ExecutionSandbox and was not bypassed. Async `mkdir(recursive=true)`
still fails on an existing directory. Delivery creation/write recovery handles
that explicitly and checks feature-owned parents before creating descendants.

No cluster deployment or packaged-app installation is included in this slice.

Validation: 550 frontend JS and 263 native service/gateway tests pass in the
combined working tree. The exact staged snapshot excludes unrelated user work
and passes 549 frontend plus 263 native tests and its release frontend build.
Native release builds, `moon info`, scoped formatting and diff checks pass;
no public-interface changes. User-owned plan/GitHub-import changes are excluded.

The signed native gateway/service and disposable PostgreSQL were used for real
browser work creation, provider-backed execution, Stop and same-task recovery.
At 390px the document width is 382px. The first failed run is retained; numeric
revision readback, confirmed session-tree suspension, stable successor admission
and one actual cancellation of the paused original were observed. Recovery
completion is not qualified by admission alone.

The corrected fresh task is
`OPC-TASK-1795515911752-5adba735-dc18-473f-aecd-0c91a77eee17`.
Its two specialists have actual completed receipts and wrote
`specialist-1/contribution-1.md` and `specialist-2/contribution-2.md` beneath the
task's `.moonproj-deliveries` directory in the local `delivery-smoke-20261124`
book. The coordinator made 102 `wait_workers` calls, continuing after both had completed.
It did not produce an independently reviewed integrated `starter-kit.md`.
The run was stopped; neither a report nor owner acceptance was fabricated.
Consequently this smoke does NOT establish autonomous company delivery, a
sellable finished product, demand or a sale. Automatic reporting and completed
revision selection have unit coverage but still need a successful live final
command to qualify end to end. Next necessary work is native coordinator
progress after terminal worker results, not more policy/approval scaffolding.
Screenshot: `/tmp/moonproj-round3-verified.jpg`. Test services/database were
stopped after verification; fixtures and native worker outputs are retained.

## One objective working home — 2026-11-24

The goal workspace now shows one selected objective, its delegated work and the
selected task's real execution/report controls together. Creating, resuming and
revising linked drafts stays here. New work inherits the objective's criteria
without duplicating the stored acceptance prefix. A sole company project is
selected automatically; multiple projects still require a choice. Creating a
record must refresh the task list as well as opening its canonical detail,
otherwise the new work is saved but invisible in the objective workspace.

Owner acceptance now supplies `objective_result` with an exact delegated task
and saved report. The existing signed task update checks report/task/project/
parent identity and records the selected report and its delivery source on the
objective. The owner need not accept the child record first: that was a redundant
review gate. Acceptance leaves child execution/task states alone and does not
create business effects. A legacy closed key node without this link is labeled
as an ended record, not verified delivery. Request changes prepares an editable
child draft with the original report reference; it does not silently rerun or
overwrite the report.

Dispatch's screen-only restrictions now also allow the objective workspace;
actor, task-selection, source, unknown-outcome and command protections remain.
No approval/policy framework or new task store was introduced. Native commands
for parent-linked work capture integrated-delivery instructions in the existing
prompt, including honest specialist/review attribution and reporting gaps/cost.
This is not proof that a specialist team actually ran. There is still no native
cancel command exposed by this gateway: do not add a cosmetic Stop button or
claim that closing an objective stops its running work.

Duplicate task IDs/status text, exports and setup warnings are removed from the
main path; sources, receipts and optional tools stay in disclosures. The shared
`.inline-form` surface now uses theme variables: the forced dark theme previously
left pale result panels with low-contrast text when the OS theme was light.

Validation: 547 frontend JS tests, 155 native company-service tests and 98 native
gateway tests pass. Release frontend build, `moon info`, scoped formatting and
diff checks pass; no generated public-interface changes.
The isolated commit-only snapshot also passes 546 frontend and 253 native tests
and its release frontend build; it excludes the unrelated GitHub-import test.
Browser smoke used
the real signed gateway/service and disposable PostgreSQL. Goal creation, inline
work creation, report inspection, request-changes preparation, exact-report
objective acceptance and reload were checked. An unrelated/missing report was
rejected. At 390px, document width was 382px and controls remained usable.
The smoke report was deliberately submitted as a manual test report; no provider
or specialist output was fabricated. Screenshot:
`/tmp/moonproj-objectives-round2-verified.jpg`. No autonomous-team production,
customer sale, packaged-app installation or cluster deployment is qualified by
this round. Test services and database are stopped; fixtures are retained.

## Objective-first cleanup — 2026-11-24

Today is the default route; Today, Objectives and Company are the primary
navigation. Objectives reuse company `key_node` records and tasks' native
`parent_task_id`, not a new goal store. Imported key nodes remain visible.
The parent link is accountability only, never an execution dependency.
Owner acceptance is explicit and does not finish child tasks or create financial
effects. Live autonomous multi-agent delivery is not established by this UI.

Fleet no longer mounts sample agents or the sample execution-cockpit package;
Dispatch's reference task board is removed. Plan bulk/reuse tools remain in a
disclosure. Missing workspace no longer blocks saving a brief; execution still
requires actual runtime configuration. Do not weaken signing, reserved business
effects or ambiguous-create reconciliation while simplifying the journey.

Tests that render Products must explicitly select Products; relying on the
old initial page hides navigation regressions and can leak browser fixtures
when assertions fail before cleanup.

`moon fmt` with the current toolchain rewrites legacy syntax in unrelated
packages. Keep its changes scoped; do not ship repository-wide formatter
churn alongside a product change. No public interface change is expected here.

Validation: 543/543 frontend JS tests pass in the combined working tree with a
writable plan fixture directory. The isolated commit-only snapshot passes
542/542; it excludes the unrelated uncommitted GitHub import and its test.
Release frontend build passes, with no generated public-interface changes.
An isolated PostgreSQL 18 instance plus the real native signed gateway/service
was used for browser creation of an objective and parent-linked work, explicit
objective acceptance, and reload. Child state remained pending after the owner
accepted the objective, as declared. A 390px viewport had no horizontal overflow.
The test services/database were stopped. No provider-backed agent production,
new packaged-app installation or cluster deployment was performed in this slice.

## Cluster Mac installation and focused UI pass — 2026-11-24

Installed MoonProj 0.1.0-preview.3, clean main `b422502` plus the focused UI
changes, in `/Applications/MoonProj.app` on 192.168.2.195. Uncommitted plan,
GitHub-import and risk work in the primary checkout was excluded. Both native
services and the Lepusa runtime target macOS 15; strict deep signatures pass.
The gateway's `/ready` returns 200 and the product catalog loads without a DB.
The remote Mac has PostgreSQL 17 tooling, whereas the release documents 18.
No database, role, schema or credentials were created/changed. Database-backed
workflows still require operator configuration; a ready gateway is not proof
of those workflows.

Working style/UI/UX sections now follow MoonTown's guidance with local style
paths. The UI uses `frontend/opc_public/moonproj.svg`, matching the app identity,
instead of a generic overview glyph. Repeated navigation descriptions remain
in accessible names/tooltips. Catalog explanations, long assessment history,
scope assumptions and work groups use disclosures; actual warnings and next
actions remain available. Search/sort controls are omitted for an empty catalog.
Authored product intent, estimates, criteria and evidence were not rewritten.
The recommended-delivery card needs its own single-column grid: the generic
boundary-note flex layout squeezes its estimate and disclosure into narrow
columns. Keep this rule local to `.inventory-next`.

Frontend validation: 536 JS tests pass. The plan evidence helper returns an
empty string unless `MOONPROJ_PLAN_FIXTURE_DIR` is set; full-suite acceptance
requires a dedicated writable fixture directory. Do not replace its file
round-trip assertions or paste large HTML snapshots to conceal that setup.
Run Warren from the module root; an absolute package path from another module
can produce an empty artifact search. After Warren, copy the files listed by
the existing `scripts/build_opc_frontend.sh` into the dist directory before
packaging (the deployment used MoonBit automation for this).

Use the padded macOS SVG with a transparent rasterizer, not Quick Look's white
thumbnail background. The sibling Mooncast `scripts/generate_macos_icon.mbtx`
checks all four corner alpha values at every ICNS size. Installed ICNS hashes
match the verified output. Native app backups, receipts and MoonBit deployment
sources are retained in the remote user's `moonsuite-install-20261124` folder.
The served UI was visually checked through an SSH tunnel; direct remote native
window interaction and real company transactions were not qualified.

Launchpad follow-up: the installed icon hash still matches the transparent
output. Staged/rollback registrations were unregistered from LaunchServices,
canonical `/Applications` copies were re-registered, and the user's Dock was
restarted without a Launchpad reset. Launchpad bookmarks MoonProj's canonical
app; direct visual acceptance still needs a screenshot from that Mac. Other
products retained duplicate Launchpad rows after this non-destructive refresh;
do not imply this procedure guarantees cache cleanup. All backups remain.
