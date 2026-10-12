# Edit existing tasks through CSV or TSV

Use the Projects workbench to bring spreadsheet edits back into the current
plan without deleting and recreating tasks. This complements the existing
[append importer](TASK_TABLE_IMPORT.md) and the owner planning brief: stable
task IDs, downstream dependencies and risk references continue to point to the
same tasks after names, assignments or authored planning costs change.

## Round trip

1. Open a project and choose **下载可编辑任务 CSV / Editable task CSV**.
2. Edit the CSV in a text editor or a spreadsheet using text-only import. Keep
   task IDs unchanged. You may keep only the rows and columns you want to edit.
3. Paste the table into the existing task-table input and select CSV or TSV.
4. Choose **预览现有任务修改 / Preview existing task edits**. Inspect the changed
   field names and complete Before/After task records. Ignored source columns
   are listed. The preview does not write browser storage or change the draft.
5. Choose **应用这些任务修改 / Apply these task edits**. All displayed changes
   apply together to the browser-local draft. The input remains available.
6. Continue editing, export a new CSV, inspect the updated owner brief, or use
   the existing explicit **Native prepare and save plan** action when ready.

**关闭修改预览 / Close preview** discards the preview without applying it. A
draft edit, input change, format change, project/account change or opening a
saved plan clears it. Applying twice has no second effect. A table with no
changes leaves the prepared result and browser storage alone.

## Update rules

- `id` plus at least one editable column are required. Header aliases are the
  same as the append importer: Issue key/Identifier/Key, Summary/Title,
  Assignee, Milestone, Planned cost, Depends on, and the canonical names.
- Only existing IDs are accepted, once each. Unknown IDs reject the whole
  preview; use append for new tasks. Unlisted tasks are retained in their
  original order, irrespective of CSV row order. No task is deleted or renamed
  by changing its identity.
- Omitted columns retain their current values. A present title column preserves
  the exact authored text, including quoted newlines and surrounding spaces,
  but a whitespace-only title is rejected.
- Present owner/milestone cells must name an existing unique ID or display
  name. Blank cells reject. The defaults beside the append button do not apply
  to updates, so a blank assignment cannot silently reassign existing work.
- Present costs trim surrounding whitespace, accept nonnegative decimals with
  at most two fractional digits, and use `0` for an explicit blank. Nonblank
  numeric strings are retained without floating-point conversion or rounding.
- Present dependencies replace that task's dependency list; a blank clears it.
  Use semicolon-separated IDs. Every dependency must exist earlier in the
  resulting draft order, and duplicates, self references and cycles reject.
  If needed, reorder the draft before previewing an edited dependency table.
- Status, progress, dates and other unsupported columns are ignored and listed.
  They never become execution or completion claims.

For example, this partial CSV changes one task's cost while leaving all other
rows and columns intact. For different columns per task, use
separate previews so blank cells are not mistaken for omitted columns:

```csv
id,cost
task-review,275.50
```

The same explicit CSV/TSV parser supports quoted delimiters, doubled quotes,
embedded newlines, BOM and LF/CRLF/CR line endings. Invalid records reject the
whole update and retain the input and draft for correction. Header-only input
is not an update.

## Boundaries

This edits a local proposal. It does not contact an issue tracker, save a native
version, create/start formal work, accept delivery, approve budget, pay or post
accounting. Owners, milestones, criteria, risk records, scope and budget fields
remain unchanged. The existing native prepare validates the whole plan later,
including budget and acceptance requirements. Applying any actual edit clears
the previous prepared preview and creates a new local draft request identity.

Local verification covers native domain tests and compiled JavaScript UI
reducer/render/storage/download/request tests with synthetic data. It is not
graphical-browser, live gateway, PostgreSQL or real-company qualification.
