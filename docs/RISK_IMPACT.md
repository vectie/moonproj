# Explore a plan risk's downstream work

In **Projects**, choose a company project and open or edit its local plan. In
**风险与缓解（可选）**, open **Risk impact explorer / 风险影响分析**. Select a risk
by its ID and summary. The brief shows:

- The risk's authored severity, owner, mitigation and the plan's source/scope notes
- Directly linked tasks, then downstream-only tasks reachable through prerequisites
- The union's authored task costs, grouped by task owner and milestone
- Current project, local plan version and revision timestamp

Choose **Download risk impact brief (.txt)** to keep the exact displayed snapshot
for a planning discussion. The file is UTF-8 plain text, including Unicode and
multiline source notes. It is created locally; the action sends no request and does
not save, edit or dispatch the draft. Review authored free text before sharing.
The existing risk register CSV editor and individual risk fields remain available.

## Edit and explore

Change task costs or dependencies, or toggle a risk's task links below the explorer.
The next preview and export use the current local draft, including unsaved-to-server
edits. The risk selection is navigation state and is not saved with the draft.
**Clear risk selection** clears only that selection. Switching project or actor
clears it; returning to a project restores its local draft through the existing
workbench workflow. If the selected risk was removed, select another or clear it.

## Read the numbers correctly

A risk can reference several tasks, and several paths may reach the same dependent.
Each affected task appears and contributes once. A directly linked task is never
repeated under downstream-only work. Task order follows the local draft. Ancestors
of linked tasks and unrelated tasks are excluded unless independently linked or
reachable downstream. Grouping by owner and by milestone partitions the same
costs; the two views must not be added together.

Amounts use the existing plan convention of 100 minor units per entered unit, with
no FX conversion. Blank or invalid costs remain visibly unavailable and make cost
coverage incomplete. Overflow makes the subtotal unavailable. A risk without task
links is unassessed, never a zero-exposure assertion. Missing, unnamed or ambiguous
owner/milestone references remain labeled for repair.

This is dependency reachability and authored planning scope, not expected loss,
risk probability, duration, actual task status or a forecast. Other risk briefs may
overlap these tasks. No contingency or budget headroom is allocated. Export does
not authorize work, spending, payment, posting or company-state changes.

## Repairable inputs and bounds

Missing risk task links, empty/duplicate task IDs, missing prerequisites, cycles,
and a missing/ambiguous selected risk prevent a misleading partial impact report.
Repair those links in the existing editors and retry. Duplicate links to the same
valid task are deduplicated. The workflow supports at most 100 tasks, 100 risks,
40 owners, 40 milestones and 100 task references in the selected risk.

Focused JavaScript model, reducer, rendering and Blob-download tests cover a
convergent diamond plan, multiple direct links, exact decimal totals, incomplete
estimates, no links, overflow, reference repair, live edits, clearing, restore and
scope switches. Test browser adapters are synthetic; this does not qualify a live
browser, accessibility session, native gateway, PostgreSQL or the full repository.
