# Delegate a deliverable

The existing portfolio operator page now has **Delegate a deliverable**, below
its product portfolio. This is a bounded digital-artifact workflow. It does not
create formal company tasks, authenticated assignments, customer acceptance,
financial approval, or a second agent runtime.

## Start with an owned plan

1. Use Projects to author a plan, optionally break broad tasks into steps, and
   save a native plan artifact. Choose **Load saved native plan** (UTF-8 JSON,
   up to 1 MiB), or paste its exact JSON into the deliverable panel.
2. State the desired output and approved workspace parent/model selector.
3. Inspect **Task-by-task acceptance**. Each form identifies the unique task ID,
   accountable owner, prerequisites, and original task/milestone/project gates.
   Duplicate task names remain separate forms. For inherited milestone/project
   gates, enter explicit task criteria and required evidence, one item per line;
   inherited gates are context and never silently become task acceptance.
   Task-scoped native gates are prefilled and can be edited.
4. Choose **Preview complete task board** (or **Preview complete source/task
   mapping** when attaching local evidence). Inspect every task's criteria,
   evidence and prerequisites, plus the outcome, workspace, model and exact graph.
   This validates the scope without saving or executing work. Any draft change
   clears the preview and disables saving until a fresh preview succeeds.
5. **Build deliverable task board** saves that exact proposal: outcome, original
   source bytes, task owners, task acceptance, dependencies, model and work graph.
   Nothing runs. Owners remain the plan's accountable people, not authenticated
   assignees. The old plan-row Dispatch draft remains independent.

Changing the loaded plan clears acceptance edits and source assignments. A failed
file replacement preserves the previous draft; cancelling the file picker is a
no-op. **Cancel unsaved task draft** clears only this intake and ignores a late
file read or preview response. It cannot cancel a save already in progress.
Saved deliverables remain available. Unsaved forms are not persisted across page
reloads; save a board after preview to preserve the reviewed proposal.

The task board is durable in the existing local portfolio host, under its data
root. Reload the page and select the saved deliverable. Repeating creation with
the same content returns that board and repairs interrupted materialization;
changed scope creates a different board. Damaged existing files are not overwritten.

## Existing native execution, explicitly configured

Use the existing `MOONPROJ_EXECUTION_CONFIG` owner-only JSON configuration. For
this workflow it must contain `workspace_root` (the approved parent),
`model_selector`, `moonflow_binary`, `catalog_file`, `deliverable_review_file`,
`moonclaw_gateway`, and `moonclaw_workspace_root`.

- Keep `MOONPROJ_PORTFOLIO_DATA` beneath `workspace_root`. Each deliverable gets
  a narrower run workspace at `<data>/deliverables/<deliverable-id>`.
- The existing installed MoonClaw gateway must serve that exact run workspace;
  set `moonclaw_workspace_root` to it. Its native capability policy, installed
  pack, approved provider route, budget and fresh capability catalog remain
  operator prerequisites. This feature provisions none of them.
- Goal requests use that same narrow run workspace. Flow inputs, prerequisite
  outputs, goal receipts and journals therefore resolve against the same root.
  Tasks produce digital files there; this does not grant access to another code
  checkout. The source plan is available as `source-plan.json` inside that root.
- The catalog and review files use the host's existing canonical, owner-only
  regular-file reader. Catalog health can refresh without changing the reviewed
  graph. Each candidate is stored content-addressed and validated by native Flow
  against the exact operation/adapter/schema/authority/claim tuple. A failed first
  import does not make that candidate permanent. Preparation intent and per-request
  catalog records preserve history, including interrupted preparations.
- The review file is an operator declaration, not a company signature. It has
  `contract_id: moonproj.deliverable-review.v1`, `decision: approved`, the exact
  `execution_digest` displayed by the board, `reviewer_id`, `reviewed_at` and
  `provider_calls_approved: false`. Set the last field to true only after explicitly
  approving provider execution for this exact scope. The old global provider flag
  cannot approve a new deliverable. The gateway independently enforces its policy.

**Import / prepare ready tasks** invokes the existing conformant graph importer
and `prepare-next`. This makes declared dependencies real Flow edges. Only Flow
prepares requests. A prerequisite's successful execution alone does not release
its dependents: its exact result must pass the existing native named review.
Task criteria and required evidence are visible on the board.

**Dispatch / reconcile** submits only a prepared task whose direct prerequisites
are accepted. The host verifies exact declarations, prepared identities and input
bytes before calling the existing durable Claw dispatcher. Paused/cancelled or
narrowed native run control blocks it. Concurrent clicks are rejected. A timeout
retains the original attempt and uses status/reconcile on retry; no second submit
is inferred from an unknown result. Native Flow represents an unknown receipt as
Blocked; the panel keeps a **Reconcile same attempt** action for it. That path
cannot submit, including when its local journal is absent. Failed and cancelled
receipts remain terminal. The configured goal step/turn settings are
local execution quanta, not a claim of total runtime budget. Native policy owns
that budget.

