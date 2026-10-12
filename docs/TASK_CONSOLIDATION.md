# Consolidate plan tasks

In **Projects → Project plan workbench**, select a company project and open
**合并任务 / Consolidate tasks** below task finding and breakdown. Use this after
spreadsheet import or detailed planning when several rows now represent one
piece of work.

1. Select at least two existing tasks. They must have the same task owner and
   milestone. Use the ordinary task editor to resolve differing assignments first.
2. Choose the selected task ID to keep. Write a combined scope name that covers
   the work in every selected task.
3. Choose **Preview consolidation**. Read the original scopes and costs, the
   surviving/removed IDs, external prerequisites, follower dependencies, risk
   links and complete resulting task order. Preview does not edit or save anything.
4. Choose **Apply consolidation**. The combined task remains editable. The local
   draft is saved through the existing browser store with a new plan version key.
   Download tasks CSV to inspect or continue spreadsheet editing, or use the
   existing explicit native prepare/save action when ready.

## What is preserved

The chosen task ID survives. All selected costs are added in integer minor units
and rendered with two decimal places; there is no floating-point rounding and
no automatic deduction of potentially duplicated estimates. For example,
200.25 + 300.00 becomes 500.25. Edit the result separately if the scope actually
costs less. Currency, plan budget, contingency, owners, milestones, acceptance
criteria, evidence text, scope notes and unaffected task fields are unchanged.

Dependencies within the selection disappear into the combined task. Its external
prerequisites are the union of the selected tasks' prerequisites. Followers wait
for the kept ID. References in linked risks are mapped to the kept ID. Duplicate
links in affected lists are removed, retaining first occurrence order. Unaffected
risk links, including unresolved references, remain visible for later repair.

A stable topological ordering places prerequisites before followers. This can
move other task rows; the preview shows the complete resulting order. A merge of
A and C in A → B → C is rejected because it would create a cycle through B.
Include B too, if that matches the intended scope and assignment, or choose a
different group. Existing missing prerequisites, dependency cycles and duplicate
or empty task IDs must be repaired before consolidation.

## Boundaries and recovery

Only the chosen ID and new name remain as task identity/title. Other selected
IDs and titles are removed from the current local draft; this is a deliberate
structural edit, not an alias mapping for external systems. There is no dedicated
undo. If you need the full earlier plan, prepare/save it first using the existing
workflow, then reopen that saved version from history if needed. Existing saved
versions are immutable. No formal company task, running work or external record
is renamed, merged or cancelled.

Cancel clears the selection and preview. Changing the selection, kept ID or name
requires another preview. Editing the draft, replacing it with a template,
opening a saved plan, switching project, refreshing or changing login identity
invalidates the old preview. Repeated Apply after a successful application has no
effect. Reload discards the temporary selection/preview and restores the ordinary
saved browser draft. An unavailable local store leaves the edited draft on the
page with the existing explicit storage warning; export before leaving.

Each selected cost must be a valid non-negative amount with at most two decimal
places. The combined cost must also fit the existing single-task input range
(999999999999999.99). The plan/selection is bounded to 100 tasks. Invalid input or
a cycle-producing selection shows a repairable error and leaves the draft and
its prepared result unchanged. This operation does not establish that other
native plan checks pass; native prepare/save remains authoritative.

This is local plan authoring. It sends no request, runs no work, grants no approval
and changes no payment, accounting or customer-acceptance state. The subsequent
existing prepare/save action requires the configured company gateway.

## Verification scope

Five pure functional tests and four production UI reducer/render tests exercise
consolidation, exact costs, branch/fanout links, risks, topological ordering,
cycle rejection, identity/assignment limits, local persistence/reload, rendered
preview, CSV download, native request projection, cancellation, stale preview,
template/history replacement and storage failure. UI browser APIs are synthetic
Node adapters. They are not a graphical-browser or live-gateway qualification.
