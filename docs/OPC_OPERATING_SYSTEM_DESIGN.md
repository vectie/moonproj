# Top-Down Innovation OPC Operating System Design (MoonProj × MoonBook × MoonClaw × MoonDesk)

- **Status**: Adopted execution design
- **Date**: 2026-11-25
- **First Live Pilot**: Innovation-oriented Research OPC — Doctoral Research on One-Person Companies (`Proposal ✓ → Advisory Board ✓ → Opening Defense ● → Dissertation ○`)

## 1. Problem Statement & First Principles

A founder building an innovation-oriented One-Person Company (OPC) needs to direct a clear organization of AI agents and resources toward **one major goal**, spending **80% of founder attention on the 20% critical decisions** that capture **80% of achievements and rewards** — while both the agents and the company evolve over time.

Across the four Moon Suite repositories, the low-level engines already exist, yet the combined user experience fails to deliver that loop because of four concrete disconnects:

1. **Broken multi-agent completion (`moonclaw`)**: `wait_workers` in `cmd/daemon/mooncode_workers.mbt` returns immediately with a synchronous snapshot instead of performing a bounded wait, includes unfinished historical workers from prior commands when `worker_ids` is omitted, duplicates `metadata` into `output`, and has no post-terminal progression guard — causing coordinators to loop `wait_workers` 100+ times after workers already finished.
2. **Conflicting Book root vs. worker isolation (`moonproj` ↔ `moondesk` ↔ `moonclaw`)**: `native_delivery_workspace` captures the registered MoonBook root so MoonDesk can discover it, while `native_prepare_delivery_workspace` places worker sandboxes *inside* that same MoonBook root (`<book>/.moonproj-deliveries/<task>/specialist-1`). MoonClaw's strict isolation check (`mooncode_worker_roots_overlap`) rejects child books nested inside the parent book, while legacy nested coordinator roots fail MoonDesk's active-library check (`unknown_workspace`).
3. **Missing living Company Charter (Power Structure, Resources, Evolution, Mission Spine)**: MoonProj's live PostgreSQL surface persists a minimal company name and flat `key_node`/`task` records. It has no durable model for:
   - an ordered **Mission & Milestone Spine** with achievement weights (`achieved` / `active` / `upcoming`);
   - a **Standing Agent Org Chart & Power Structure** (Tier 0 Founder → Tier 1 Coordinator → Tier 2 Specialists, explicit granted powers, red-line limits, skill links, and version);
   - a **Company Resource Registry** (registered MoonBooks, corpora, datasets, tools, models);
   - an **Evolution Ledger** recording how agent skills and company rules upgrade after real feedback.
4. **No 80/20 Founder Focus Queue**: The default Workspace gives equal visual weight to every background task and requires manual plumbing rather than separating **Founder 20% Critical Decisions** from **80% Delegated Agent Execution**.

## 2. Single-Responsibility Ownership Across the Four Products

| Product | Owns | Does NOT Own |
| --- | --- | --- |
| **MoonProj** | Company Charter (Mission Spine, Standing Roles & Power Structure, Resource Registry, Evolution Log), 80/20 Founder Decision Queue, formal tasks/deliverables, signed owner acceptance & audit receipts | Agent reasoning loops, raw markdown editing, durable wiki synthesis |
| **MoonBook** | Registered Company Knowledge Book (`book.json`, `SUMMARY.md`, `raw/`, `wiki/`, `skills/<role>/SKILL.md`, `reviews/`), source provenance, durable lessons | Task dispatch, company authority grants |
| **MoonClaw** | Bounded agent execution, coordinator + isolated worker sessions, durable journals, bounded `wait_workers`, terminal receipts | Company acceptance, org authority policy |
| **MoonDesk** | Embedded & standalone human review/edit studio for files inside the registered MoonBook | Company charter state, agent scheduling |

## 3. Root-Cause Fixes

### 3.1 MoonClaw `wait_workers` Fix
- Scope default `wait_workers` (when `worker_ids` is omitted) to the active parent `command_id` (falling back to all records only when `command_id` is empty or no command-scoped workers exist).
- Make `Daemon::mooncode_tool_wait_workers` perform a bounded async poll (default `timeout_ms = 15000`, `poll_interval_ms = 500`, returning immediately as soon as `ready == true`) while keeping `mooncode_wait_workers_projection` pure and fast for unit tests.
- Stop duplicating `metadata.stringify()` into `output`; emit a concise human/model status summary and include an explicit `next_action` instruction when `ready == true`.
- Add a `WarningContext` progression guard in `mooncode_runtime_turn_model_followup_messages` when a `wait_workers` call has already returned `ready == true`, directing the coordinator to synthesize outputs and finish instead of polling again.

