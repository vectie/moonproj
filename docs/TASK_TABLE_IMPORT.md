# Import a local backlog into a project plan

The existing Projects plan workbench accepts pasted CSV and TSV exports. This
adds editable planning tasks; it does not create service tasks or import their
execution status. It uses the same draft, task editor, browser-local recovery,
native prepare/save, saved-plan history and plan outputs described in
[PROJECT_PLAN_WORKBENCH.md](PROJECT_PLAN_WORKBENCH.md).

1. Open a company project. Add the owners and milestones you need first.
2. Under **Task order / 任务顺序**, choose CSV or TSV. Select the existing owner
   and milestone to use for blank cells. Paste the entire local export including
   its header. CSV and TSV are explicit choices, not guessed from content.
3. Choose **Append imported tasks / 追加导入任务**. Rows append in source order.
   Existing tasks remain unchanged. Errors retain the source and entire old
   draft so you can fix and retry. Successful import reports skipped columns.
4. Edit names, assignments, costs and dependencies using the existing task
   controls. Import invalidates the old prepared preview just like any edit.
5. Download **Editable task CSV / 下载可编辑任务 CSV** for a portable task table,
   or use **Native prepare and save plan** for the complete validated plan and
   existing readable/JSON output.

To bring edits back to existing tasks, use the separate
[preview-and-apply task updates](TASK_TABLE_UPDATES.md) beside these controls.
It matches stable IDs, preserves omitted rows/columns, and shows complete
before/after task records before changing the local draft.

## Columns

Headers are case-insensitive and surrounding header whitespace is ignored.

| Field | Accepted headers | Meaning |
| --- | --- | --- |
| Required task identity | id, task_id, Issue key, Identifier, Key | Stable source key; never generated or renumbered |
| Required title | name, title, Summary | Editable task name |
| Owner | owner, owner_id, Assignee | Existing exact ID or unique display name |
| Milestone | milestone, milestone_id | Existing exact ID or unique name |
| Planning cost | cost, Planned cost | Nonnegative decimal, at most two decimal places; blank is 0 |
| Predecessors | dependencies, Depends on | Semicolon-separated task IDs |

Missing or blank owner/milestone cells use the selected defaults. A supplied
unknown or ambiguous value must be corrected; it is not silently reassigned.
Dependencies may reference earlier imported rows or earlier existing tasks.
Reorder the source when a dependency comes later. Self, missing and forward
references are rejected. Task IDs must be unique across the combined draft;
re-importing an existing ID is not an update. A plan supports 100 tasks.

Other columns, including Status, Description, Priority, sprint and dates, are
ignored and listed after import. These are not fields of the existing planning
task contract and do not become completed-work claims. Keep the original export
if those fields matter. No external issue tracker is contacted.

Quoted cells support commas/tabs, embedded newlines and doubled quotation marks.
UTF-8 BOM, CRLF, LF and CR record endings are accepted. Empty records are skipped.
Malformed quoting, inconsistent row widths, duplicate mapped headers, missing
required fields, invalid costs or invalid assignments reject the whole import.
Errors refer to logical record numbers (the header is record 1).

The export uses quoted CSV cells and owner/milestone IDs so it can be re-imported
into an empty task list with the same owner and milestone definitions. It is
only a task table, not a complete plan archive. Append does not update existing
IDs; use the update preview for a safe editing round trip. Text is exported exactly;
when opening untrusted source text in spreadsheet software, use a text-only CSV
import rather than allowing spreadsheet formula evaluation.

Samples: [issue CSV](samples/backlog-issues.csv) and
[task TSV](samples/backlog-tasks.tsv). Their blank assignments deliberately use
your selected owner/milestone rather than inventing company identities.
