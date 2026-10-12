# Spreadsheet risk register

In **Projects → an existing project draft → Risks and mitigations**, open
**Risk register table**. Download the current risk CSV, edit it in a spreadsheet,
then paste CSV or TSV and choose **Preview risk register**. Inspect the new and
updated counts and each full Before/After record, then **Apply risk register**.
The empty register downloads a header you can use to start a new table.

This is local project-plan editing. It neither records resolution of risks nor
creates company tasks, sends messages, grants authority, executes work or makes
financial changes. Native prepare/save is the existing separate action.

## Columns and matching

- `id`: required stable risk ID. An existing ID updates that row; a new ID appends
  a risk. Keep existing IDs when editing: a changed ID creates an additional risk.
  IDs are trimmed on input. Empty, padded or duplicate existing draft risk IDs
  must be corrected before import.
- `summary`: exact authored text. Required and nonblank for a new risk; a supplied
  blank also rejects for an existing risk. Aliases: `title`, `risk`.
- `severity`: `low`, `medium`, `high` or `critical`, case-sensitive; surrounding
  whitespace is removed. Required for new risks.
- `owner`: existing owner ID or unique exact display name; IDs take precedence.
  Required and nonblank for new risks and when supplied on an existing row.
  Aliases: `owner_id`, `assignee`.
- `mitigation`: exact authored text. A blank clears it. An omitted column retains
  an existing mitigation and leaves a new row blank. Alias: `mitigation plan`.
- `tasks`: existing task IDs separated with semicolons, or a JSON string array
  such as `["TASK-1","TASK-2"]`. A blank or `[]` clears all links. Omitted columns
  retain existing links and leave new rows unlinked. Aliases: `related_task_ids`,
  `related tasks`. Task names are not lookup keys.

`risk_id` and `risk id` are aliases for `id`. Headers ignore surrounding whitespace
and case. Duplicate mapped columns reject. Unknown columns (including `Status`,
acceptance, authority or execution claims) are listed as ignored in the preview
and are not added to the plan or exported. No field is inferred from them.

Existing rows keep their original order regardless of input order. New rows are
appended in input order. Unlisted rows and columns stay unchanged; there is no
implicit delete. Use the existing row editor to remove a risk. Partial updates
can leave other fields incomplete; this tool is not full plan validation.

Mitigation and task links may be empty in this local editing table. Full native
plan validation remains authoritative, including any requirements for risk
mitigation. Blank summaries/owners/severities supplied by the table are errors,
not a request to erase those fields. A failure rejects the whole table without
partially editing or creating any rows.

## Spreadsheet round trip

CSV exports all six columns, using CRLF records and quoted data cells. Quotes,
commas, tabs, line breaks, Unicode and leading/trailing authored summary or
mitigation whitespace are retained. Quotes inside a quoted cell are doubled.
TSV accepts the same quoting rules. BOM and LF/CRLF/CR input are supported.

The export always represents `tasks` as a JSON array inside its quoted CSV cell,
so a task ID containing a semicolon, comma, quote or newline is unambiguous. Use
JSON arrays for such IDs when editing too; semicolon input trims each ID and
ignores empty segments. JSON array entries must match exact existing task IDs.
Missing/ambiguous IDs and repeated links reject; their order is retained.

For a valid register, reimporting its unchanged export is a no-op. This is an
editable risk table, not a backup of the project, a history export or a record of
risk resolution. It does not include plan source notes, costs, owner definitions,
credentials, actor authority or evidence receipts. Cross-project reuse requires
matching owner/task identities in that destination. Maximum input is 1,000,000
UTF-16 text units and 100 rows; resulting plans may contain at most 100 risks.

## State and recovery

Preview/Close/download never change the draft, prepared result or browser
storage. Input/format changes discard the preview. Applying changed rows uses
the existing actor/project-scoped draft persistence, creates a fresh request key
and invalidates prepared output. The table's pasted text stays available during
editing; the preview clears. Repeated Apply therefore does nothing. Storage
failure retains edits in memory with the existing visible warning.

Any draft edit invalidates the preview. Project/account changes, project refresh,
whole-template replacement and successful saved-version open discard table
staging. A stale preview cannot overwrite newer draft content. Reload restores
the applied draft through the existing recovery route, not the transient pasted
input or preview. Downloads always use the current draft.

The existing company identity/gateway is still needed to load Projects in the
real app. This capability does not supply a sample company or establish signed
company service availability. Its tests exercise the real compiled reducer,
rendering, download and request projection with synthetic browser adapters.
