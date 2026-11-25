# MoonProj project handoff

## Pure-UI audit fixes: MoonGate resource link, Chinese embedded locale & menu/favicon polish — 2026-11-25

- Added **"在 MoonGate 配置模型"** action (`http://127.0.0.1:15721/ui/rabbita#providers`, `data-open-external="moongate"`) in `资源清单 → 算力与模型` (`frontend/opc/company_resources_view.mbt`).
- Appended `locale=zh-Hans` when mounting embedded MoonDesk iframes in `frontend/opc_public/company_workspace.js` (eliminating the bilingual Chinese/English seam), auto-closed open `.topbar details[open]` dropdowns on action click, handled `moonsuite:navigate` from embedded MoonDesk to prevent iframe nesting, and added inline SVG favicon in `frontend/opc_public/index.html` (0 `/favicon.ico` 404s).
- Verified live: 587/587 `frontend/opc` JS tests + `company_workspace.test.mjs` (4/4) + `dist/opc` build passed; installed into `/Applications/MoonProj.app`, strictly signed, and verified live in Chrome.

## Permanent desktop-service orphan cleanup & MoonGate handoff — 2026-11-25

Fixed `MoonProj.app` refusing to reopen after quitting:
- **Root cause**: When `MoonProj.app` quit, `moonproj-desktop-service` (`scripts/moonproj_desktop_service.sh`) left its child processes `moonproj-company-service` (`:4174`) and `moonproj-company-gateway` (`:4173`) alive. On the next launch, Lepusa aborted startup with `macOS service start refused for main: readiness endpoint is already active; close the other app instance`.
- **Root fix**:
  - Updated `scripts/moonproj_desktop_service.sh` to record desktop-owned backend PIDs in `$APP_DATA_DIR/desktop-service.pids`, reclaim stale MoonProj backend listeners on startup, and run a parent/GUI-exit watcher that directly terminates `$gateway_pid`, `$service_pid`, and `$$` (avoiding the macOS `/bin/sh` deferred-trap behavior while blocked in `wait`) the instant `MoonProj.app` exits.
  - Added a loopback-validated `message` listener (`moonsuite:open-url` for `127.0.0.1:4201`/`15721`) in `frontend/opc_public/company_workspace.js` so embedded MoonDesk's `"Open MoonGate"` action opens cleanly via Lepusa `opener.openUrl`.
- **Verification**: Installed into `/Applications/MoonProj.app`, strictly ad-hoc signed, and verified two full Launch → Quit → zero `:4173/:4174` listeners → Relaunch cycles cleanly (`PID 52153` → quit → free → `PID 52273` + `/ready` HTTP 200).

## Desktop OS spatial model, standing Dock agents & solid notices — 2026-11-25

Refined MoonProj's human spatial model and eliminated overlapping/transparent warnings:
- **Root causes**:
  - `.notice` in dark mode (`frontend/opc_public/styles.css`) used transparent `var(--accent-soft)` (`rgba(139,124,246,.13)`) while `.workspace-main > .notice` was positioned at `inset: 8px 20px auto`, bleeding over and obscuring the Mission Spine.
  - Clicking `组织与权力` or `资源清单` previously unmounted the entire Desktop/Flow surface, making navigation feel like disorienting page teleports rather than staying anchored on the company desktop, and standing AI agents were not visible in the bottom Dock.
- **Fixes**:
  - Made `.notice`, `.charter-inline-alert`, and `.founder-focus` 100% solid opaque surfaces; relocated `.workspace-main > .notice` to a non-overlapping bottom-right floating toast (`bottom: 112px`, above the Dock).
  - Kept the Desktop canvas (`.company-flow` with Mission Horizon + live SVG Projects Flow) continuously mounted in the background and rendered `组织与权力`, `资源清单`, and clicked Dock agents inside solid opaque floating Overlay Sheets (`.desktop-sheet`, Escape / backdrop-click to dismiss).
  - Upgraded the bottom Dock (`.job-dock`) into a unified macOS-style bar: **桌面** home + **Project/Task apps** + divider + **Standing AI Agents** (from Company Charter with tier badges and live status dots; clicking opens a focused Agent Inspector Sheet over the desktop).
  - Added a direct `← 返回公司桌面` button in `.topbar` whenever navigating to secondary routes.
