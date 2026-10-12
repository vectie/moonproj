# Find and edit project-plan tasks

In Projects, open an existing project draft. Under **Task order / 任务顺序**, expand
**Find tasks / 查找任务**. Search task names or IDs and select an owner and/or
milestone. Results retain their original draft order; all conditions are combined
with AND. Text is a literal substring, ignoring ASCII case and surrounding search
whitespace. IDs in the two selectors match exactly; equal names do not merge IDs.
A blank search or an All choice removes only that constraint.

Choose **Edit this task** beside a result. The existing task form is shown alone,
with its original task number and complete dependency choices from the whole
draft. Rename, reassign, edit cost, change prerequisites, or reorder through the
ordinary controls. Its stable ID stays focused even if editing makes it stop
matching the search. The live result count can therefore be zero while the focused
form remains open. **Show all task forms** restores the full editor while retaining
the search. Changing a filter clears focus; **Reset finder** clears both.

Adding/appending new tasks or removing the focused task shows all task forms.
Deleting another task preserves focus and the existing missing-dependency repair
controls. A removed selected owner or milestone remains an explicit missing
reference in the selector; the finder never silently broadens to All. Project or
actor change, project refresh, template replacement, successful saved-plan read,
and reload reset the finder. Filters and focus are transient, not draft fields.

## Export the matching task subset

**Download matching tasks** downloads `plan-task-search-results.csv` using the
existing editable task-table columns:

`id,title,owner,milestone,cost,dependencies`

It exports the current matches, independent of the focused form. Original IDs,
assignments, exact cost strings, and dependency references are retained. Prerequisites
outside the matches are not automatically included. The full-plan task CSV button
still exports all tasks. Empty results have no subset download.

Use **Existing-task updates** to preview spreadsheet edits back into the same full
draft. Omitted tasks stay unchanged; this is not a replacement or an append into
an empty plan. Existing CSV conventions remain: quoted multiline text, exact owner
and milestone IDs, and semicolon-separated dependency IDs. Use a full plan template
for lossless portable plan backup, including unusual dependency IDs containing a
semicolon and all owner/milestone/risk context. No CSV schema changes are introduced.

Search, focus and export do not save the draft, invalidate a prepared result,
change request identity, or contact the gateway. Actual edits use the existing
local-save path and invalidate the prepared result. **Native prepare and save plan**
still sends the full draft, including tasks hidden by focus, and remains the
separate complete-plan validation operation. No task execution, company fact,
financial action or review acceptance is created by the finder.

## Verification scope

Focused pure tests cover matching, exact identities, literal/Unicode content,
unresolved assignments, 100 tasks, order, and subset CSV round trip against a full
draft. Compiled production UI reducer/render/download tests cover filters, escaped
HTML and label linkage, stable focused edits, hidden dependency choices, normal
storage and prepare payload, reset/reload/template/saved-response paths, additions,
removals, and unchanged state on read-only actions. Browser APIs and saved responses
are synthetic adapters under Node; this does not establish graphical browser,
keyboard/focus ergonomics, screen-reader or live gateway acceptance.
