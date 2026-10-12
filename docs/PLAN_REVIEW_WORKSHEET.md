# Offline plan-review worksheet

Projects → **复用完整计划模板** → **下载离线计划审阅表 (.html)** exports
`plan-review.html` from the current editable draft using the existing plan-template
codec. This includes unsaved edits. The action leaves the draft, prepared result,
local storage and saved history unchanged. Structural template errors use the
existing export error message; no partial worksheet is downloaded.

## Review, save and resume

1. Download the worksheet, then open the saved HTML in a browser with JavaScript
   enabled. It has no dependencies or network requests. The complete scope,
   budget strings, owner roles, tasks and dependencies, milestone dates/criteria/
   evidence, and risks/mitigations are displayed as plain source text.
2. Enter a reviewer label. For scope and each owner/task/milestone/risk row,
   choose `not-reviewed`, `no-change-requested`, `question` or `change-requested`,
   and type a note. Every row starts unreviewed. These are feedback labels,
   never approval, work completion or customer acceptance.
3. Click **Download review notes JSON** and verify `plan-review-notes.json` was
   saved. Keep both files. The worksheet does not use browser storage; closing
   without saving can lose edits. It requests a browser close warning after edits,
   including after a download request because download success cannot be confirmed.
   Browsers may suppress this warning, so it is not a recovery guarantee.
4. To resume, reopen the same HTML and choose the saved JSON with **Load saved
   review notes for this snapshot**. A full successful load restores reviewer and
   every note/state. Loading over unsaved edits asks for replacement confirmation.
   Cancel retains current edits. Re-selecting the same file is supported.
5. Give the original HTML plus your JSON to the planning preparer using your own
   approved sharing method. They can open that HTML and load your JSON to inspect
   the feedback, or use its [preparer feedback inbox](PLAN_REVIEW_INBOX.md) to collect
   several returned reviews, record responses and focus unresolved items. Edit the
   current MoonProj plan separately. There is no automatic plan application,
   author identity verification, plan merge, or native approval.

The JSON carries the **exact original template string**, not only a filename or
row labels. Another worksheet accepts it only if that string is identical,
including whitespace. A changed task name, criterion, date, budget or order needs
a fresh review; retain the old pair for earlier feedback. Template-local IDs are
not canonical project/task IDs. Matching bytes establishes snapshot compatibility,
not authenticity or proof of a signed saved version.

Preparer replies can now be [returned as per-reviewer response packets](PLAN_REVIEW_RESPONSE.md),
loaded into this worksheet, and used to resume and revise the original review.
The full plan is included, while unrelated reviewer feedback is excluded.

## Review a changed plan

Use the [revision comparison](PLAN_REVIEW_REVISION.md) to load an older review as
historical reference and explicitly pair old/current rows. Template IDs are
regenerated positional slots, so no identity or current decision is inferred.
Save pairings separately from fresh current review notes; the ordinary saved-notes
loader still accepts only its exact snapshot.

## Limits and authority

The worksheet inherits the complete template limits: 1–40 owners, 100 tasks,
40 milestones, 100 risks, and 1,000,000 UTF-16 source units. Blank amounts and
assignments, unusual dates and unfinished text remain proposals, exactly as
exported. The worksheet neither calculates money nor validates a native plan.
Reviewer labels allow 1,000 UTF-16 units and individual notes 16,384; JSON loads
are bounded to 40,000,000 bytes, enough for fully escaped allowed content.

Malformed JSON, unsupported schemas/fields, wrong snapshot, incomplete/reordered
rows, unknown review states and oversize notes leave the whole current review
unchanged. A read failure is visible. Editing while a file read is pending or
selecting a newer file prevents the earlier read replacing that newer work.

Both files contain the entire authored plan; JSON additionally contains feedback.
Free text can include private information. Inspect the files before sharing.
No source text is fetched or interpreted as markup, including URLs and HTML-looking
notes. A restrictive content security policy disables network connections. Browser
file/download policies may prevent opening or saving the worksheet; no alternative
remote service or automatic upload is attempted.

No company login, credentials, source project/request/saved-version identities or
receipts are added. No native preparation, signed command, task creation, approval,
spend, delivery, accounting, payment or customer response is created. The existing
ERP authority and signed company service boundaries remain unchanged.

## Reproduce the focused qualification

From the repository root:

```sh
node --test scripts/test_plan_review_inbox.mjs scripts/test_plan_review.mjs scripts/test_trello_plan.mjs scripts/test_import_csv.mjs
```

The new suite executes the actual production JavaScript renderer and its embedded
worksheet program in Node with a small synthetic DOM. It checks full source rows,
real Blob download contents, annotate/save/reopen/load, exact snapshot matching,
Unicode and markup-looking text, no partial replacement, pending reads, edit
preservation, and explicit feedback semantics. Trello and CSV tests are regressions.
The MoonBit export call/action/render wiring is asserted from source only; no
MoonBit compilation, mounted browser, accessibility session, PostgreSQL, provider,
real reviewer identity or full product acceptance is qualified here.

PRD rationale: MOONPROJ-UC07/B07's review-pending project planning and N01's draft/
company-authority separation. This supplies a local human review worksheet for
an authored template; it does not fulfill signed execution, commercial closure,
or upgrade any PRD requirement to fully verified.
