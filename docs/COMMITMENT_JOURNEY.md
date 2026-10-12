# Read-only commitment journey

Open an existing task in the founder cockpit. **这项工作走到哪一步** shows
seven compact stages: source, proposal/feedback, formal work, result/report,
internal acceptance, customer delivery/acceptance, and invoice/cash.
The visible links lead to the existing task controls. Expand a stage to inspect
its evidence, recorded actor/time, event and audit references, and missing links.
No extra acknowledgement or company command is introduced.

## Evidence rules

- The order describes work stages, not a timestamp-derived chronology. Missing,
  reversed, and incomparable times remain as recorded or explicitly unknown.
- Current task source and original creation source remain separate. The creator
  is not assigned as recorder of a later changed source.
- The current proposal uses the existing exact-content/version matcher. Earlier
  proposal and reply records remain visible. Only audited, same-version,
  unsuperseded replies count for the current proposal; a correction retains its
  original. Recorder identity is separate from the claimed respondent and time.
- Formal task state, execution observation, saved report, and internal acceptance
  are separate. Internal acceptance is linked only when task state, exact accepted
  report/source, verified source context, and available matching acceptance audit
  agree. Otherwise the displayed task state remains visible with its linkage gap.
- Report source descriptions use that report's own source. A retained human
  revision digest is shown only for one matching valid revision of the correct
  native run. Selecting another report or source cannot rewrite accepted identity.
- Local draft edits are excluded. Customer delivery/acceptance and financial
  receipts have no current readback contract here and stay explicitly unavailable.
  A ZIP download, proposal reply, internal acceptance, or execution completion
  never establishes delivery, customer acceptance, debt, invoice, or cash.

## Refresh and navigation

The journey projects the existing task readback without its own persistence or
requests. While refreshing or after an unconfirmed operation, it retains the last
successfully read records and labels that limitation. Older task revisions cannot
replace newer records. Task and actor switches use the existing generation fences
and clear the previous evidence before a new read completes. Fragment links reuse
the existing history behavior and do not create tasks or run work.

## Qualification

This is a local read-only slice of **MOONPROJ-R01**, not completion of the full
source-to-cash integration. Tests execute the production receipt-history projector
over synthetic persisted command/audit fixtures, serialize canonical task bytes,
decode/apply them, and render the actual Rabbita UI. They cover actor/task changes,
stale and failed reads, missing/conflicting audit and source links, retained
revisions, proposal corrections, every stage anchor, and escaping.

Compiler, JS reducer/render, native/JS receipt-domain, and release build results
are recorded with the frozen delivery evidence. There is no mounted-browser,
keyboard/assistive-technology, live signed service/PostgreSQL, provider, installed
Mac, customer delivery, payment, or external publication qualification.