- **Verification**: `frontend/opc` JS tests (587/587), `company_workspace.test.mjs` (4/4), and `company_no_python_runtime_gate.sh` passed. Built `dist/opc`, installed into `/Applications/MoonProj.app/Contents/Resources/public`, strictly ad-hoc signed, and verified live on `http://127.0.0.1:4173`.

## MoonDesk-in-MoonProj bridge & embedded opening — 2026-11-25

Fixed MoonDesk failing to open inside MoonProj:
- **Root causes**: (1) When `MoonDesk.app` was not already running, `127.0.0.1:4201` refused connections while `company_workspace.js` blindly cached a dead `ERR_CONNECTION_REFUSED` iframe in `state.frames`; (2) `"在 MoonDesk 打开"` links in `资源清单` and `"独立打开"` in `.job-app-panes` used `target="_blank"`, which macOS WKWebView (Lepusa) drops.
- **Fixes**:
  - Added authenticated loopback-only endpoints `GET /api/company/moondesk/status` and `POST /api/company/moondesk/ensure` in `cmd/postgres_company_gateway/moondesk_bridge.mbt` (+ `moondesk_bridge_wbtest.mbt`) that probe `http://127.0.0.1:4201/` and, in desktop mode, background-launch `/Applications/MoonDesk.app` (`open -g -a`) and poll until ready.
  - Updated `frontend/opc_public/company_workspace.js` to verify/wake MoonDesk before caching any iframe (with clear connecting + offline recovery UI), and intercept `"独立打开"` via `window.lepusa.invoke('opener.openUrl', ...)`.
  - Added `WorkspaceAction(OpenResource(title, url))` in `frontend/opc/company_workspace.mbt`, `company_workspace_view.mbt`, and `company_resources_view.mbt` so `"在 MoonDesk 打开"` in `资源清单` opens directly inside MoonProj's embedded `.job-app-window`.
- **Verification**: `cmd/postgres_company_gateway` 116/116 passed, `frontend/opc` charter/workspace tests passed, `company_workspace.test.mjs` 4/4 passed. Installed into `/Applications/MoonProj.app`, strictly ad-hoc signed, and verified cold auto-wake (`4201` down → `POST /api/company/moondesk/ensure` returned `{"reachable":true,"started":true}` → HTTP 200 on `opc-doctoral-research` Wiki).

## Modular OPC frontend, UI/UX cleanup, and focus-guiding motion — 2026-11-25

Modularized the oversized frontend files and polished the Workspace & Charter UI/UX:

- **Frontend modularization**:
  - Split `frontend/opc/main.mbt` (4,299 lines → 127 lines) into `app_model.mbt` (479), `app_routes.mbt` (331), `app_update.mbt` (1,383), `app_shell_view.mbt` (366), `app_legacy_ops_views.mbt` (860), and `app_legacy_finance_views.mbt` (753).
  - Split `frontend/opc/company_charter.mbt` (1,468 lines) into `company_charter_types.mbt` (393), `company_charter_codec.mbt` (411), and `company_charter_update.mbt` (664).
  - Split `frontend/opc/company_charter_view.mbt` (1,025 lines) into `company_charter_shared_view.mbt`, `company_mission_view.mbt`, `company_org_view.mbt`, and `company_resources_view.mbt`.
  - Split `frontend/opc_public/company_workspace.css` into three focused layers: `company_workspace.css` (shell, flow board, dock, app window), `company_charter.css` (Mission Spine, 80/20 Founder Focus, Org & Resources), and `workspace_motion.css` (GPU-composited motion with full `prefers-reduced-motion` and `[data-motion="paused"]` safety), wired into `index.html` and `scripts/build_opc_frontend.sh`.