Task output review remains the existing `moonflow review-outcome` operation. This
panel does not fabricate or submit review receipts. Refresh the board after review,
then prepare the newly ready tasks. Expired health blocks preparation until the
operator supplies a fresh compatible catalog. New attempts retain that fresh
snapshot. Immediately before a definite first submission, current health is
validated again. A packet saved before a crash/configuration failure can refresh
only its evaluation timestamps and catalog metadata while its exact request,
idempotency identity, configuration and input remain unchanged. A failed freshness
check leaves the journal Prepared and sends nothing, so corrected health can
recover the same unsent work. Paired immutable invocation/catalog snapshots retain
that preparation history. Once submission starts or the outcome is uncertain,
reconciliation restores the original invocation's snapshot and evaluation time;
no timestamp refresh or second submit is permitted. Native installed-pack
and current gateway policy checks still apply. No automatic polling or dispatch
is installed.

## Assemble output and correct only affected work

**Assemble reviewed outputs** requires every current task to have a successful
receipt and a matching named acceptance review. It verifies the top-level native
receipt/journal digest, follows the agent-goal receipt's `artifact_evidence`, and
verifies the referenced content bytes. Receipt-only or journal-only output cannot
stand in for a deliverable. Text, Markdown, JSON and CSV evidence is assembled into
readable Markdown; binary files retain their original references. Each section
keeps its owner/review provenance. Download the assembled Markdown from the panel.
This is mechanical assembly, not an invented editorial synthesis.

**Targeted rework** takes a task and correction text. It invalidates that task plus
all transitive dependents, preserves the original board, and proposes a separate
scope requiring a new exact review. Unaffected tasks must already be accepted;
their verified content bytes are copied into the new run as declared carry-in
inputs. Later rework retains earlier carry-ins. No accepted result is transplanted
as a new native acceptance. Rework is blocked while any old task is active because
uncertain work, including a Blocked/unknown native receipt, must first be reconciled. The old run is preserved, not automatically
cancelled. The operator must configure the gateway for the new run before dispatch.

## Bounds and verification

At most 100 tasks, safe task IDs up to 80 characters, acyclic existing dependencies,
unique identities, named plan owners and nonempty task criteria/evidence are
required. The agent request's installed length/count limits are retained. Unsafe
artifact paths, symlinks, changed source/receipt/output bytes and mismatched native
identities fail closed. Assembly reads at most 2 MB per artifact and 8 MB of new
reviewed evidence per call. Large deliverables need a different assembly path.

Tests run actual production Node helpers, reducer/render functions and the
loopback portfolio HTTP route, including reload. Flow and Claw responses in the
workflow tests are explicitly synthetic adapters shaped from their current source.
They establish local orchestration behavior only. Native import, installed Claw
execution, live company/DB acceptance and graphical-browser/accessibility behavior
have not been qualified. See [wire references](DELIVERABLE_WIRE_REFERENCES.md).

Run the focused checks from the repository root:

```sh
node --test --test-concurrency=1 scripts/deliverable_acceptance.test.mjs scripts/deliverable_evidence_panel.test.mjs scripts/deliverable_workflow.test.mjs scripts/deliverable_http.test.mjs scripts/portfolio_execution.test.mjs scripts/portfolio_dispatch.test.mjs
node --check scripts/portfolio_host.mjs
```

## Plan owner capacity before import (R569)

An original or specialist-delegated, unimported board has **Plan owner capacity**. Enter one positive
integer (1–100) for every displayed task owner, then choose **Create capacity-scoped
board**. For example, `{"writer": 1, "researcher": 2}` gives the writer one
sequential lane and the researcher two lanes. The graph retains all original
prerequisites and adds links between consecutive tasks in each owner's lane.
Task order is stable topological order from the authored plan; lane assignment is
round-robin. This is deliberately conservative and does not optimize durations.

The new board shows each added prerequisite and has a new exact review digest.
It uses the existing import, preparation, dispatch and task-review flow. A lane's
next task is released only when its predecessor's exact result is accepted, not
merely when execution stops. Independent owners/lanes can still proceed together.
The original plan bytes, original board, owners, acceptance and required evidence
are preserved. Repeating the same request returns the same saved proposal, including
after reload. No estimates, authored statuses or formal company assignments change.