### 3.2 MoonProj ↔ MoonDesk ↔ MoonClaw Isolation & Book Discovery Fix
- Keep the coordinator's `book_root` equal to the **registered MoonBook root** (e.g. `<suite>/books/opc-research`), so MoonDesk resolves `book-opc-research` without weakening library boundary checks.
- Place isolated worker sandboxes in a disjoint sibling lane **outside** the registered MoonBook root: `<dirname(book_root)>/.moonproj-workers/<task_id>/<role>` (e.g. `specialist-1`, `specialist-2`, `reviewer`). This satisfies MoonClaw's strict non-overlap invariant while keeping final integrated deliverables inside `<book_root>/.moonproj-deliveries/<task_id>/coordinator/` where MoonDesk can open and edit them directly.
- Allow any valid loopback port (`127.0.0.1`, `localhost`, `[::1]`) in `frontend/opc_public/company_workspace.js` `jobAppURL()` so embedded MoonDesk works cleanly across both installed (`4201`) and local dev (`4199`) hosts without weakening protocol/path/workspace validation.

## 4. Company Charter Persistence Contract (PostgreSQL V4)

Uses the existing `company_aggregate_projection` + `company_record` (`company_command`, `company_audit_event`) tables with zero schema migration:

- `GET /api/company/charter` → latest `company_charter` (`aggregate_id = 'current'`) projection or explicit `persisted: false` empty state.
- `PUT /api/company/charter` → authenticated, actor-signed, idempotent transactional revision write (`Idempotency-Key`, strict field validation, audit event, replay safety).
- Schema (`moonproj.company-charter.v1`):
  - `mission`: `{ title, north_star, active_stage_id }`
  - `stages[]`: `{ id, order, title, status ("achieved"|"active"|"upcoming"), weight_pct, outcome, milestone_task_id }`
  - `roles[]`: `{ id, name, tier (0|1|2), reports_to, kind ("human"|"agent"), mission, powers[], limits[], skill_ref, model, version, status }`
  - `resources[]`: `{ id, name, kind ("moonbook"|"corpus"|"tool"|"runtime"), uri, desk_url, access, owner_role, notes }`
  - `evolution_log[]`: `{ id, date, target ("company"|"agent"), target_id, change, evidence }`
  - `critical_task_ids[]`: explicit Founder 20% critical-path task IDs (in addition to automatic escalation of tasks needing review/approval/recovery).

## 5. Default Workspace UX Contract (`frontend/opc`)

The default `Workspace` keeps its calm top bar, warm MoonDesk app host, and bottom job dock, organized into three top-level workspace tabs:

1. **使命与聚焦 (Mission & 80/20 Focus)** — Mission Spine stepper (`Proposal ✓ → Advisory Board ✓ → Opening Defense ● → Dissertation ○`) with achieved/active weight, a dedicated **20% 关键决策 (Founder Leverage Queue)** separating high-impact founder decisions from background work, and the existing **工作如何汇成交付 (Contribution Flow)** filtered cleanly by stage or all work.
2. **组织与权力 (Org & Power Structure)** — Tiered visual hierarchy (Tier 0 Founder → Tier 1 Coordinator → Tier 2 Specialist Agents) with explicit powers, red-line boundaries, linked `SKILL.md`, version, and **演化记录 (Evolution Log)** with inline add/evolve controls persisted to PostgreSQL.
3. **资源清单 (Resources)** — Categorized registry of registered MoonBooks (direct open in MoonDesk), source corpora, tools, and runtime infrastructure, with inline registration persisted to PostgreSQL.

## 6. Live Pilot Quality Standard (OPC Research Lab)

- Original files in `~/Downloads/Research` are **strictly read-only and never modified**.
- A clean, genuine MoonBook (`opc-research-lab`) is initialized with `book.json`, `SUMMARY.md`, `raw/` (verified mirror of key research sources), `wiki/` (structured thesis overview, opening-defense checklist, empirical claims register), and `skills/` (versioned role playbooks for `research-director`, `corpus-verifier`, `defense-editor`, and `advisory-critic`).
- The pilot PostgreSQL database is seeded with the real 4-stage research mission, standing 5-role org chart, verified resource links, and concrete Opening Defense deliverables — then verified end-to-end across native tests, frontend JS tests, live HTTP gateway/service, and real browser rendering.