- **UI/UX & functional fixes**:
  - Fixed stage-click filtering in `company_workspace_view.mbt`: selecting a stage whose `milestone_task_id` points to a regular task (e.g. `OPC-DOCTORAL-PRESENTATION`) now retains its parent goal (`OPC-DOCTORAL-GOAL`) so SVG contribution wires remain connected and spotlighted instead of orphaning the task under `"其他工作"`, and adds a direct `"打开此阶段材料"` action in `.mission-stage-detail`.
  - Cleaned visual hierarchy on `使命与聚焦`: single `<h1>` on the Mission Spine, proportional segmented `.mission-weight-rail`, concise single-line flow legend, aligned inline `已入 20%` / `标为 20%` pill toggle on `.flow-job-row`, and icon+label segmented workspace tabs.
  - Humanized `组织与权力` & `资源清单`: resolved `reports_to` and `owner_role` IDs to human-readable role names (`charter_role_display_name`), localized standard power tokens (`charter_power_label`) as compact chips while preserving user-authored text verbatim, and tucked technical paths/models into compact card footers.
- **Focus-guiding animation layer**:
  - Sliding GPU-composited active tab indicator (`syncTabIndicator` in `company_workspace.js`), calm breathing beacon on the active milestone (`opc-stage-beacon`), subtle sheen on the active proportional weight rail segment (`opc-rail-sheen`), 80/20 focus beacon & elevation cues, choreographed tab/form entrance (`opc-surface-enter`, `opc-panel-reveal`), and interactive SVG contribution wire highlighting on hover/focus/stage-spotlight while dimming unrelated wires.

Validation:
- `frontend/opc` JS tests: **587/587 passed** (added test covering task-bound stage parent-goal retention, `"打开此阶段材料"`, role display-name resolution, and power localization).
- `node --test frontend/opc_public/company_workspace.test.mjs`: **4/4 passed** (verifies reduced-motion & manual pause in both `company_workspace.css` and `workspace_motion.css`).
- `scripts/company_no_python_runtime_gate.sh`: passed.
- Warren release build (`dist/opc`) installed into `/Applications/MoonProj.app/Contents/Resources/public`, ad-hoc signed (`codesign --verify --deep --strict` valid), and verified live on `http://127.0.0.1:4173` (all new CSS/JS assets return HTTP 200).

## Top-down OPC Operating System, coordinator wait fix, and Research Lab pilot — 2026-11-25

Implemented the top-down NeoLab-style OPC operating model across MoonProj, MoonClaw, and the registered `opc-doctoral-research` MoonBook, documented in `docs/OPC_OPERATING_SYSTEM_DESIGN.md`:

