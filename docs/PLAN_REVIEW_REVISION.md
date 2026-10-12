# Re-review a revised plan with earlier feedback

The offline [plan-review worksheet](PLAN_REVIEW_WORKSHEET.md) can load a previous
plan's review as historical reference while you review a new draft. It places
explicitly paired old/current rows, their direct linked context and earlier
observations beside the current review controls. Current notes and decisions
remain independent. This closes the earlier gap where any plan change required
reconstructing previous feedback manually in another worksheet.

## Use

1. Retain the previous `plan-review-notes.json`. Edit the draft in Projects, then
   download a new **offline plan-review worksheet (.html)** from the template
   panel. Open this current HTML. Old HTML exports do not acquire new controls.
2. In **Re-review a revised plan**, choose **Load previous plan review notes JSON**.
   The previous review's embedded complete template is checked before loading.
   The scope/budget blocks are compared immediately. Other current rows start
   **Unresolved**, even if previous and current IDs are the same.
3. Below each current source row, use **Explicitly pair this current row with a
   previous row**. Choose the corresponding previous owner/task/milestone/risk,
   or explicitly mark the current row as added. Pairing is one-to-one and within
   the same category. Unpair an old assignment before reusing it elsewhere.
4. Inspect the complete PREVIOUS and CURRENT row, historical state/note, literal
   field differences and category positions. A changed position is labeled
   **POSITION CHANGED**. Owner, milestone, dependency and risk-task context is
   shown from each snapshot. IDs and references are compared literally; they
   are not automatically remapped through your pairings. Inspect linked context
   and scope independently, including transitive impacts yourself.
5. The **Unpaired or removed previous rows** section keeps complete older rows and
   observations visible. Mark an old row as removed only after checking that it
   was actually removed. **Undo removed label** makes it unresolved again. A row
   marked removed cannot also be paired. Added/removed/pairing labels are your
   assertions about these snapshots, not independently verified business facts.
6. Make fresh decisions using the ordinary review state/note controls above each
   comparison. Loading or pairing historical feedback never fills those controls,
   the current reviewer label, or the preparer inbox. A previous
   `no-change-requested` decision is always labeled historical.
7. Download **revision comparison JSON** and verify `plan-review-revision.json`
   was saved. Separately download the current **review notes JSON**. To resume,
   reopen this exact current HTML, load the comparison using **Resume saved
   revision comparison**, then load current notes using the ordinary saved-notes
   control. Neither load overwrites the other. Keep the current HTML and both JSON
   files. Return current notes to the preparer using your own approved sharing
   method; the existing inbox accepts them for the current snapshot.

## Why pairing is explicit

The product's template export regenerates `owner-1`, `task-1`, `milestone-1` and
`risk-1` from row positions. They are not stable project identities. Inserting a
new first task can make the new `task-1` unrelated to the old `task-1`. No IDs,
labels, matching names or identical row bytes are used to infer correspondence.
Only the sole scope/budget block is paired automatically.

Even identical literal row fields can mean different work when an owner,
milestone or dependency behind the same slot has changed. The worksheet therefore
says **No literal row-field differences**, never that a review remains valid.
Direct linked rows are shown in full; this is not a native plan validator,
semantic diff, automatic migration, dependency-impact closure or plan merge.
Your explicit pairing does not prove these plans belong to the same company,
project or revision lineage. Inspect the supplied plans before pairing them.

## Save format, recovery and limits

`moonproj.plan-review-revision.v1` contains exactly:

- `schema` and the exact current `source_template` string
- `previous_review`: the original complete `moonproj.plan-review-notes.v1` packet
- `pairing`: one entry per current review annotation in source order. Entry zero
  is `0` for scope/budget. Other entries are `null` (unresolved), `"added"`, or an
  integer previous annotation index explicitly chosen by the reviewer
- `removed`: unique previous annotation indexes explicitly marked removed,
  excluding scope and any paired row

The snapshot strings retain their exact whitespace. Reopening a comparison on
another current snapshot rejects before any replacement. Older reviews still
require complete correctly ordered annotations for their own embedded template.
The original same-snapshot review loader, inbox and response-packet loader retain
their exact-byte checks; this new reference mode does not loosen them.

Both template snapshots use the existing bounded v1 structure: up to 1,000,000
UTF-16 units each; 1–40 owners, 100 tasks, 40 milestones and 100 risks. Previous
notes retain the 1,000-unit reviewer label, 16,384-unit per-note limits and 40 MB
file bound. Amounts, dates, unfinished strings and dependency order remain literal
proposals; no costs, validity, approval or company facts are inferred.

Read/validation failures and cancelled replacements preserve all current data.
Replacing or clearing edited pairings asks first. A newer pairing edit, clear or
file choice prevents an older pending read from replacing it. Current notes and
inbox have separate recovery paths. Downloads cannot confirm successful saving;
verify files before closing. A close warning after pairing edits is best effort
and stays active after a download request. There is no browser storage or autosave.

The comparison includes BOTH complete plans and the historical review. It does
not include current review notes, preparer replies or the preparer inbox. Inspect
private free text before manual sharing. Text is not interpreted as markup, and
the worksheet's existing network-disabled policy remains. No external message,
upload, native prepare, signed command, company-state mutation, approval, customer
acceptance or financial action occurs.

## Qualification

Run from the repository root:

```sh
node --test scripts/test_plan_review_revision.mjs scripts/test_plan_review_response.mjs scripts/test_plan_review_inbox.mjs scripts/test_plan_review.mjs scripts/test_trello_plan.mjs scripts/test_import_csv.mjs
```

Ten new workflow tests execute the actual production JavaScript extern renderer
and generated handlers with Node and a synthetic DOM. They cover a revised plan
with reused positional slots, explicit pairing, direct linked-context changes,
added/removed rows, one-to-one choices, actual disk save/reopen, independent current
review return to the existing inbox, cancellation and pending read recovery.
Existing response/inbox/worksheet/Trello/CSV tests run as regressions.

No MoonBit compilation, mounted browser, keyboard/accessibility session, native
plan application, PostgreSQL, provider or full-product execution was run or
qualified. MoonBit signatures/interfaces are unchanged; only the JavaScript
extern body, Node tests and docs changed. No dependency installation or Moon
invocation was needed. R50 is still the last fully verified cumulative result;
R51–55 remain separate.

PRD rationale: `prd_work/content/moonproj.json` MOONPROJ-UC07/B07 requires
review-pending plans bound to their inputs and invalidation when dependencies
change; N01 separates draft evidence and authority. Historical context helps a
reviewer make new decisions without recycling an old decision as current approval.
This does not qualify signed orchestration, commercial closure, adoption, or the
full PRD requirement.
