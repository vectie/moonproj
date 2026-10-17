# Import a milestone roadmap

Bring an existing CSV or pasted TSV roadmap into a new or populated project
draft without manually creating every milestone first. This is an addition-only
mode beside the existing strict update-only editor. It keeps supplied IDs so a
subsequent task CSV can use the same milestone references.

## Use

1. Open **Projects → your project**. Add/import the named owners first, and fill
   in the logged-in preparer's name. Owners are local plan metadata.
2. Expand **Edit milestone table** in **Milestones and acceptance criteria**.
   Choose **Import new milestones**. An empty milestone list is supported.
3. Paste a table including its header and choose **CSV** or **TSV**.
4. Choose **Preview new milestones**. Inspect complete added rows, unchanged
   existing IDs, and ignored columns. This leaves the draft and prepared result
   untouched. **Close preview** retains the pasted input without adding rows.
5. Choose **Apply new milestones**. New rows append in input order, preserving
   their source IDs and every pre-existing row/link. This saves through the
   ordinary browser-local draft recovery and invalidates the prepared preview.
6. Import your task CSV using those milestone IDs. Continue normal editing,
   export the milestone CSV/calendar/template, or explicitly choose **Native
   prepare and save plan** once the whole draft is ready.

A [portable synthetic roadmap, owner roster and task table](examples/milestone-roadmap/README.md)
show the sequence. Import all spreadsheet columns as text: CSV quoting does not
prevent formula interpretation or spreadsheet changes to dates and IDs.

## Columns and replay

Required columns are `id`, `title` and `owner`. Existing milestone header aliases
also work: `milestone_id`/`Milestone ID`; `name`/`milestone`;
`owner_id`/`assignee`. IDs and owner lookup values are trimmed. An owner must
resolve to one existing exact ID or unique display name. A title must be nonblank
and keeps its authored spaces. Import does not create owners or accounts.

Optional `date`, `criteria` and `evidence` columns default to empty draft fields.
Their existing aliases are supported. Dates, when supplied, must be real
Gregorian `YYYY-MM-DD` dates; dates are trimmed. Criteria and evidence keep exact
text, including quoted newlines, commas, tabs and doubled quotes. Missing or
empty criteria/evidence are incomplete requirements, never acceptance. Native
preparation still checks completeness. UTF-8 BOM and LF/CRLF/CR endings work.

- A new ID appends one milestone. Existing order and all tasks, risks, owners,
  notes, budget and other draft fields stay unchanged.
- An existing ID whose complete interpreted row is identical is listed and
  skipped. Reimporting the same roadmap is a no-op, including after reload.
- An existing ID with any different field rejects the entire preview. Switch
  to **Edit existing milestones** to update it deliberately. Omitted optional
  columns mean blank in import mode, not “retain old value.”
- Duplicate IDs within one table reject, even if their rows match. Existing
  draft milestone IDs must also be unique, nonblank and unpadded.
- The input contains 1–40 rows and at most 1,000,000 text units. The resulting
  plan can contain at most 40 milestones. Identical replays count only once.
- Unknown columns, including Status and % complete, are shown and ignored.
  They never record completion, acceptance, approval or company facts.
- Malformed quoting/widths, duplicate mapped headers, missing required columns,
  invalid dates, unknown/ambiguous owners and ID conflicts refuse the complete
  preview. Correct the retained input and preview again; no partial rows apply.

## State and authority

Apply uses the normal local save, rotates the request identity and clears stale
prepared output. Repeated Apply has no second effect. Input/format/mode changes,
ordinary draft edits and Close clear staging. Project/account changes, refresh,
opening a saved version and full-template replacement reset the panel. A stale
preview cannot apply to a newer draft. Pasted text and previews are ephemeral;
only applied rows survive normal actor/project-scoped draft recovery.

A storage failure leaves the visible edit usable and shows the existing warning;
do not assume it survived reload. Preview, Apply and CSV export make no service
request. Native prepare/save remains an explicit separate action. No formal task,
provider call, calendar write, approval, customer acceptance, spend or payment
is created. Source IDs and text appear in exports; inspect before sharing.

Focused development tests cover actual MoonBit domain APIs and the production
UI reducer, renderer, local-storage, download and explicit-request paths using
synthetic browser adapters. This does not qualify a graphical browser, signed
live gateway, PostgreSQL, provider execution or the complete project-plan PRD.