- **Persisted Company Charter (`GET`/`PUT /api/company/charter`)**: Added `cmd/postgres_company_service/company_charter.mbt` (+ `company_charter_wbtest.mbt`) using the existing PostgreSQL V4 `company_aggregate_projection` + `company_record` (`company_command`, `company_audit_event`) atomic locking/idempotency/recovery pattern (zero schema migration), and allow-listed `PUT /api/company/charter` in `cmd/postgres_company_gateway/main.mbt` (+ `company_charter_wbtest.mbt`). Models Mission + weighted Milestone Spine (`achieved`/`active`/`upcoming`), 3-tier Standing Org & Power Structure (`powers`, `limits`, `skill_ref`, `version`), Resource Registry (`moonbook`/`corpus`/`tool`/`runtime` with direct `desk_url`), Evolution Log, and Founder `critical_task_ids`.
- **Workspace 80/20 Command Center (`frontend/opc`)**: Added `company_charter.mbt`, `company_charter_view.mbt`, and `company_charter_wbtest.mbt`, extending `Workspace` with three tabs (`使命与聚焦`, `组织与权力`, `资源清单`) while preserving `.flow-board`, `.flow-wires`, `.job-dock`, and warm MoonDesk `.job-app-host` iframes. `jobAppURL()` in `frontend/opc_public/company_workspace.js` now accepts both installed (`4201`) and local dev (`4199`) loopback MoonDesk ports while still rejecting arbitrary ports.
- **Root-cause fix for worker isolation vs. MoonDesk Book root**: Previously, `native_delivery_workspace` captured the registered MoonBook root while `cmd/postgres_company_service/delivery_work.mbt` (`plan_task_execution_workspace`) still expected `<root>/.moonproj-deliveries/<id>/coordinator` (causing 422 mismatches on reserve) AND `native_prepare_delivery_workspace` created worker books inside `<root>/` (rejected by MoonClaw's `mooncode_worker_roots_overlap`). Fixed both: service and gateway now agree on the registered MoonBook root, final integrated coordinator outputs stay under `<root>/.moonproj-deliveries/<task>/coordinator/`, and isolated worker books live in a disjoint sibling lane `<dirname(root)>/.moonproj-workers/<task>/{specialist-1,specialist-2,reviewer}`.
- **Root-cause fix for MoonClaw `wait_workers` spin loop (`../moonclaw`)**: `Daemon::mooncode_tool_wait_workers` previously returned synchronously in <1ms, selected unfinished historical workers from prior commands when `worker_ids` was omitted, duplicated `metadata` into `output`, and gave no post-terminal progression guard. Fixed in `../moonclaw/cmd/daemon/mooncode_workers.mbt`, `mooncode_tools.mbt`, `mooncode_runtime_model_planner.mbt`, and `mooncode_workers_wbtest.mbt`: command-scoped default wait, bounded async polling (`timeout_ms` default 15s, `poll_interval_ms` 500ms, early exit on `ready=true`), compact summary + `next_action`, and an escalating `warning.worker_wait_complete` follow-up guard.
- **Live OPC Research Lab pilot**: Added 4 standing role playbooks (`skills/{research-director,corpus-verifier,defense-editor,advisory-critic}/SKILL.md`) and `wiki/00-opc-lab-charter.md` inside the registered `opc-doctoral-research` MoonBook (verified all 445 files in `raw/originals/` pass `原件校验.sha256`; `~/Downloads/Research` untouched). Seeded revision 1 of `company_charter` in the local app PostgreSQL database bound to the real tasks (`OPC-DOCTORAL-PROPOSAL`, `OPC-DOCTORAL-PRESENTATION`, `OPC-DOCTORAL-DISSERTATION`) with Stage 3 Opening Defense active and marked in `critical_task_ids`. Added reusable fixture `scripts/fixtures/opc_research_charter.json` and `scripts/seed_opc_research_charter.sh`.

Pitfalls & toolchain notes (upgraded 2026-11-25):
- Upgraded local MoonBit toolchain from `0.1.20260920` to `0.1.20261119 (738607b 2026-11-19)` and installed Warren `0.4.5` (`~/.moon/bin/warren`).
- `moon.mod` path-override syntax is not supported in the DSL; resolving local `vectie/moonlib` (which fixes `[4015]` impl-method errors present in published `0.1.23`) uses a `moon.work` file via `MOON_WORK=/path/to/moon.work` listing `["/Volumes/Vectie/Codespace/moonlib", "<repo>"]`.
- Warren `0.4.5` requires `--browser-entry frontend/opc` (positional arg now expects `.mbtx`) and a child `--dist` path under `-C "$ROOT"`; updated `scripts/build_opc_frontend.sh` accordingly.
- `moon 0.1.20261119` + `async@0.22.x` + `rabbita@0.17.0` breaking changes migrated across MoonProj (`cmd/postgres_company_service`, `cmd/postgres_company_gateway`, `cmd/moonflow_project_plan_adapter`, `integration/moonflow_adapter`, `operations/task_evidence`, `product/plan_workbench`, `frontend/opc`) and MoonClaw (`cmd/daemon`, `internal/*`, `plugin/*`, `tools/*`, `channels/*`, `cmd/main/*`, `gateway/*`): removed `try?`, removed implicit trait impl methods (`.to_json()`, etc.), `@http.Headers` (`Map[@http.CaseInsensitiveString, String]`), `protect_from_cancel` without `resume_on_cancel`, removed `virtual(implement: "moonbitlang/core/abort")`, and `@rabbita.create_state_with_init` + mock DOM test helper (`frontend/opc/test_rabbita_helpers_wbtest.mbt`).
- Root-cause fix in MoonClaw `cmd/daemon/mooncode_session_journal.mbt`: `mooncode_session_journal_transaction` previously called `file.write(...)` after reading on an `append=false` handle, which overwrote offset 0 under `async@0.22.4` and caused `line 1: journal sequence gap`. Changed to `file.write_at(..., position=state.committed_size)` matching `mooncode_append_session_journal_once_locked`.

Validation (all run on `moon 0.1.20261119` + Warren `0.4.5`):
- `scripts/company_no_python_runtime_gate.sh`: passed.
- `node --test frontend/opc_public/company_workspace.test.mjs`: 4/4 passed.
- MoonProj native tests (`MOON_WORK=/tmp/moonproj-work/moon.work`):
  - `cmd/postgres_company_service`: **163/163 passed** (incl. 5/5 `company_charter_wbtest.mbt`, 2/2 `delivery_work_wbtest.mbt`).
  - `integration/moonflow_adapter`: **26/26 passed**.
  - `cmd/postgres_company_gateway`: **115/115 passed** (incl. 8/8 `native_delivery_wbtest.mbt`, 2/2 `company_charter_wbtest.mbt`).
- MoonProj frontend JS tests (`MOONPROJ_PLAN_FIXTURE_DIR=/tmp/moonproj-plan-fixtures`): **586/586 passed** (incl. 6/6 `company_charter_wbtest.mbt`, 10/10 `company_workspace_wbtest.mbt`).
- MoonProj repo-wide `moon info`: **182 tasks, 0 errors** (`.mbti` diffs contain only `0.1.20261119` syntax updates `#derive`, `Int32`, `@json.Json`, zero API changes).
- MoonClaw native tests (`MOON_WORK=/tmp/moonclaw-work/moon.work`): **72/72 passed** across `mooncode_workers_wbtest.mbt` (7/7), `mooncode_worker_results_wbtest.mbt` (7/7), `mooncode_session_journal_sequence_wbtest.mbt` (17/17), `mooncode_runtime_approvals_wbtest.mbt` (10/10), and `mooncode_session_journal_streaming_wbtest.mbt` (31/31); `moon build --target native --release cmd/main` succeeded with **0 errors**.
- Release builds & `/Applications/MoonProj.app` install:
  - Built native release `postgres_company_service.exe` (7.4M), `postgres_company_gateway.exe` (3.2M), and `dist/opc` (`index.js` 2.8M + updated CSS/JS).
  - Backed up prior app resources to `/tmp/moonproj-app-backup-20261125/`, installed updated binaries + `public/` into `/Applications/MoonProj.app`, re-signed ad-hoc (`codesign --verify --deep --strict` valid on disk), and restarted `moonproj-desktop-service` on ports `4173`/`4174`.
  - Live HTTP verification: `GET /ready` returned `200 {"ready":true,"scope":"gateway"}`; unauthenticated `GET /api/company/charter` returned `401`; desktop-authenticated `GET /api/company/charter` returned `200` with persisted revision 1 of `OPC 创新研究一人公司（OPC Research Lab）` (4 stages, 5 roles, 5 resources, 2 evolution entries, `critical_task_ids: ["OPC-DOCTORAL-PRESENTATION"]`); `GET /api/company/projects` returned `opc-doctoral-research` (4 tasks); live `index.js` and `company_workspace.css` serve the new 3-tab Workspace UI.
  - All 445 files in `opc-doctoral-research/raw/originals/` re-verified OK against `原件校验.sha256` (`~/Downloads/Research` untouched).
- Not yet qualified in this turn: live Chrome DevTools visual inspection (Chrome remote debugging was not enabled on this machine, `DevToolsActivePort` ENOENT) and a live provider-backed multi-agent execution run.

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

## Three-stage MoonBook preparation (2026-11-24)

New coordinated executions must capture the selected, registered MoonBook root,
not its hidden coordinator subfolder. Keep worker isolation and final output
folders per task, but retain that registered root for Desk handoff identity.
Imported source links must be visible before an execution exists; importing
documents is neither worker evidence nor owner acceptance. Unknown task dates
remain blank rather than inventing a deadline during project setup.

The macOS launcher detects keg-only Homebrew psql and an explicitly provisioned
app-local PostgreSQL directory. It does not initialize or adopt a system/Homebrew
cluster. The cluster Mac's dedicated database uses a private Unix socket and a
user LaunchAgent with LC_ALL=C (PostgreSQL otherwise failed at startup there).
Reuse an existing Desk pairing only when exactly one configuration exists.
Native binaries installed on macOS 15 must be built with deployment target 15;
the local default produced incompatible macOS 26 binaries.

MoonDesk now resolves Book-relative document/figure references against their
source file and opens direct code-file links after the exact Book is known.
Long Markdown live previews wait for a brief typing pause. A >400k-character
HTTP preview/save regression protects complete dissertation text. CUA string
readback itself truncates at 200k characters with `[Truncated]`: never feed a
large extracted editor value back into fill(). Verify lengths/digests and edit
in place instead. Originals and working copies were restored byte-for-byte
after the smoke edits. UI resources were tested against installed app services
through a cluster tunnel; direct remote native-window visual QA remains unverified.

## Docked company workspace (2026-11-24)

The default route is now Workspace: a full-height job-to-goal contribution map,
with one dock app per real regular task. Goal nodes are deliverables, not agents;
ordering does not invent execution dependencies. Existing explicit routes remain
available under Tools. Each focused job has MoonDesk materials and the existing
team/delivery controls; opening or minimizing an app only reads/selects work.

The stable app host lazily retains local MoonDesk iframes across job, pane,
overview and legacy-route changes. Actor changes clear the frame cache. External
sources remain explicit links, not arbitrary embedded apps. These are in-product
job apps, not separate macOS applications or a general-purpose window manager.
Unsaved editor state survives in-session switching, not a browser reload/quit.

The presentation adapter draws contribution wires and short app-opening motion.
Only an observed new exact goal/report receipt animates a handoff; initial reads
do not replay delivery. Only actual running work pulses. Pausing and reduced-motion
preferences retain readable static relationships. Completed execution is labeled
for review, never accepted automatically. Active work quietly refreshes the real
task collection; the selected native execution keeps its existing polling chain.
Newer collection revisions take precedence over older selected snapshots. Failed
refreshes preserve scoped last-read jobs with an explicit warning.

Installed services on the cluster Mac were tested through a local tunnel using
the three real dissertation stages. Keyboard editing, an unsaved temporary index
draft, switching jobs, overview, Guide and status refresh preserved the draft;
the marker was removed and editing cancelled without saving. Team/delivery showed
the exact selected job, unstarted reviewers and no fabricated output. The dock,
375px flow layout and motion pause/resume were checked. Browser automation could
read embedded controls but could not pointer-click them; keyboard traversal and
editing worked. Native remote-window pointer QA and an actual running/accepted
handoff remain unqualified. No paid agent execution was started for this UI pass.

## Windowed Mac startup repair (2026-11-25)

The native app must open as an ordinary resizable window. The flow/dock occupy
the window content, not the macOS screen. Default content size is now 1040x680
with an explicit native title bar; do not add automatic fullscreen/maximize.

On the cluster Mac, the apparent crash reproduced as a normal launcher exit
with `readiness endpoint is already active; close the other app instance`.
An orphaned test-only `moonproj-desktop-service` and its two children owned
4173/4174 while no native MoonProj app was running. The exact processes were
checked and stopped; the dedicated persistent PostgreSQL and Book files were
not removed or changed. Do not bypass Lepusa's refusal to adopt an unrelated
server, kill arbitrary port owners, or leave manually launched smoke servers
running when handing off the packaged app.

The installed runtime manifest was backed up outside the app, resized, signed
and verified. LaunchServices then started the native MoonProj process and its
own service/gateway; readiness returns 200 and repeated LaunchServices opening
keeps the same instance. No new crash report appeared. Four focused config/
workspace runtime tests pass. No MoonBit production source or execution authority
changed. Direct remote window controls are unavailable through the current
viewer; red-button close/relaunch and visual window acceptance require the
user's confirmation. Signal termination was not a substitute for that UI check.
