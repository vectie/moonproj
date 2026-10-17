# Projects plan workbench

`/projects` in the default OPC interface now reads actual company projects and
opens an editable, planning-only workbench. The former sample portfolio is no
longer displayed as company state. The existing Products, Today, company setup,
proposal, dispatch, acceptance and finance flows are unchanged.

## Use

1. Sign in through the existing MoonProj native company gateway and select
   **Projects → Read company projects**. Choose the company project returned by
   the service. If it is absent, establish it through Company setup first.
2. Enter scope/source notes, budget limit and contingency, and your name.
   Currency is an uppercase three-letter code. Amount entry uses a fixed
   two-decimal scale; results and exports label the underlying minor units.
3. Add named owners and roles, or [import and edit an owner roster](OWNER_ROSTER_TABLE.md)
   by stable ID with a CSV/TSV preview. Then add milestone dates, acceptance criteria and required
   evidence (one per line), or [import a new milestone roadmap](MILESTONE_ROADMAP_IMPORT.md)
   with source IDs that your later task CSV can reference. Use the [owner planning brief](OWNER_PLANNING_BRIEF.md)
   to inspect one owner's assigned work and cross-owner handoffs, and download
   the current draft context. Add tasks, their owners, milestone, costs and
   dependencies. Move tasks up/down so predecessors come first. Add risk rows
   and mitigations as needed. To bring an existing spreadsheet risk register into
   the plan, [preview CSV/TSV risk additions and updates](RISK_REGISTER_TABLE.md),
   inspect stable IDs and linked tasks, apply locally, and download the editable
   register again. Technical row and request identities are generated.
   When a project term changes, [preview and replace authored plan text](PLAN_TEXT_REPLACEMENT.md)
   across selected notes, task titles, milestone descriptions and risk prose,
   keeping all stable identities and links intact.
   Use the [task finder](TASK_FINDER.md) to search by name or ID, combine exact
   owner/milestone filters, focus a matching task’s existing edit form, and export
   only the current matches without changing the rest of the draft.
   To refine a broad task, [break it into sequential steps](TASK_BREAKDOWN.md),
   allocate its exact cost, and preview reconnected follower dependencies and
   expanded risk links before applying the local edit.
   You can also [paste a local CSV/TSV backlog](TASK_TABLE_IMPORT.md), append its
   tasks with stable source IDs, edit them here, and download an editable task CSV.
   To reuse an action list from a brief or repository issue,
   [preview a Markdown checklist](MARKDOWN_CHECKLIST_IMPORT.md) and append its
   unchecked tasks with source line mapping, heading/nested context and chosen
   owner/milestone. Checked items can explicitly be replanned without recording
   completion; the original Markdown stays in scope notes.
   To turn a planned row into actionable work, [preview it as a Dispatch draft](PLAN_TASK_HANDOFF.md).
   Its source snapshot, scope, prerequisites, risks and milestone context carry
   over into an independent editable brief; formal creation remains explicit.
   Bring spreadsheet edits back through [existing-task update previews](TASK_TABLE_UPDATES.md)
   to inspect and apply changed fields without recreating task identities.
   When staffing changes, [reassign an owner’s complete draft allocation](OWNER_REASSIGNMENT.md)
   with an affected-row preview across tasks, milestones and risks.
   Use the [dependency explorer](DEPENDENCY_EXPLORER.md) to inspect parallel-ready
   waves, trace downstream impact, and automatically order tasks by prerequisites.
   Download a [milestone calendar](MILESTONE_CALENDAR.md) from the current draft
   to carry its explicit target dates and task context into an `.ics` calendar.
   This does not schedule tasks or change the plan.
   To replan an existing board, [preview a local Trello JSON export](TRELLO_BOARD_IMPORT.md)
   with card descriptions, list context and checklist detail retained in source
   notes. Review it through the same explicit template replacement or phase append.
   To reuse the entire plan in another project, download and preview a
   [complete editable plan template](PLAN_TEMPLATES.md), map your owner slot,
   and replace the destination draft with a freshly identified copy. Dates,
   amount strings, requirements and dependencies retain their authored values.
   To compose a reusable phase into work already in progress, use
   [preview-and-append phase](PLAN_PHASE_APPEND.md) instead of replacement.
   It carries the phase's complete milestone/acceptance/risk context and keeps
   your current draft rows, owner identity, scope and budget.
   For spreadsheet roadmap changes, [edit existing milestone CSV/TSV tables](MILESTONE_TABLE_UPDATES.md)
   by stable ID, including independently chosen dates, owners and multiline
   acceptance/evidence requirements, while keeping task links intact.
   When the start or delivery target changes, [rebase the milestone dates](MILESTONE_RESCHEDULING.md)
   from one new anchor date, preview every change, and apply them together while
   preserving the existing calendar-day spacing.
   Inspect the [draft budget breakdown](BUDGET_BREAKDOWN.md) to see exact cost
   allocation by owner and milestone, incomplete costs and remaining budget,
   then download the current report without preparing or saving a native plan.