Limits apply within this graph only; this is not a global worker quota, resource
reservation, provider budget or duration estimate. Owner names remain accountability
labels, not authenticated actors. Capacity planning refuses already imported boards,
rework scopes and scopes already capacity-planned. Use the same original or
specialist-delegated unimported parent board for a different proposal. It never cancels or migrates existing native attempts.
A new scope requires its own exact operator review and configured run workspace
before execution. A no-op capacity proposal is rejected rather than duplicating
an equivalent board.

Focused source tests include two-lane HTTP persistence/reload, same-scope retries,
old-review rejection, reversed source ordering, malformed limits, unchanged owners
and acceptance, imported-run refusal, and actual helper/panel rendering. Native
Flow/Claw fixtures remain synthetic adapters; no mounted-browser or provider-backed
qualification is implied.

## Parallel specialist delegation (R583)

To give a broad task multiple focused contributors while retaining its accountable
integration owner and acceptance gate, use [specialist delegation](SPECIALIST_DELEGATION.md).
The separate execution proposal adds parallel contributions with their own reviews;
original plan rows, costs and downstream acceptance boundaries remain intact.

## Capacity-plan delegated contributions (R592)

After creating specialist delegation, keep its board unimported and expand
**Plan owner capacity**. Set a limit for every board owner and choose
**Create capacity-scoped board**. All tasks count toward their owner's local lanes,
including specialist contributions and the retained integration task. For two
contributions owned by one writer, a limit of one makes the second wait for the
first contribution's named acceptance. Different owners can retain parallel lanes.

The new proposal displays both the specialist origin and capacity parent, plus
each added edge and its own review digest. It preserves every existing prerequisite,
all contribution criteria/evidence, the original integration task's owner and
acceptance, and downstream dependencies. Integration still waits for every
contribution's named review. The source plan and both earlier proposals remain
unchanged; their operator reviews cannot authorize this changed graph. Creation
never imports or dispatches work.

The supported order is specialist delegation, then capacity planning. Further
delegation or a second capacity pass on the resulting child is refused. To compare
a different capacity, select its same unimported delegated parent again. Limits
that add no dependency edges return a repairable no-op error. A native projection
on that parent, including prepared or uncertain work, blocks planning. A saved-board
change clears the capacity draft; controls from an earlier render cannot edit or
submit the newly selected board. Repeated clicks are serialized, and a late result
cannot reopen a dismissed panel.

This is bounded development progress toward **MOONPROJ-B07**'s exact versioned
review-pending plan handoff and changed-dependency review boundary. Local durable
retry/restart tests are supporting evidence for the **MOONPROJ-N02** concern only;
they do not establish signed-service idempotency. Labeled controls and textual
state support **MOONPROJ-N04**, with graphical-browser, keyboard and accessibility
qualification still unrun. No authored PRD requirement specifically promises this
capacity/specialist composition, and none of those broader requirements is claimed
complete. Native Flow/Claw execution in tests remains synthetic.

## Task-specific local source evidence (R606)

Use the existing **Start from a saved plan** form to delegate work from files you
already have. After pasting the native plan, choose **Local evidence files**.
The browser reads only the files you select; the host accepts their bytes, never
a source path to read on your computer or its own filesystem.

1. Select UTF-8 `.txt`, `.md`, `.markdown`, `.json` or `.csv` files. The supported
   intake is at most 12 distinct filenames, 128 KiB per file and 256 KiB total.
   Empty, invalid UTF-8 and binary-control input is rejected. JSON/CSV are source
   text, not parsed datasets, so malformed JSON/CSV is not silently repaired.
2. Expand and inspect the entire source text, then mark **I inspected this source
   content**. Original bytes are retained, including UTF-8 BOM, CRLF and Unicode.
   The visual text renderer may display whitespace differently; SHA-256 and byte
   counts identify the original bytes. Filename/content markup is escaped.
3. Assign each source to one or more named tasks from the pasted plan. A task may
   have no local file. Every selected file must have at least one valid assignment.
   Removing a file or changing the draft invalidates the previous preview.
4. Choose **Preview complete source/task mapping**. Inspect every task, its owner,
   prerequisites, acceptance, required outputs, and each assigned source's name,
   byte count, digest and generated artifact reference. Preview validates the
   scope without saving files or starting work.
5. Choose **Build deliverable task board** to save that exact preview. The host
   requires a matching preview digest when local evidence is present. Changing
   bytes, filenames, assignments or any existing execution scope yields a new
   digest. Reload, select the board, and use **Inspect saved …** to re-read the
   verified saved source text. This is an ordinary review-pending board using the
   existing operator review, MoonFlow preparation and MoonClaw dispatch controls.

