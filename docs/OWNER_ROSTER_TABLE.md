# Owner roster spreadsheet workflow

In **Projects → your project → Owners → Owner roster table**, download the current
CSV or paste a roster including its header. Choose CSV or TSV, then **Preview
owner roster**. Each addition and changed field shows before/after values. Only
**Apply owner roster** saves the edit to this browser's local draft.

Columns are `id,name,role`. Header aliases `owner_id`/`owner id`,
`display_name`/`display name`, and `responsibility` are also accepted (case
insensitive). UTF-8 BOM, quoted commas, quote escaping and multiline cells are
supported. ID whitespace is trimmed; names and roles retain their exact text.

- Existing IDs update only the supplied columns. Omitted rows and columns remain.
- New IDs require name and role columns and append after the original roster, in
  input order. Names must be nonblank. A blank role explicitly clears the role;
  it leaves an incomplete draft for the existing native validation to check.
- Names need not be unique. Matching is by ID only. Keep an ID to rename a person;
  changing it adds a separate owner and does not move work.
- Tasks, milestones and risks retain their exact owner references. To hand work
  to another existing owner, use the separate **Reassign owner** workflow.
- Unknown columns are listed and ignored, including account/status data. Never
  paste credentials. This is plan metadata; it creates no account or permissions.
- Blank/duplicate IDs, duplicate mapped columns, malformed records and rosters
  over 40 owners are rejected as a whole. Input is limited to 1,000,000 text units.

Preview, Close and CSV download leave the draft and prepared result unchanged.
Apply preserves unmatched owners, updates local storage, rotates the existing
plan request identity and invalidates the old prepared preview. It does not call
the company service or create formal work. Native prepare/save is separate.
Editing input/format or any draft content discards the old preview. Switching
project, actor, refreshing projects or opening a saved version resets the panel.
Pasted text is ephemeral and isn't stored with the draft. A page reload restores
only the applied draft through the existing actor/project-scoped recovery.

The exported `plan-owners.csv` contains only ID, name and role. It is a roster, not
a complete plan backup. An untouched valid roster imports as a no-op. Incomplete
owners with empty names can be exported for repair but must have their names
filled before importing a table that supplies the name column.