4. Choose **Native prepare and save plan**. The native operation validates the
   complete request, then saves immutable source and plan files. A success is
   displayed only after reopening and recomputing the exact saved result.
5. Inspect dependency order, milestones, risks, acceptance requirements and
   budget. Download the readable `.txt` or exact typed native artifact `.json`.
   Reopen a saved version from actor/project-scoped history after reload.
6. Beside saved history, choose **Compare two saved plans (read only)** and
   select **Before** and **After**. This reads each exact immutable version
   through the existing authenticated GET route. Expand a change for complete
   before/after text, swap the two versions, retry a failed read, close the panel,
   or download its complete readable report. Current editing can continue.

Comparison is independent of the editor: it never opens a historical version
into the draft, calls prepare, or writes browser storage. Its own actor,
project, epoch, selected pair and generation fence late responses, including
after cancellation, swapping, reselecting a pair and refreshing projects.
Changes, errors and report export preserve the editor's draft bytes, prepared
result, revision and phase. A browser reload closes the ephemeral comparison;
the existing local draft recovery remains unchanged.

Rows match stable owner/task/milestone/risk IDs. A renamed label is a field
change; a different ID is a removal plus addition. Existing rows appear in
Before order, followed by additions in After order within each category.
Dependencies and risk task references compare as ID sets, with task execution
order shown separately. Scope, names/roles, owner and milestone assignments,
costs, dates, acceptance criteria, required evidence and risk fields retain
their full before/after text. Version/digest/timestamp/source provenance has
its own header and does not inflate substantive changes.

Budget limit, planned total, contingency, unallocated balance and per-task cost
come from saved native artifact minor units. Same-currency non-negative Int64
values subtract exactly, including beyond JavaScript's safe integer range.
Different currencies, missing values, invalid amounts and out-of-range values
show an unavailable delta. There is no float arithmetic, inferred zero, FX
conversion or draft-decimal calculation in a comparison.

Editing invalidates the prepared preview/download controls without discarding
the edit. Local draft recovery is labeled as browser-local and scoped by actor
and project. Failed requests retain the same request identity for retry. A
project switch, actor change or further edit prevents an older response from
replacing the current work. Opening a historical version explicitly replaces
the current browser draft; the immutable saved version itself is unchanged.

## Host and storage boundary

There is no new HTTP service, agent runtime, provider call or separate plan
executable. The existing authenticated `cmd/postgres_company_gateway` handles:

- `GET /api/company/projects/:project/prepared-plans` (newest 100 saved versions,
  ordered by immutable file modification time, with total count and truncation)
- `POST /api/company/projects/:project/prepared-plans` (prepare and save)
- `GET /api/company/projects/:project/prepared-plans/:version` (exact reopen)

Every operation re-reads the exact project from the existing signed company
service. The request project must match the route. Its observed business-unit
identity scopes the native proposal; it is not a legal-registration assertion.
The logged-in actor must be a declared owner and is always the preparer.