The source scope records `moonproj.local-task-evidence.v1` metadata with original
filename, generated `inputs/local-evidence/<digest>.<extension>` reference,
content digest, byte length and selected task IDs. Each task declares only its
assigned files in `input_artifacts`; its Claw instructions identify those exact
files and treat their content as untrusted evidence rather than instructions or
additional authority. No files are implicitly assigned to newly added specialist
contributions. Before import, use [explicit source assignment](SOURCE_ASSIGNMENT.md)
to give a current task or specialist its saved files in a separately reviewed child.
These are task scope declarations inside one run workspace, not
filesystem confidentiality isolation between tasks.

Capacity and specialist child proposals copy and verify the same source bytes.
Targeted rework retains only files and assignments for tasks in the affected
subgraph; reviewed unaffected outputs continue through the existing carry-in
mechanism. The old plan and all previous boards remain unchanged. Each changed
scope requires its own exact operator review. No-evidence creation keeps the
pre-feature source shape, execution digest, generated graph and requests.

The host verifies saved source evidence during board loading and before prepare,
dispatch, inspection or child copying. Missing, altered and symlinked files block
those operations. Repeating the exact create request repairs missing files from
the supplied original bytes; it refuses to overwrite different existing bytes.
Inspection accepts only a source reference already declared by that board, with
no arbitrary path read endpoint. Intake uses bounded canonical base64 and the
loopback HTTP body's bounded 1 MB limit. This is an owner-local development host,
not a multi-tenant security boundary or adversarial filesystem-race guarantee.

Mounted event tests cover inspection/mapping, preview/save, invalidation,
replacement failure, removal, repeated clicks, detached controls and dismissal
during asynchronous file/preview work. Real loopback HTTP tests cover exact-byte
storage, no-write preview, stale review refusal, cross-origin rejection, declared
inspection and restart. Flow/Claw tests are explicitly synthetic; graphical
browser/accessibility, live native execution, company signatures and provider
calls remain unrun. This contributes bounded local evidence for the source-backed
packet and versioned handoff goals in MOONPROJ-B02/B07. It does not complete those
broader PRD requirements or demonstrate autonomous operation/release readiness.

Additional focused test: `node --test scripts/deliverable_evidence_panel.test.mjs`.

## Task-by-task acceptance forms (R611)

The browser and compiler share execution-subset plan inspection. They reject
ambiguous IDs, missing owners/gates, incompatible gate scopes and dependency
cycles. Forms use stable task IDs, including when display names repeat. The
existing HTTP taskCriteria map remains supported for compatible clients; the UI
constructs it from labeled task fields. Existing no-evidence clients can still
create directly, but a supplied preview digest must match the exact scope. The
UI requires preview before every new board save. The existing 1,000,000-character
HTTP request bound remains; oversized plan/acceptance/evidence combinations produce
a repairable message before submission.

This is bounded progress toward MOONPROJ-UC07 / MOONPROJ-B07's review-pending
versioned plan handoff and MOONPROJ-UC01's usable, reloadable local draft when
execution infrastructure is unavailable. Preview and save do not grant operator
approval, company acceptance, authenticated assignment, provider access, or
financial authority. The saved board uses the existing exact operator review,
MoonFlow preparation, task review and reconciliation boundaries.

Focused Node tests exercise shared helpers, actual mounted controller handlers,
and the real loopback HTTP route through preview/save/restart/blocked preparation.
They include inherited gates, duplicate task names, special object-property IDs,
missing fields, malformed plans, edited scope, cancellation, stale controls,
repeated clicks and retained local source evidence. The DOM harness is not a
browser layout, keyboard or accessibility qualification. Native compiler/build,
MoonFlow/Claw execution, provider calls, formal company service, full UI and
release gates remain unrun and blocking; no release claim follows from these tests.

## Change an accountable owner before import

Use the board's **Hand off a task to another owner** panel to preview and save a
separate, review-pending owner assignment without rewriting the original board.
Do this before capacity or specialist planning. See [Owner handoff](OWNER_HANDOFF.md)
for the exact source, history, planning-order and authority boundaries.

## Give an owner a readable delegation brief (R630)

Select a saved board, open **Prepare an owner delegation brief**, choose its
current accountable owner and preview their tasks, acceptance, prerequisite
owners and downstream handoffs. Local source text is excluded by default and
requires an explicit opt-in. Download re-verifies the exact saved scope and
source bytes. It saves Markdown locally without assigning, sending or starting
work. See [Owner delegation brief](OWNER_DELEGATION_BRIEF.md) for the complete
journey, scope and verification boundaries.

## Revise a saved task's prerequisites before import (R645)

Open **Revise task prerequisites** on an unimported board, select the task and
the inputs it must wait for, and explain the change. Preview the edge differences,
downstream impact and complete proposed graph, then save a separate review-pending
child. The old board and source bytes remain available; its review cannot authorize
the changed graph. See [Prerequisite revision](PREREQUISITE_REVISION.md) for the
complete edit/reload journey, planning order and execution boundaries.
