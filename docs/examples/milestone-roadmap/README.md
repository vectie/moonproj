# Synthetic roadmap intake

Use an authorized test project and a browser-local draft. These are fictional
planning rows, not company or completion evidence. No provider is needed.

1. Fill the logged-in preparer's name; retain that existing actor row.
2. Preview/apply `owners.csv` through Owner roster table, or replace `owner-test`
   in both input tables with an existing owner ID from your draft.
3. In Edit milestone table choose Import new milestones. Paste `roadmap.csv`,
   preview the two additions, inspect ignored Status, and apply.
4. Paste `tasks.csv` in the existing task table importer. The source milestone
   IDs now resolve directly; the second task follows the first.
5. Export the roadmap and re-preview it in import mode: both IDs are unchanged,
   with zero additions. Change a title and preview again: the conflicting
   existing ID is refused; ordinary Edit existing milestones can perform that
   separate edit.
6. Reopen the same project to inspect recovered applied rows. Explicit native
   preparation additionally requires a complete scope/budget and the existing
   authenticated native gateway. None is established by these input files.

Try malformed date `2027-02-29`, an unknown owner, duplicate rows or an existing
ID with changed content: each preview should refuse without partial changes.
Use CSV text import in spreadsheet apps; quoted strings can still be formulas.
