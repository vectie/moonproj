# Turn a plan task into a Dispatch draft

Use **Projects → Project plan workbench → Plan task to Dispatch draft** when a
planned row is ready to be shaped into an actionable work brief.

1. Select a task from the current plan and choose **Preview task draft**.
2. Inspect the task title, project, exact source snapshot reference, scope notes,
   direct prerequisites, linked and plan-wide risks, and milestone context.
3. Choose **Create local task draft**. Dispatch opens a fresh, editable local
   draft. The plan, saved plan versions, existing drafts and selected formal task
   stay intact.
4. Fill the owner, start date and any execution settings. Check the copied target
   date, which remains authored text. Adapt milestone-wide acceptance criteria
   and required evidence to the selected task. If no unique milestone exists,
   acceptance and due date are blank for you to fill.
5. Check prerequisite completion yourself. When appropriate, use the existing
   explicit signed task-create workflow. Creating this local draft sends no
   company command and starts no work.

## What carries over

The title is copied verbatim. The source reference records the project ID, plan
version key, plan-task ID and plan timestamp as a readable JSON tuple. It is a
local planning reference, not a canonical task ID or proof of a saved plan.
The context retains scope/source notes, planned owner, authored cost and currency,
milestone, direct prerequisite names/IDs and relevant risk/mitigation text. Missing
or ambiguous prerequisites and milestones remain explicitly unresolved.

Milestone criteria and evidence are labelled as context to adapt. They do not
establish task acceptance. The planned owner is context only; the new task's owner
field stays blank because a plan owner is not an authenticated task assignment.
Product binding, agent/model/workspace settings, formal task identity, receipts,
approvals, customer acceptance and financial state are not copied.

The new draft is an independent snapshot. Later plan edits, renaming, splitting or
consolidation do not rewrite its reference or copied text. The reference retains
the version and task selected at creation. Save a plan version first with the
existing prepare/save operation if you need server-backed history; a local-only
reference is not an automatic restore link. You can edit or export the new draft
through Dispatch's existing text and reusable-work-brief tools.

## Cancel, interruption and recovery

Preview and Cancel have no persistence effect. Selecting another task or editing
the plan invalidates the preview. Changing project, refreshing the project list,
opening a saved plan, replacing/appending a template or changing login identity
requires a new preview. Repeated creation from the consumed preview has no effect.
An intentional new preview can create another independent draft of the same task.

The new draft is saved with the existing browser draft collection. Reload and
resume it from Dispatch. Before saving, this flow reads and merges previously
stored drafts, including an earlier collection not yet loaded in the page. If
that collection cannot be read, the handoff stops without overwriting it. If
saving the new draft fails, Dispatch reports that it remains on the page; export
or retain its text before leaving. Local drafts are browser-origin data and may
contain your source notes: review free text before sharing.

## Verification boundary

Focused functional and production reducer/render/transport tests exercise the
snapshot, persistence, reload, selection changes, stale previews, cancellation,
history navigation and failed storage using synthetic browser adapters. They do
not qualify graphical-browser ergonomics, keyboard/screen-reader behavior, a live
signed gateway or dependency completion. No formal execution dependency is
installed by copying a planning prerequisite into the brief.

## Owned deliverables

For a reviewed multi-task execution graph, use the portfolio operator page's
[Delegate a deliverable](DELEGATE_DELIVERABLE.md) workflow. It explicitly adapts
per-task acceptance and installs dependencies only through native Flow import.
This single-row local Dispatch handoff retains the limits described above.
