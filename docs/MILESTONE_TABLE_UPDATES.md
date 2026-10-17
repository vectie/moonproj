# Edit a milestone roadmap through CSV or TSV

In **Projects**, open an existing project draft, then expand **Edit milestone
table / 编辑里程碑表** in **Milestones and acceptance criteria**. This adds a
spreadsheet round trip to the ordinary milestone editor. Its default **Edit
existing milestones** mode edits existing rows. To bring in a new roadmap,
choose **Import new milestones**, including when the draft has no milestones.
See [Import a milestone roadmap](MILESTONE_ROADMAP_IMPORT.md).

1. Choose **Download milestone CSV**. Keep the `id` column unchanged.
2. Edit names, owners, individual target dates, acceptance criteria or required
   evidence. You may keep only the rows and columns you want to change.
3. Paste the table including its header into the milestone input. Select CSV or
   TSV explicitly. Use a text-only spreadsheet import to avoid interpreting
   untrusted text as formulas or changing IDs/dates automatically.
4. Choose **Preview milestone edits**. Expand each changed ID to inspect its
   complete Before/After record and changed fields. Unknown columns are listed.
5. Choose **Apply milestone edits**. Changes update the browser-local draft
   together. Milestone IDs/order and every task's milestone reference remain
   unchanged. Omitted milestones and columns retain their previous values.
6. Continue editing, download the revised table or calendar, or choose the usual
   **Native prepare and save plan** when the whole plan is ready. No native save
   happens merely from a preview, table download or Apply.

Unlike uniform date rescheduling, these edits can move one milestone later and
another earlier, leaving every other milestone's date unchanged. They do not
infer task durations, shift dependencies or change execution status.

## Columns and blank-cell rules

Headers are case-insensitive; surrounding header whitespace is ignored.

| Field | Accepted headers | Present cell | Omitted column |
| --- | --- | --- | --- |
| Identity | id, milestone_id, Milestone ID | Existing stable ID, once per table | Required |
| Name | title, name, milestone | Exact text; whitespace-only rejected | Retained |
| Owner | owner, owner_id, Assignee | Existing unique owner ID or display name; blank rejected | Retained |
| Target date | date, target_date, Target date, Due date | Trimmed real YYYY-MM-DD date; blank clears target | Retained |
| Criteria | criteria, Acceptance criteria | Exact text; blank clears criteria | Retained |
| Evidence requirements | evidence, Required evidence | Exact text; blank clears requirements | Retained |

Keep multiline criteria/evidence within a quoted CSV/TSV cell. Quotes within a
quoted cell must be doubled. Commas, tabs, embedded newlines and Unicode survive
round trip. UTF-8 BOM and LF/CRLF/CR record endings are supported. The exported
CSV quotes every cell and uses owner IDs. Target dates are Gregorian calendar
dates from 0001-01-01 through 9999-12-31; leap days are checked. Whitespace is
trimmed only for IDs, owner lookup and supplied dates. Name/criteria/evidence
retain authored spaces and line breaks.

For independent date changes, this partial table changes only two existing
milestones (replace the example IDs with IDs from your export):

```csv
id,date
milestone-one,2026-11-02
milestone-two,2026-11-04
```

An explicitly empty date clears its target. An empty criteria/evidence cell is
also an intentional edit. For example `id,evidence` with `milestone-one,` clears
that milestone's requirements. Use separate partial tables when you want to edit
different columns for different rows: an empty cell is not an omitted column.
Cleared/incomplete requirements are draft work still to fill in, never acceptance
or evidence of completion. Native preparation remains responsible for complete
plan validation. An already-incomplete field can be retained by omitting its
column; a full exported table must satisfy the supplied-cell rules on reimport.

At least one editable column and one existing row are required. Empty records
are skipped. Unknown IDs, duplicate IDs/mapped headers, malformed quoting, wrong
record widths, ambiguous owners and invalid dates reject the entire preview.
The table is limited to 1,000,000 text units and an existing 1–40-milestone draft.
Errors retain the input, draft, prepared result and stored draft for correction.
Unsupported columns such as Status or % complete are ignored and listed; they
cannot create delivery, approval or financial facts.

## State and boundaries

Preview and Close leave the current draft, storage and prepared result alone.
Apply with no changes does nothing. An actual Apply saves through ordinary local
draft recovery, updates its request identity, and invalidates the old prepared
preview. Repeated Apply has no second effect. Editing the input/format or draft
clears the preview. Project/account changes, refresh, opening a saved version
and full-template replacement discard staging. Closing only the preview retains
the pasted text. Reload restores applied edits, not pasted input or a preview.

Downloads always reflect the current draft. Existing owner briefs, calendar,
budget/dependency views and native request projection consume the same edited
milestones; task IDs, assignments, costs, dependencies, owners, risks, notes and
budget are not rewritten. Missing browser storage still produces the ordinary
warning, so do not assume edits survived a reload when that warning appears.

This is local proposal authoring. It makes no issue-tracker/calendar API request,
creates no formal task, grants no authority and records no customer acceptance,
payment or accounting event. Free text and owner/row IDs appear in exports;
inspect them before sharing. The CSV is a milestone editing table, not a complete
plan archive or a transfer of saved immutable history.

Focused evidence uses compiled JavaScript domain APIs and the actual UI
reducer/render/download/storage/request path with synthetic browser adapters.
It does not establish a graphical-browser, live gateway or PostgreSQL result.