The native gateway calls the existing
`moonproj/project.plan.prepare@0.1.0` implementation in-process. Its original
owners, tasks, dependency, milestone, date, evidence, fixed-point budget, risk
and acceptance-gate checks remain authoritative. Validation failures name useful
fields/rows. No task is created or started, even when a valid plan is saved.

Storage reuses the existing adapter's immutable, synced workspace file helpers:

```
<existing --moonsuite-workspace-root>/moonproj/
  .moonsuite/products/moonproj/project-plans/
    <sha256 actor>/<sha256 project>/<generated version>/
      source.json
      plan.json
```

`source.json` preserves the actual user-authored draft and the service-observed
project identity. `plan.json` binds that source digest, typed request, exact
native result, exported bytes and readable projection. Reopen verifies the
source bytes, actor/project/version, request, deterministic native result and
download digest. It does not substitute a recalculated newer plan. A repeat
with changed data under the same version fails closed. Interrupted writes can
be retried with the original draft. Storage errors are unconfirmed outcomes,
not claims that no write happened.

The operator must already have a company service/database, gateway session and
a writable existing MoonProj workspace at the configured location. Missing
service, workspace, binary or browser storage remains visible. The workbench
does not provision a database, credentials, legal principal or runtime, and
does not fall back to samples. No standalone adapter executable is needed;
an unavailable gateway is an unavailable feature, not permission for a fallback.

## Reuse part of a draft

The **Extract reusable phase** panel selects tasks or a milestone, shows all
automatically included prerequisites, and downloads standard plan-template JSON.
It preserves the current draft and prepared result. Partial milestone requirements,
omitted cross-scope risks, and excluded source-wide scope/budget are explicit.
See [Phase extraction](PHASE_EXTRACTION.md) for selection, context, reuse and state
rules. Existing whole-template replacement and append accept the result unchanged.

## Consolidate overlapping task rows

[Consolidate tasks](TASK_CONSOLIDATION.md) combines selected same-owner,
same-milestone tasks into one chosen surviving ID. Preview exact summed cost,
rewritten dependencies and risk links, and the resulting prerequisite-first order
before saving the local edit. Existing task CSV output and native prepare/save
use the consolidated draft. Saved versions remain unchanged.

## Re-review a revised draft

The [offline revision comparison](PLAN_REVIEW_REVISION.md) lets a reviewer inspect
previous observations next to explicitly paired current rows, retain added/removed
row labels, and save/reopen comparison context while making fresh review decisions.
It accounts for positional template IDs and never transfers old decisions.

## Authority ceiling

The result remains `pending_review`, `accepted=false`, `review_required=true`
and `claim_ceiling=digital-artifact`. Spending, accounting, payment, contracts
and work-execution effects remain false. Plans are proposals; named-human
review and any later business authorization are separate work. Exporting or
opening a plan is not acceptance. There is deliberately no bulk task conversion.

## Verification

The Round 19 verification script compiles/checks the affected native packages,
runs the entire OPC frontend regression suite, captures the production UI
prepare request, sends it through the production authenticated HTTP gateway,
calls real native prepare/storage/reopen, then feeds the exact saved response
back through the UI reducer/render/download commands. Download byte equality
and dependency snapshots are asserted. The company service in this isolated
test is explicitly a synthetic read-only projection fixture. This is not
production-database or production-identity acceptance.

Negative coverage includes unknown references, duplicate identities and
dependencies, self/forward dependencies, invalid calendar dates, invalid and
over-budget money, duplicate/empty criteria, actor/project isolation, corrupted
saved source/artifact, missing workspace, repeat clicks, edit invalidation,
project switching, late replies, local-draft reload and unavailable gateway.

The Round 26 verifier extends that actual UI → gateway → native saved-response
crossing with two immutable versions, then feeds both through the compiled
read-only comparison reducer, rendered disclosures and report download. It
checks exact report byte equality, stable-ID removal/addition, label changes,
set-only dependency changes versus execution order, long-field preservation,
native Int64 boundaries, unavailable money, currencies, stale pair and scope
replies, cancellation/reload, concurrent editing, and unchanged editor/local
storage. Tests and the UI release build run against private pinned dependencies.
